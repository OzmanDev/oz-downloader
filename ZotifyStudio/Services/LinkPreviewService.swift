import Foundation
import Combine

struct LinkPreview: Identifiable, Equatable {
    var id: String { url }
    let url: String
    let kind: String          // playlist | album | track
    let name: String
    let detail: String        // e.g. owner or artists
    let trackCount: Int
    let trackIds: [String]
    let trackNames: [String]
    let alreadyHave: Int
    let status: MatchStatus
    let error: String?

    enum MatchStatus: Equatable {
        case noneDownloaded
        case partiallyDownloaded
        case fullyDownloaded
        case unknown
    }

    var statusTitle: String {
        switch status {
        case .noneDownloaded: return "Not on this Mac yet"
        case .partiallyDownloaded: return "Partially downloaded"
        case .fullyDownloaded: return "Already downloaded"
        case .unknown: return "Couldn’t check local files"
        }
    }

    var statusSystemImage: String {
        switch status {
        case .noneDownloaded: return "arrow.down.circle"
        case .partiallyDownloaded: return "circle.lefthalf.filled"
        case .fullyDownloaded: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var tracksLabel: String {
        if kind == "track" { return "1 song" }
        if trackCount == 1 { return "1 song" }
        return "\(trackCount) songs"
    }

    var matchLabel: String {
        guard trackCount > 0 else { return statusTitle }
        switch status {
        case .fullyDownloaded:
            return "All \(trackCount) already on this Mac"
        case .partiallyDownloaded:
            return "\(alreadyHave) of \(trackCount) already on this Mac"
        case .noneDownloaded:
            return "None downloaded yet"
        case .unknown:
            return statusTitle
        }
    }
}

@MainActor
final class LinkPreviewService: ObservableObject {
    @Published var previews: [LinkPreview] = []
    @Published var isLoading = false
    /// True while track details load after the title card is visible.
    @Published var isEnriching = false
    @Published var urlsText: String = ""
    @Published var message: String = ""
    /// Shown under the link field when input can’t be looked up.
    @Published var inputError: String?

    private static let oembedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    private static var oembedCache: [String: OEmbedResult] = [:]

    private var debounceTask: Task<Void, Never>?
    private var requestID = UUID()

    /// User-visible preview card (title loaded, not just spinner).
    var hasRenderablePreview: Bool {
        previews.contains { $0.error == nil && $0.name != "Loading…" && !$0.name.isEmpty }
    }

    func clear() {
        debounceTask?.cancel()
        requestID = UUID()
        urlsText = ""
        previews = []
        message = ""
        inputError = nil
        isLoading = false
        isEnriching = false
    }

    /// Instant preview when download starts from My Playlists (no paste field needed).
    func seedForDownload(from queue: [DownloadQueueItem], musicRoot: String) {
        debounceTask?.cancel()
        let urls = queue.map(\.url).filter { !$0.isEmpty }
        guard !urls.isEmpty else { return }

        urlsText = urls.joined(separator: "\n")
        inputError = nil
        message = ""

        let seeds = queue.prefix(5).map { item -> LinkPreview in
            LinkPreview(
                url: item.url,
                kind: Self.kindFromURL(item.url),
                name: item.name.isEmpty ? "Loading…" : item.name,
                detail: "",
                trackCount: max(item.trackCount, 0),
                trackIds: [],
                trackNames: [],
                alreadyHave: 0,
                status: .unknown,
                error: nil
            )
        }
        previews = seeds
        let waitingForTitle = seeds.contains { $0.name == "Loading…" || $0.name.isEmpty }
        isLoading = waitingForTitle
        isEnriching = !waitingForTitle

        let id = UUID()
        requestID = id

        Task { await refresh(urls: urls, musicRoot: musicRoot, requestID: id) }
    }

    func schedulePreview(for urlsText: String, musicRoot: String) {
        self.urlsText = urlsText
        debounceTask?.cancel()
        let trimmed = urlsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            previews = []
            message = ""
            inputError = nil
            isLoading = false
            isEnriching = false
            return
        }

        let urls = Self.extractSpotifyURLs(from: trimmed)
        guard !urls.isEmpty else {
            previews = []
            message = ""
            isLoading = false
            isEnriching = false
            inputError = "That doesn’t look like a Spotify playlist, album, or song link."
            return
        }

        inputError = nil
        isLoading = true
        isEnriching = false
        previews = []
        message = "Looking up…"
        let id = UUID()
        requestID = id

        let looksComplete = urls.count >= 1
            && trimmed.contains("open.spotify.com/")
            && !trimmed.hasSuffix("/")
        let delay: UInt64 = looksComplete ? 0 : 300_000_000

        debounceTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled, requestID == id else {
                return
            }
            await refresh(urls: urls, musicRoot: musicRoot, requestID: id)
        }
    }

