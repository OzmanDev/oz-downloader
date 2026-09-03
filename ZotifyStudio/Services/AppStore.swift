import Foundation
import Combine
import AppKit

enum JSONStore {
    static func load<T: Decodable>(_ type: T.Type, from url: URL, fallback: T) -> T {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(T.self, from: data)
        else {
            return fallback
        }
        return value
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("JSONStore save failed: \(error)")
        }
    }
}

/// App-owned stores. Always start empty for playlists; settings use neutral defaults only.
@MainActor
final class AppStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { JSONStore.save(settings, to: AppPaths.settingsURL) }
    }

    @Published var playlists: [SavedPlaylist] {
        didSet { JSONStore.save(playlists, to: AppPaths.playlistsURL) }
    }

    @Published var account: SpotifyAccountInfo = .empty
    @Published var avatarImage: NSImage?
    @Published var spotifyPlaylists: [FetchedPlaylist] = []
    /// True while display name / avatar are being loaded after login or on refresh.
    @Published var isRefreshingProfile = false

    init() {
        // Intentionally do NOT import ~/…/Zotify/playlists.json or credentials.
        let loadedSettings: AppSettings
        if FileManager.default.fileExists(atPath: AppPaths.settingsURL.path) {
            loadedSettings = JSONStore.load(AppSettings.self, from: AppPaths.settingsURL, fallback: .empty)
        } else {
            loadedSettings = .empty
        }

        let loadedPlaylists: [SavedPlaylist]
        if FileManager.default.fileExists(atPath: AppPaths.playlistsURL.path) {
            loadedPlaylists = JSONStore.load([SavedPlaylist].self, from: AppPaths.playlistsURL, fallback: [])
        } else {
            loadedPlaylists = []
        }

        settings = loadedSettings
        playlists = loadedPlaylists
        account = JSONStore.load(SpotifyAccountInfo.self, from: AppPaths.accountURL, fallback: .empty)
        spotifyPlaylists = JSONStore.load([FetchedPlaylist].self, from: AppPaths.spotifyPlaylistsURL, fallback: [])
        if let data = try? Data(contentsOf: AppPaths.avatarURL),
           let image = NSImage(data: data) {
            avatarImage = image
        }

        // Detach from the terminal zotify music folder if this install still pointed there.
        let shared = AppPaths.terminalZotifyMusicRoot.standardizedFileURL.path
        if settings.rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || URL(fileURLWithPath: settings.rootPath).standardizedFileURL.path == shared {
            settings.rootPath = AppPaths.defaultMusicRoot.path
        }
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: settings.rootPath, isDirectory: true),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: AppPaths.settingsURL.path) {
            JSONStore.save(settings, to: AppPaths.settingsURL)
        }
        if !FileManager.default.fileExists(atPath: AppPaths.playlistsURL.path) {
            JSONStore.save(playlists, to: AppPaths.playlistsURL)
        }

        syncToZotifyConfig()
        syncAccountFromCredentials()
        ZotifyCLI.scrubLogFiles(in: settings.rootPath)
        // Also clear any zotify logs left from prior runs or other code paths.
        ZotifyCLI.scrubLogFiles(arguments: [])
    }

    var isLoggedIn: Bool {
        FileManager.default.fileExists(atPath: AppPaths.zotifyCredentialsURL.path)
    }

    /// Friendly label for Preferences: display name when known, otherwise Signed in.
    var accountTitle: String {
        guard isLoggedIn else { return "Not signed in" }
        let name = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Signed in" : name
    }

    var accountSubtitle: String {
        guard isLoggedIn else { return "Connect Spotify to load your playlists." }
        if !account.displayName.isEmpty {
            return "Signed in with Spotify"
        }
        return "Your Spotify account is connected."
    }

    /// Read user id from credentials.json; keep cached display name when possible.
    func syncAccountFromCredentials() {
        guard isLoggedIn,
              let data = try? Data(contentsOf: AppPaths.zotifyCredentialsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userId = obj["username"] as? String,
              !userId.isEmpty
        else {
            if account != .empty {
                account = .empty
                try? FileManager.default.removeItem(at: AppPaths.accountURL)
                clearAvatar()
            }
            return
        }

        if account.userId != userId && !account.userId.isEmpty {
            // Different Spotify account — drop old profile.
            account = SpotifyAccountInfo(userId: userId, displayName: "", imageURL: "")
            clearAvatar()
        } else {
            account = SpotifyAccountInfo(
                userId: userId,
                displayName: account.displayName,
                imageURL: account.imageURL
            )
        }
        JSONStore.save(account, to: AppPaths.accountURL)
    }

    func updateAccount(userId: String, displayName: String, imageURL: String? = nil) {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextURL = (imageURL ?? account.imageURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let next = SpotifyAccountInfo(
            userId: userId,
            displayName: cleaned.isEmpty ? account.displayName : cleaned,
            imageURL: nextURL
        )
        guard next != account else { return }
        account = next
        JSONStore.save(account, to: AppPaths.accountURL)
    }

    func replaceSpotifyPlaylists(_ items: [FetchedPlaylist]) {
        spotifyPlaylists = items
        JSONStore.save(items, to: AppPaths.spotifyPlaylistsURL)
    }

    func clearAvatar() {
        avatarImage = nil
        try? FileManager.default.removeItem(at: AppPaths.avatarURL)
    }

    func cacheAvatar(from urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = NSImage(data: data) else { return }
            try data.write(to: AppPaths.avatarURL, options: [.atomic])
            await MainActor.run { self.avatarImage = image }
        } catch {
            // keep previous avatar
        }
    }

    /// Fetch Spotify display name + image via Zotify session (background-safe to call from Task).
    func refreshAccountProfile() async {
        syncAccountFromCredentials()
        guard isLoggedIn else { return }

        isRefreshingProfile = true
        defer { isRefreshingProfile = false }

        let script = #"""
        import json, time, sys
        from argparse import Namespace
        from pathlib import Path
        fields = dict(persist=False, update_config=False, update_archive=False, debug=False,
                      no_splash=True, config_location=__OZ_CONFIG__, username=None, token=None, urls='',
                      file_of_urls=None, liked_songs=False, user_playlists=False,
                      followed_artists=False, followed_albums=False, search=None, verify_library=False)
        args = Namespace(**fields)
        from zotify.config import Zotify, Config
        from zotify.termoutput import Printer
        Printer.splash = staticmethod(lambda: None)
        Zotify.CONFIG = Config()
        Zotify.start()
        Zotify.CONFIG.load(args)
        for i in range(4):
            try:
                Zotify.login(args); break
            except Exception:
                time.sleep(2)
        else:
            print(json.dumps({"ok": False}))
            raise SystemExit(0)
        cred = json.loads(Path(Zotify.CONFIG.get_credentials_location()).read_text())
        username = cred.get('username') or ''
        profile = Zotify.SESSION.api().get_user_profile(username, playlist_limit=1)
        name = ''
        image = ''
        if isinstance(profile, dict):
            name = (profile.get('name') or profile.get('display_name') or '').strip()
            image = (profile.get('image_url') or profile.get('imageUrl') or '').strip()
            if not image:
                imgs = profile.get('images') or []
                if isinstance(imgs, list) and imgs:
                    # Prefer the largest image when sizes are present.
                    best = None
                    best_w = -1
                    for im in imgs:
                        if not isinstance(im, dict):
                            continue
                        u = (im.get('url') or '').strip()
                        if not u:
                            continue
                        w = im.get('width') or 0
                        try:
                            w = int(w)
                        except Exception:
                            w = 0
                        if u and w >= best_w:
                            best = u
                            best_w = w
                    image = best or ((imgs[0].get('url') if isinstance(imgs[0], dict) else '') or '')
            if not image:
                # Walk nested profile for any image url (librespot shapes vary).
                def walk(o):
                    if isinstance(o, dict):
                        for k, v in o.items():
                            if k in ('image_url', 'imageUrl', 'url') and isinstance(v, str) and (
                                'scdn.co' in v or 'spotifycdn' in v or v.startswith('https://i.scdn')
                            ):
                                return v
                            found = walk(v)
                            if found:
                                return found
                    elif isinstance(o, list):
                        for v in o:
                            found = walk(v)
                            if found:
                                return found
                    return ''
                image = walk(profile) or ''
        print(json.dumps({"ok": True, "userId": username, "displayName": name, "imageURL": image}))
        """#
            .replacingOccurrences(of: "__OZ_CONFIG__", with: AppPaths.pythonPathLiteral(AppPaths.zotifyConfigURL))

        let python = ZotifyCLI.which("python3") ?? URL(fileURLWithPath: "/usr/bin/python3")
        do {
            let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CommandResult, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let r = try ZotifyCLI.run(executable: python, arguments: ["-c", script])
                        cont.resume(returning: r)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            guard let start = result.output.lastIndex(of: "{"),
                  let data = String(result.output[start...]).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["ok"] as? Bool) == true
            else { return }
            let userId = obj["userId"] as? String ?? account.userId
            let name = obj["displayName"] as? String ?? ""
            let imageURL = obj["imageURL"] as? String ?? ""
            updateAccount(
                userId: userId,
                displayName: name.isEmpty ? account.displayName : name,
                imageURL: imageURL.isEmpty ? nil : imageURL
            )
            if !imageURL.isEmpty {
                await cacheAvatar(from: imageURL)
            }
        } catch {
            // Keep cached name / avatar if offline / login flake.
        }
    }

    func upsertPlaylist(_ item: SavedPlaylist) {
        if let idx = playlists.firstIndex(where: { Self.sameSpotifyURL($0.url, item.url) }) {
            var merged = playlists[idx]
            if !item.name.isEmpty { merged.name = item.name }
            if item.trackCount > 0 { merged.trackCount = item.trackCount }
            if !item.imageURL.isEmpty { merged.imageURL = item.imageURL }
            playlists[idx] = merged
        } else if let idx = playlists.firstIndex(where: { $0.alias == item.alias }) {
            playlists[idx] = item
        } else {
            playlists.append(item)
        }
        playlists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Save (or refresh) a playlist after a successful download from Get Music.
    func rememberPlaylist(name: String, url: String, trackCount: Int = 0, imageURL: String = "") {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return }
        let display = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = display.isEmpty ? "Playlist" : display
        let img = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let idx = playlists.firstIndex(where: { Self.sameSpotifyURL($0.url, u) }) {
            var existing = playlists[idx]
            existing.name = finalName
            if trackCount > 0 { existing.trackCount = trackCount }
            if !img.isEmpty { existing.imageURL = img }
            playlists[idx] = existing
            return
        }

        var used = Set(playlists.map(\.alias))
        let alias = Self.makeAlias(for: finalName, used: &used)
        upsertPlaylist(SavedPlaylist(alias: alias, name: finalName, url: u, trackCount: trackCount, imageURL: img))
    }

    static func sameSpotifyURL(_ a: String, _ b: String) -> Bool {
        normalizeSpotifyURL(a) == normalizeSpotifyURL(b)
    }

    static func normalizeSpotifyURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s.lowercased()
    }

    static func makeAlias(for playlistName: String, used: inout Set<String>) -> String {
        var bare = playlistName
        if let r = try? NSRegularExpression(pattern: #"^dj[\s_-]*"#, options: .caseInsensitive) {
            bare = r.stringByReplacingMatches(in: bare, range: NSRange(bare.startIndex..., in: bare), withTemplate: "")
        }
        let words = bare.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var base = (words.first ?? "pl").prefix(2).lowercased()
        if words.count >= 2, words[0].lowercased().hasPrefix("amapiano"),
           bare.lowercased().contains("appetizer") {
            base = "ap"
        }
        var alias = String(base)
        var n = 2
        while used.contains(alias) {
            alias = "\(base)\(n)"
            n += 1
        }
        used.insert(alias)
        return alias
    }

    func removePlaylist(alias: String) {
        playlists.removeAll { $0.alias == alias }
    }

    /// Push settings into Oz Downloader’s private Zotify config (never the terminal one).
    func syncToZotifyConfig() {
        let dir = AppPaths.zotifySupportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var dict: [String: String] = [:]
        if let data = try? Data(contentsOf: AppPaths.zotifyConfigURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in existing {
                dict[k] = "\(v)"
            }
        }

        dict["ROOT_PATH"] = settings.rootPath
        dict["CREDENTIALS_LOCATION"] = AppPaths.zotifyCredentialsURL.path
        dict["SAVE_CREDENTIALS"] = "True"
        dict["DOWNLOAD_FORMAT"] = settings.downloadFormat
        dict["DOWNLOAD_QUALITY"] = settings.downloadQuality
        // Cap very high waits that make large playlists look "stuck".
        if (Double(settings.bulkWaitTime) ?? 20) >= 10 {
            settings.bulkWaitTime = "1"
        }
        dict["BULK_WAIT_TIME"] = settings.bulkWaitTime
        dict["DOWNLOAD_RATE_LIMITER"] = settings.downloadRateLimiter
        dict["RETRY_ATTEMPTS"] = settings.retryAttempts
        dict["SKIP_EXISTING"] = settings.skipExisting ? "True" : "False"
        dict["SKIP_PREVIOUSLY_DOWNLOADED"] = settings.skipPreviouslyDownloaded ? "True" : "False"
        dict["API_CLIENT_ID"] = settings.apiClientId
        // Skip expensive Spotify metadata fetches that block large playlists for minutes
        // before any audio downloads (genre + album disc/track totals).
        dict["MD_SAVE_GENRES"] = "False"
        dict["MD_DISC_TRACK_TOTALS"] = "False"
        // New lyrics keys (DOWNLOAD_LYRICS is deprecated and ignored by current zotify).
        dict.removeValue(forKey: "DOWNLOAD_LYRICS")
        dict["LYRICS_TO_METADATA"] = "False"
        dict["LYRICS_TO_FILE"] = "False"
        dict["ALWAYS_CHECK_LYRICS"] = "False"
        // Keep every playlist’s tracks in one folder: {playlist}/01_Artist_Song.ogg
        dict.removeValue(forKey: "OUTPUT_PLAYLIST") // deprecated; OUTPUT_PLAYLIST_EXT is used
        dict["OUTPUT_PLAYLIST_EXT"] = "{playlist}/{playlist_num}_{song_name}"
        // Track/album single downloads (and track-by-track cancel mode) land flat in -rp folder.
        dict["OUTPUT"] = "{song_name}"
        dict["OUTPUT_SINGLE"] = "{song_name}"
        dict["OUTPUT_ALBUM"] = "{album_num}_{song_name}"
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: AppPaths.zotifyConfigURL, options: [.atomic])
        }
    }

    func clearCredentials() {
        try? FileManager.default.removeItem(at: AppPaths.zotifyCredentialsURL)
        account = .empty
        try? FileManager.default.removeItem(at: AppPaths.accountURL)
        clearAvatar()
        spotifyPlaylists = []
        try? FileManager.default.removeItem(at: AppPaths.spotifyPlaylistsURL)
        objectWillChange.send()
    }
}