    func refreshNow(urlsText: String, musicRoot: String) {
        self.urlsText = urlsText
        debounceTask?.cancel()
        let trimmed = urlsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            previews = []
            inputError = nil
            isLoading = false
            isEnriching = false
            return
        }
        let urls = Self.extractSpotifyURLs(from: trimmed)
        guard !urls.isEmpty else {
            previews = []
            isLoading = false
            isEnriching = false
            inputError = "That doesn’t look like a Spotify playlist, album, or song link."
            return
        }
        inputError = nil
        isLoading = true
        isEnriching = false
        previews = []
        message = "Looking up…"
        let id = UUID()
        requestID = id
        Task { await refresh(urls: urls, musicRoot: musicRoot, requestID: id) }
    }

    /// One-off lookup that does not touch the shared Get Music preview state.
    static func lookup(urlText: String, musicRoot: String) async -> (preview: LinkPreview?, error: String?) {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, "Paste a Spotify playlist, album, or song link.")
        }
        let urls = extractSpotifyURLs(from: trimmed)
        guard let url = urls.first else {
            return (nil, "That doesn’t look like a Spotify playlist, album, or song link.")
        }
        do {
            let meta = try await fetchMetadata(url: url)
            let ids = meta.trackIds
            let names = meta.trackNames
            let have = Self.countAlreadyHave(trackIds: ids, trackNames: names, root: musicRoot)
            let status: LinkPreview.MatchStatus
            if ids.isEmpty {
                status = .unknown
            } else if have == 0 {
                status = .noneDownloaded
            } else if have >= ids.count {
                status = .fullyDownloaded
            } else {
                status = .partiallyDownloaded
            }
            return (
                LinkPreview(
                    url: url,
                    kind: meta.kind,
                    name: meta.name,
                    detail: meta.detail,
                    trackCount: meta.trackCount > 0 ? meta.trackCount : ids.count,
                    trackIds: ids,
                    trackNames: meta.trackNames,
                    alreadyHave: have,
                    status: status,
                    error: nil
                ),
                nil
            )
        } catch {
            // Not signed in / API fail — still resolve public playlists via embed page.
            if let embed = await fetchPublicEmbedMeta(url: url) {
                let ids = embed.trackIds
                let names = embed.trackNames
                let have = Self.countAlreadyHave(trackIds: ids, trackNames: names, root: musicRoot)
                let status: LinkPreview.MatchStatus
                if ids.isEmpty {
                    status = .unknown
                } else if have == 0 {
                    status = .noneDownloaded
                } else if have >= ids.count {
                    status = .fullyDownloaded
                } else {
                    status = .partiallyDownloaded
                }
                return (
                    LinkPreview(
                        url: url,
                        kind: embed.kind,
                        name: embed.name,
                        detail: embed.detail,
                        trackCount: max(embed.trackCount, ids.count),
                        trackIds: ids,
                        trackNames: embed.trackNames,
                        alreadyHave: have,
                        status: status,
                        error: nil
                    ),
                    nil
                )
            }
            return (nil, friendlyError(error.localizedDescription))
        }
    }

    private func refresh(urls: [String], musicRoot: String, requestID: UUID) async {
        // Phase 1: fast title via oEmbed + public embed track list (no Spotify sign-in).
        var quickResults: [LinkPreview] = []
        let targetURLs = Array(urls.prefix(5))
        await withTaskGroup(of: (String, OEmbedResult?, RemoteMeta?).self) { group in
            for url in targetURLs {
                group.addTask {
                    let oembed = try? await Self.fetchOEmbed(url: url)
                    let embed = await Self.fetchPublicEmbedMeta(url: url)
                    return (url, oembed, embed)
                }
            }
            for await (url, oembed, embed) in group {
                if Task.isCancelled || self.requestID != requestID { return }
                let kind = embed?.kind ?? Self.kindFromURL(url)
                let name = embed?.name.isEmpty == false ? (embed?.name ?? "") : (oembed?.title ?? "")
                guard !name.isEmpty || embed != nil else { continue }
                let count = embed?.trackCount ?? 0
                let ids = embed?.trackIds ?? []
                let names = embed?.trackNames ?? []
                quickResults.append(
                    LinkPreview(
                        url: url,
                        kind: kind,
                        name: name.isEmpty ? "Playlist" : name,
                        detail: embed?.detail ?? "",
                        trackCount: count > 0 ? count : ids.count,
                        trackIds: ids,
                        trackNames: names,
                        alreadyHave: 0,
                        status: .unknown,
                        error: nil
                    )
                )
            }
        }

        guard self.requestID == requestID else { return }
        if !quickResults.isEmpty {
            // Apply local disk match if we already have track IDs from public embed.
            previews = quickResults.map { preview in
                guard !preview.trackIds.isEmpty else { return preview }
                let have = Self.countAlreadyHave(
                    trackIds: preview.trackIds,
                    trackNames: preview.trackNames,
                    root: musicRoot
                )
                let status: LinkPreview.MatchStatus
                if have == 0 { status = .noneDownloaded }
                else if have >= preview.trackIds.count { status = .fullyDownloaded }
                else { status = .partiallyDownloaded }
                return LinkPreview(
                    url: preview.url,
                    kind: preview.kind,
                    name: preview.name,
                    detail: preview.detail,
                    trackCount: preview.trackCount,
                    trackIds: preview.trackIds,
                    trackNames: preview.trackNames,
                    alreadyHave: have,
                    status: status,
                    error: nil
                )
            }
            isLoading = false
            inputError = nil
            message = ""
        }

        isEnriching = true

        // Phase 2: enrich with signed-in zotify / Web API (full names + private playlists).
        var enriched: [LinkPreview] = []
        for url in urls.prefix(5) {
            if Task.isCancelled || self.requestID != requestID { return }
            let quick = quickResults.first(where: { $0.url == url })
            do {
                let meta = try await Self.fetchMetadata(url: url)
                let ids = meta.trackIds.isEmpty ? (quick?.trackIds ?? []) : meta.trackIds
                let names = meta.trackNames.isEmpty ? (quick?.trackNames ?? []) : meta.trackNames
                let count = max(meta.trackCount, ids.count, quick?.trackCount ?? 0)
                let have = Self.countAlreadyHave(trackIds: ids, trackNames: names, root: musicRoot)
                let status: LinkPreview.MatchStatus
                if ids.isEmpty {
                    status = count > 0 ? .unknown : .unknown
                } else if have == 0 {
                    status = .noneDownloaded
                } else if have >= ids.count {
                    status = .fullyDownloaded
                } else {
                    status = .partiallyDownloaded
                }
                enriched.append(
                    LinkPreview(
                        url: url,
                        kind: meta.kind,
                        name: meta.name,
                        detail: meta.detail,
                        trackCount: count,
                        trackIds: ids,
                        trackNames: names,
                        alreadyHave: have,
                        status: status,
                        error: nil
                    )
                )
            } catch {
                // Keep public-embed preview (with real song count) instead of falling back to 0.
                if let quick {
                    enriched.append(quick)
                    continue
                }
                let friendly = Self.friendlyError(error.localizedDescription)
                enriched.append(
                    LinkPreview(
                        url: url,
                        kind: "unknown",
                        name: "Not found",
                        detail: "",
                        trackCount: 0,
                        trackIds: [],
                        trackNames: [],
                        alreadyHave: 0,
                        status: .unknown,
                        error: friendly
                    )
                )
            }
        }

        guard self.requestID == requestID else { return }
        if !enriched.isEmpty {
            previews = enriched
        }
        isLoading = false
        isEnriching = false
        if let firstError = enriched.first(where: { $0.error != nil })?.error,
           enriched.allSatisfy({ $0.error != nil }) {
            inputError = firstError
            message = ""
        } else {
            inputError = nil
            message = ""
        }
    }

    private static func kindFromURL(_ url: String) -> String {
        if url.contains("/playlist/") || url.contains("spotify:playlist:") { return "playlist" }
        if url.contains("/album/") || url.contains("spotify:album:") { return "album" }
        if url.contains("/track/") || url.contains("spotify:track:") { return "track" }
        return "unknown"
    }

    private struct OEmbedResult {
        let title: String
        let thumbnailURL: String
    }

    private static func fetchOEmbed(url: String) async throws -> OEmbedResult {
        if let cached = oembedCache[url] {
            return cached
        }
        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        guard let reqURL = URL(string: "https://open.spotify.com/oembed?url=\(encoded)") else {
            throw NSError(domain: "oEmbed", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        let (data, response) = try await oembedSession.data(from: reqURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = obj["title"] as? String, !title.isEmpty
        else {
            throw NSError(domain: "oEmbed", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "oEmbed failed"])
        }
        let thumb = (obj["thumbnail_url"] as? String) ?? ""
        let result = OEmbedResult(title: title, thumbnailURL: thumb)
        oembedCache[url] = result
        return result
    }

    /// Public Spotify embed page — works without sign-in. Used so Get Music shows
    /// real song counts (oEmbed alone never includes track totals).
    private static func fetchPublicEmbedMeta(url: String) async -> RemoteMeta? {
        guard let parsed = parseSpotifyURL(url) else { return nil }
        let embedURLString = "https://open.spotify.com/embed/\(parsed.kind)/\(parsed.id)"
        guard let embedURL = URL(string: embedURLString) else { return nil }
        var request = URLRequest(url: embedURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return nil }

            var name = ""
            // Prefer JSON "name":"..." capture (avoid leaving a trailing quote in the folder name).
            if let re = try? NSRegularExpression(pattern: #""name"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
               let match = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: html) {
                name = String(html[r])
                    .replacingOccurrences(of: #"\""#, with: "\"")
                    .replacingOccurrences(of: #"\\/"#, with: "/")
            }
            if name.isEmpty,
               let re = try? NSRegularExpression(pattern: #""title"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
               let match = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: html) {
                name = String(html[r])
            }
            name = DownloadService.sanitizePlaylistFolderName(name)

            var ids: [String] = []
            var seen = Set<String>()
            let idPattern = try NSRegularExpression(pattern: #"spotify:track:([A-Za-z0-9]+)"#)
            let ns = html as NSString
            idPattern.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                let tid = ns.substring(with: match.range(at: 1))
                if seen.insert(tid).inserted {
                    ids.append(tid)
                }
            }

            // Prefer visible row count when present (embed caps list length sometimes).
            var rowMax = -1
            let rowPattern = try NSRegularExpression(pattern: #"tracklist-row-(\d+)"#)
            rowPattern.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let n = Int(ns.substring(with: match.range(at: 1))) else { return }
                rowMax = max(rowMax, n)
            }
            let rowCount = rowMax >= 0 ? rowMax + 1 : 0
            let count = max(ids.count, rowCount)

            // Titles from tracklist rows (best-effort; may be shorter than full playlist).
            var names: [String] = []
            let titlePattern = try NSRegularExpression(
                pattern: #"TracklistRow_title__[^"]*"[^>]*>([^<]+)<"#
            )
            titlePattern.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                let t = ns.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { names.append(t) }
            }
            while names.count < ids.count {
                names.append("Song \(names.count + 1)")
            }
            if names.count > ids.count {
                names = Array(names.prefix(ids.count))
            }

            guard count > 0 || !name.isEmpty else { return nil }
            return RemoteMeta(
                kind: parsed.kind,
                name: name.isEmpty ? parsed.kind.capitalized : name,
                detail: "",
                trackCount: count,
                trackIds: ids,
                trackNames: names
            )
        } catch {
            return nil
        }
    }

    private static func parseSpotifyURL(_ raw: String) -> (kind: String, id: String)? {
        let pattern = #"(playlist|album|track)[/:]([A-Za-z0-9]+)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges > 2,
              let kindRange = Range(match.range(at: 1), in: raw),
              let idRange = Range(match.range(at: 2), in: raw)
        else { return nil }
        return (String(raw[kindRange]).lowercased(), String(raw[idRange]))
    }


    private static func friendlyError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("sign in") || lower.contains("preferences") {
            return "Sign in with Spotify in Preferences, then try again."
        }
        if lower.contains("not a spotify") || lower.contains("not a valid") {
            return "That doesn’t look like a Spotify playlist, album, or song link."
        }
        if lower.contains("not found") || lower.contains("404") || lower.contains("unavailable")
            || lower.contains("no such") || lower.contains("does not exist") {
            return "Playlist, album, or song not found. Check the link and try again."
        }
        if lower.contains("rate") || lower.contains("429") {
            return "Spotify is busy — wait a moment and try again."
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Couldn’t find that on Spotify."
        }
        return raw
    }

    static func extractSpotifyURLs(from text: String) -> [String] {
        var urls: [String] = []
        let pattern = #"https?://open\.spotify\.com/(playlist|album|track)/[A-Za-z0-9]+[^\s]*|spotify:(playlist|album|track):[A-Za-z0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text.split(whereSeparator: \.isNewline).map(String.init).filter {
                $0.contains("spotify")
            }
        }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var s = ns.substring(with: match.range)
            if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
            if !urls.contains(s) { urls.append(s) }
        }
        return urls
    }

    static func loadLocalTrackIds(root: String) -> Set<String> {
        loadLocalArchiveIndex(root: root).ids
    }

    private struct LocalArchiveIndex {
        var ids: Set<String>
        var titleKeys: Set<String>
    }

    private static func normalizedTitleKey(_ name: String) -> String {
        let base = name.replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return base.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func titleKeysFromDisplayName(_ name: String) -> [String] {
        var keys: [String] = []
        let full = normalizedTitleKey(name)
        if !full.isEmpty { keys.append(full) }
        for sep in ["—", " – ", " - "] {
            if let r = name.range(of: sep) {
                let title = String(name[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let t = normalizedTitleKey(title)
                if !t.isEmpty, !keys.contains(t) { keys.append(t) }
                break
            }
        }
        return keys
    }

    private static func titleKeysFromAudioFilename(_ filename: String) -> [String] {
        var keys: [String] = []
        var base = (filename as NSString).deletingPathExtension
        if let range = base.range(of: #"^\d+_"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        let spaced = base.replacingOccurrences(of: "_", with: " ")
        let full = normalizedTitleKey(spaced)
        if !full.isEmpty { keys.append(full) }
        if let us = base.firstIndex(of: "_") {
            let after = String(base[base.index(after: us)...]).replacingOccurrences(of: "_", with: " ")
            let titleOnly = normalizedTitleKey(after)
            if !titleOnly.isEmpty, !keys.contains(titleOnly) { keys.append(titleOnly) }
        }
        return keys
    }

    private static func loadLocalArchiveIndex(root: String) -> LocalArchiveIndex {
        var ids = Set<String>()
        var titleKeys = Set<String>()
        let rootURL = URL(fileURLWithPath: root)
        let audioExts: Set<String> = ["flac", "ogg", "mp3", "m4a", "wav"]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return LocalArchiveIndex(ids: ids, titleKeys: titleKeys) }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == ".song_ids" {
                guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                for line in data.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    guard parts.count >= 5 else { continue }
                    if !parts[0].isEmpty { ids.insert(parts[0]) }
                    let titleKey = normalizedTitleKey(parts[3])
                    if !titleKey.isEmpty { titleKeys.insert(titleKey) }
                }
                continue
            }
            guard audioExts.contains(fileURL.pathExtension.lowercased()) else { continue }
            for key in titleKeysFromAudioFilename(fileURL.lastPathComponent) {
                titleKeys.insert(key)
            }
        }
        return LocalArchiveIndex(ids: ids, titleKeys: titleKeys)
    }

    private static func countAlreadyHave(trackIds: [String], trackNames: [String], root: String) -> Int {
        let index = loadLocalArchiveIndex(root: root)
        var have = 0
        for (i, id) in trackIds.enumerated() {
            if index.ids.contains(id) {
                have += 1
                continue
            }
            if i < trackNames.count {
                let keys = titleKeysFromDisplayName(trackNames[i])
                if keys.contains(where: index.titleKeys.contains) {
                    have += 1
                }
            }
        }
        return have
    }

    private struct RemoteMeta {
        let kind: String
        let name: String
        let detail: String
        let trackCount: Int
        let trackIds: [String]
        let trackNames: [String]
    }

    private static let tokenCachePath: String = {
        let dir = AppPaths.zotifySupportDir.path
        return dir + "/.token_cache.json"
    }()

    private static func fetchMetadata(url: String) async throws -> RemoteMeta {
        // Fast path: cached Spotify Web API token avoids the ~5-15s zotify login.
        // Falls back to full login only when the cached token is missing or expired.
        let script = #"""
        import json, os, re, sys, time, requests

        raw = sys.argv[1].strip()
        m = re.search(r'(playlist|album|track)[/:]([A-Za-z0-9]+)', raw)
        if not m:
            print("OZ_JSON|" + json.dumps({"ok": False, "error": "Not a Spotify playlist, album, or track link"}))
            raise SystemExit(0)
        kind, sid = m.group(1), m.group(2)

        CACHE = sys.argv[2] if len(sys.argv) > 2 else ""
        OZ_CONFIG = __OZ_CONFIG__

        def load_cached_token():
            if not CACHE or not os.path.exists(CACHE):
                return None
            try:
                with open(CACHE) as f:
                    c = json.load(f)
                if time.time() - c.get("ts", 0) < c.get("expires_in", 3600) - 120:
                    return c["token"]
            except Exception:
                pass
            return None

        def save_token(token, expires_in=3600):
            if not CACHE:
                return
            try:
                with open(CACHE, "w") as f:
                    json.dump({"token": token, "ts": time.time(), "expires_in": expires_in}, f)
            except Exception:
                pass

        def login_and_cache():
            from argparse import Namespace
            from zotify.config import Zotify, Config
            from zotify.termoutput import Printer
            Printer.splash = staticmethod(lambda: None)
            Zotify.CONFIG = Config()
            Zotify.start()
            fields = dict(persist=False, update_config=False, update_archive=False, debug=False,
                          no_splash=True, config_location=OZ_CONFIG, username=None, token=None, urls='',
                          file_of_urls=None, liked_songs=False, user_playlists=False,
                          followed_artists=False, followed_albums=False, search=None, verify_library=False)
            args = Namespace(**fields)
            Zotify.CONFIG.load(args)
            for i in range(4):
                try:
                    Zotify.login(args); break
                except Exception:
                    time.sleep(2)
            else:
                return None
            try:
                tok = Zotify.SESSION.tokens().get_token(
                    'user-read-email', 'playlist-read-private', 'user-library-read'
                ).access_token
                save_token(tok)
                return tok
            except Exception:
                return None

        def api_get(token, endpoint):
            r = requests.get(
                f"https://api.spotify.com/v1/{endpoint}",
                headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
                timeout=10
            )
            if r.status_code in (401, 429):
                return None
            r.raise_for_status()
            return r.json()

        def fetch_with_token(token):
            if kind == "playlist":
                meta = api_get(token, f"playlists/{sid}?fields=name,owner(display_name),tracks(total)")
                if meta is None:
                    return None
                if not meta:
                    return {"ok": False, "error": "Playlist not found"}
                name = (meta.get("name") or "Playlist").strip()
                owner = ""
                o = meta.get("owner")
                if isinstance(o, dict):
                    owner = o.get("display_name") or ""
                count = ((meta.get("tracks") or {}).get("total")) or 0
                ids, names = [], []
                offset = 0
                page_size = 100
                while True:
                    page = api_get(
                        token,
                        f"playlists/{sid}/tracks?limit={page_size}&offset={offset}"
                        f"&fields=total,items(track(id,name,artists(name)))"
                    )
                    if page is None:
                        # Keep whatever we already fetched rather than failing entirely.
                        break
                    if not count:
                        count = page.get("total") or 0
                    items = page.get("items") or []
                    if not items:
                        break
                    for it in items:
                        t = it.get("track")
                        if not isinstance(t, dict) or not t.get("id"):
                            continue
                        ids.append(t["id"])
                        n = (t.get("name") or "").strip() or f"Track {len(ids)}"
                        arts = t.get("artists") or []
                        artist = ", ".join(
                            a.get("name", "") for a in arts if isinstance(a, dict) and a.get("name")
                        )
                        names.append(f"{artist} — {n}" if artist else n)
                    offset += len(items)
                    total = page.get("total") or count or 0
                    if offset >= total or len(items) < page_size:
                        break
                if not count:
                    count = len(ids)
                return {"ok": True, "kind": "playlist", "name": name, "detail": owner,
                        "trackCount": count, "trackIds": ids, "trackNames": names}

            elif kind == "album":
                d = api_get(token, f"albums/{sid}")
                if d is None:
                    return None
                if not d:
                    return {"ok": False, "error": "Album not found"}
                name = (d.get("name") or "Album").strip()
                artists = d.get("artists") or []
                detail = ", ".join(a.get("name","") for a in artists if isinstance(a, dict))
                count = d.get("total_tracks") or 0
                ids, names = [], []
                offset = 0
                page_size = 50
                while True:
                    if offset == 0:
                        items = (d.get("tracks") or {}).get("items") or []
                        total = (d.get("tracks") or {}).get("total") or count
                    else:
                        page = api_get(token, f"albums/{sid}/tracks?limit={page_size}&offset={offset}")
                        if page is None:
                            break
                        items = page.get("items") or []
                        total = page.get("total") or count
                    if not items:
                        break
                    for t in items:
                        if not isinstance(t, dict) or not t.get("id"):
                            continue
                        ids.append(t["id"])
                        n = (t.get("name") or f"Track {len(ids)}").strip()
                        arts = t.get("artists") or artists
                        artist = ", ".join(
                            a.get("name", "") for a in arts if isinstance(a, dict) and a.get("name")
                        )
                        names.append(f"{artist} — {n}" if artist else n)
                    offset += len(items)
                    if offset >= (total or 0) or len(items) < page_size:
                        break
                if not count:
                    count = len(ids)
                return {"ok": True, "kind": "album", "name": name, "detail": detail,
                        "trackCount": count, "trackIds": ids, "trackNames": names}
            else:
                d = api_get(token, f"tracks/{sid}")
                if d is None:
                    return None
                if not d:
                    return {"ok": False, "error": "Song not found"}
                name = (d.get("name") or "Track").strip()
                artists = d.get("artists") or []
                detail = ", ".join(a.get("name","") for a in artists if isinstance(a, dict))
                return {"ok": True, "kind": "track", "name": name, "detail": detail,
                        "trackCount": 1, "trackIds": [sid], "trackNames": [name]}

        # Try fast path: cached token + Web API
        token = load_cached_token()
        if token:
            try:
                result = fetch_with_token(token)
                if result is not None:
                    print("OZ_JSON|" + json.dumps(result))
                    raise SystemExit(0)
            except SystemExit:
                raise
            except Exception:
                pass

        # Slow path: full zotify login + Mercury protocol (not Web API, avoids rate limits)
        from argparse import Namespace as _NS2
        from zotify.config import Zotify as _Z2, Config as _C2
        from zotify.termoutput import Printer as _P2
        _P2.splash = staticmethod(lambda: None)
        _Z2.CONFIG = _C2()
        _Z2.start()
        _fields2 = dict(persist=False, update_config=False, update_archive=False, debug=False,
                      no_splash=True, config_location=OZ_CONFIG, username=None, token=None, urls='',
                      file_of_urls=None, liked_songs=False, user_playlists=False,
                      followed_artists=False, followed_albums=False, search=None, verify_library=False)
        _args2 = _NS2(**_fields2)
        _Z2.CONFIG.load(_args2)
        from zotify.api import Playlist as _Pl, Album as _Al, Track as _Tr
        _logged_in = False
        for _i in range(4):
            try:
                _Z2.login(_args2); _logged_in = True; break
            except Exception:
                time.sleep(2)
        if not _logged_in:
            print("OZ_JSON|" + json.dumps({"ok": False, "error": "Sign in with Spotify in Preferences first"}))
            raise SystemExit(0)

        # Cache the new token for next fast-path attempt
        try:
            _tok = _Z2.SESSION.tokens().get_token(
                'user-read-email', 'playlist-read-private', 'user-library-read'
            ).access_token
            save_token(_tok)
        except Exception:
            pass

        def _walk(obj, out_ids, out_names):
            if isinstance(obj, dict):
                u = obj.get('uri') or ''
                if u.startswith('spotify:track:'):
                    tid = u.split(':')[-1]
                    if tid not in out_ids:
                        out_ids.append(tid)
                        n = (obj.get('name') or '').strip()
                        if not n:
                            a = obj.get('attributes')
                            if isinstance(a, dict): n = (a.get('name') or '').strip()
                        t = obj.get('track')
                        if not n and isinstance(t, dict):
                            n = (t.get('name') or '').strip()
                        out_names.append(n)
                for k, v in obj.items():
                    if k == 'track' and u.startswith('spotify:track:'): continue
                    _walk(v, out_ids, out_names)
            elif isinstance(obj, list):
                for v in obj: _walk(v, out_ids, out_names)

        def _pl_items(resp):
            ids, names = [], []
            if not isinstance(resp, dict): return ids, names
            items = []
            c = resp.get('contents')
            if isinstance(c, dict): items = c.get('items') or []
            if not items and isinstance(resp.get('tracks'), dict):
                items = (resp.get('tracks') or {}).get('items') or []
            if not items and isinstance(resp.get('tracks'), list):
                items = resp.get('tracks') or []
            for it in items:
                if not isinstance(it, dict): continue
                uri = (it.get('uri') or '').strip()
                track = it.get('track') if isinstance(it.get('track'), dict) else None
                tid = ''
                if uri.startswith('spotify:track:'): tid = uri.split(':')[-1]
                elif track:
                    u2 = (track.get('uri') or '').strip()
                    if u2.startswith('spotify:track:'): tid = u2.split(':')[-1]
                    if not tid: tid = (track.get('id') or '').strip()
                if not tid or tid in ids: continue
                n = ''
                a = it.get('attributes') if isinstance(it.get('attributes'), dict) else {}
                n = (a.get('name') or '').strip()
                if not n and track:
                    n = (track.get('name') or '').strip()
                if not n: n = (it.get('name') or '').strip()
                ids.append(tid); names.append(n)
            if not ids: _walk(resp, ids, names)
            return ids, names

        def _fill(ids, names):
            for i, tid in enumerate(ids):
                if i < len(names) and names[i]: continue
                while len(names) <= i: names.append('')
                try:
                    t = _Z2.invoke_libre_md(_Tr, f'spotify:track:{tid}') or {}
                    n = (t.get('name') or '').strip()
                    if not n:
                        a = t.get('attributes') if isinstance(t.get('attributes'), dict) else {}
                        n = (a.get('name') or '').strip()
                    if n: names[i] = n
                except Exception: pass
            return names

        uri = f"spotify:{kind}:{sid}"
        name, detail, ids, names, count = "", "", [], [], 0
        if kind == "playlist":
            resp = _Z2.invoke_libre_md(_Pl, uri) or {}
            if not resp:
                print("OZ_JSON|" + json.dumps({"ok": False, "error": "Playlist not found"}))
                raise SystemExit(0)
            a = resp.get('attributes') if isinstance(resp.get('attributes'), dict) else {}
            name = (resp.get('name') or a.get('name') or "Playlist")
            if isinstance(name, str): name = name.strip() or "Playlist"
            ow = resp.get('owner')
            if isinstance(ow, dict): detail = ow.get('display_name') or ow.get('name') or ''
            if not detail: detail = resp.get('owner_username') or a.get('owner_username') or ''
            ln = resp.get('length') or a.get('length')
            ids, names = _pl_items(resp)
            if any(not n for n in names) or (ids and not names): names = _fill(ids, names)
            try: count = int(ln) if ln else len(ids)
            except: count = len(ids)
            if count < len(ids): count = len(ids)
        elif kind == "album":
            resp = _Z2.invoke_libre_md(_Al, uri) or {}
            if not resp:
                print("OZ_JSON|" + json.dumps({"ok": False, "error": "Album not found"}))
                raise SystemExit(0)
            name = resp.get('name') or "Album"
            arts = resp.get('artist') or resp.get('artists') or []
            if isinstance(arts, list) and arts:
                detail = ", ".join(x.get('name','') for x in arts if isinstance(x, dict))
            _walk(resp, ids, names)
            names = _fill(ids, names)
            count = len(ids) or int(resp.get('total_tracks') or 0)
        else:
            resp = _Z2.invoke_libre_md(_Tr, uri) or {}
            if not resp:
                print("OZ_JSON|" + json.dumps({"ok": False, "error": "Song not found"}))
                raise SystemExit(0)
            name = resp.get('name') or "Track"
            arts = resp.get('artist') or resp.get('artists') or []
            if isinstance(arts, list) and arts:
                detail = ", ".join(x.get('name','') for x in arts if isinstance(x, dict))
            ids, names, count = [sid], [name], 1

        while names and not names[-1]: names.pop()
        names = [n if n else f"Track {i+1}" for i, n in enumerate(names)]
        print("OZ_JSON|" + json.dumps({"ok": True, "kind": kind, "name": name, "detail": detail,
                                        "trackCount": count, "trackIds": ids, "trackNames": names}))
        """#
            .replacingOccurrences(of: "__OZ_CONFIG__", with: AppPaths.pythonPathLiteral(AppPaths.zotifyConfigURL))

        let python = ZotifyCLI.which("python3") ?? URL(fileURLWithPath: "/usr/bin/python3")
        let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CommandResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let r = try ZotifyCLI.run(executable: python, arguments: ["-c", script, url, tokenCachePath])
                    cont.resume(returning: r)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        guard let obj = result.ozJSON() else {
            throw NSError(domain: "LinkPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "No preview data returned"])
        }

        if let ok = obj["ok"] as? Bool, !ok {
            let err = obj["error"] as? String ?? "Preview failed"
            throw NSError(domain: "LinkPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: err])
        }

        return RemoteMeta(
            kind: obj["kind"] as? String ?? "unknown",
            name: obj["name"] as? String ?? "Unknown",
            detail: obj["detail"] as? String ?? "",
            trackCount: obj["trackCount"] as? Int ?? 0,
            trackIds: obj["trackIds"] as? [String] ?? [],
            trackNames: obj["trackNames"] as? [String] ?? []
        )
    }
}
