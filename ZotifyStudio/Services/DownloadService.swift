import Foundation
import Combine
import AppKit

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

struct SongDownloadItem: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case downloading
        case done
        case skipped
        case failed
    }

    /// Why a row was skipped — shown in Progress details.
    enum SkipReason: Equatable {
        case none
        case duplicate          // same song appears again in the playlist
        case alreadySaved       // skip-existing / already on disk
        case cancelled
    }

    let id: Int
    var number: Int
    var name: String
    var status: Status
    var fraction: Double
    var trackId: String
    var skipReason: SkipReason

    var isFinished: Bool {
        status == .done || status == .skipped || status == .failed
    }

    var isDuplicateSkip: Bool { status == .skipped && skipReason == .duplicate }

    init(
        id: Int,
        number: Int,
        name: String,
        status: Status,
        fraction: Double,
        trackId: String = "",
        skipReason: SkipReason = .none
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.status = status
        self.fraction = fraction
        self.trackId = trackId
        self.skipReason = skipReason
    }
}

struct DownloadQueueItem: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case downloading
        case done
        case failed
        case cancelled
    }

    var id: String { url }
    var name: String
    var url: String
    var trackCount: Int
    var imageURL: String
    var status: Status
    var retryAttempt: Int
    var lastError: String

    init(
        name: String,
        url: String,
        trackCount: Int = 0,
        imageURL: String = "",
        status: Status = .pending,
        retryAttempt: Int = 0,
        lastError: String = ""
    ) {
        self.name = name
        self.url = url
        self.trackCount = trackCount
        self.imageURL = imageURL
        self.status = status
        self.retryAttempt = retryAttempt
        self.lastError = lastError
    }
}

enum DownloadTabBadge: Equatable {
    case none
    case inProgress
    case success
    case failure
}

/// What the download worker is doing right now — drives Progress status copy.
enum DownloadPhase: Equatable {
    case idle
    case starting
    case fetchingTrackInfo
    case checkingExisting
    case downloading
    case converting
    case signingIn
    case retrying
    case stopping
}

@MainActor
final class DownloadService: ObservableObject {
    @Published var logText: String = ""
    @Published var isRunning = false
    @Published var statusMessage: String = ""
    /// High-level activity for Progress UI (checking vs downloading vs converting).
    @Published var downloadPhase: DownloadPhase = .idle
    /// Playlist-load status only (kept separate so downloads don’t pollute My Playlists).
    @Published var playlistStatusMessage: String = ""
    @Published var songItems: [SongDownloadItem] = []
    @Published var queueItems: [DownloadQueueItem] = []
    @Published var currentQueueIndex: Int = 0
    @Published var totalExpected: Int = 0
    @Published var totalCompleted: Int = 0
    /// Human-readable download rate, e.g. "1.2 MB/s". Empty when unknown / idle.
    @Published var downloadSpeedLabel: String = ""
    /// Final error after retries are exhausted — shown in Progress UI / toast.
    @Published var downloadErrorMessage: String = ""
    @Published var retryStatusMessage: String = ""
    /// Separate convert/post-process step (not a fake song row).
    @Published var isConverting = false
    @Published var convertFraction: Double = 0
    @Published var convertLabel: String = ""
    /// Convert step had nothing to do (no new OGG/FLAC folders).
    @Published var convertSkipped = false
    /// Whether this job will run FLAC convert after download (drives convert step in UI).
    @Published var autoConvertEnabled = false
    /// Persist Show details across tab switches (session only).
    @Published var showProgressDetails = false
    @Published var tabBadge: DownloadTabBadge = .none
    @Published var showCelebration = false
    @Published var toastMessage: String = ""
    @Published var toastVisible: Bool = false
    @Published var isSigningIn = false
    /// Spotify authorize URL while OAuth is waiting — used to reopen the page.
    @Published var pendingAuthURL: String?
    /// Set when a download starts so ContentView can switch to Get Music (Progress lives there).
    @Published var requestShowGetMusic = false

    /// Short label for the Progress header / queue “Now” row.
    var phaseStatusLabel: String {
        let playlist = queueItems.indices.contains(currentQueueIndex)
            ? queueItems[currentQueueIndex].name
            : ""
        switch downloadPhase {
        case .idle:
            return statusMessage.isEmpty ? "" : statusMessage
        case .starting:
            return playlist.isEmpty ? "Starting…" : "Starting \(playlist)…"
        case .fetchingTrackInfo:
            return "Fetching track list…"
        case .checkingExisting:
            return "Checking library…"
        case .downloading:
            let newCount = songItems.filter {
                $0.status == .pending || $0.status == .downloading
                    || $0.status == .done || $0.status == .failed
            }.count
            if newCount > 0 {
                return newCount == 1
                    ? "Downloading 1 new song…"
                    : "Downloading \(newCount) new songs…"
            }
            return playlist.isEmpty ? "Downloading…" : "Downloading \(playlist)…"
        case .converting:
            return convertLabel.isEmpty ? "Converting…" : convertLabel
        case .signingIn:
            return "Sign in with Spotify…"
        case .retrying:
            return retryStatusMessage.isEmpty
                ? (playlist.isEmpty ? "Retrying…" : "Retrying \(playlist)…")
                : retryStatusMessage
        case .stopping:
            return "Cancelling…"
        }
    }

    /// One-line Progress summary under the card title.
    var phaseProgressSummary: String {
        let skipped = songItems.filter { $0.status == .skipped }.count
        let left = songItems.filter {
            $0.status == .pending || $0.status == .downloading || $0.status == .failed
        }.count
        switch downloadPhase {
        case .idle:
            return ""
        case .starting:
            return "Getting ready…"
        case .fetchingTrackInfo:
            return "Loading song titles from Spotify…"
        case .checkingExisting:
            if skipped > 0 || left > 0 {
                return "\(skipped) skipped · \(left) left"
            }
            return "Checking which songs you already have. You can leave this window open."
        case .downloading:
            return "\(skipped) skipped · \(left) left"
        case .converting:
            return convertLabel.isEmpty
                ? "Converting downloaded files to FLAC, embedding lyrics, and renaming…"
                : convertLabel
        case .signingIn:
            return "Complete Spotify sign-in in your browser, then this will continue."
        case .retrying:
            return retryStatusMessage.isEmpty
                ? "Connection issue — retrying…"
                : retryStatusMessage
        case .stopping:
            return "Stopping…"
        }
    }

    private func setPhase(_ phase: DownloadPhase) {
        downloadPhase = phase
        switch phase {
        case .idle:
            break
        case .starting, .fetchingTrackInfo, .checkingExisting, .downloading,
             .converting, .signingIn, .retrying, .stopping:
            statusMessage = phaseStatusLabel
        }
    }
    private var cancelFlag = CancellationFlag()
    /// Skip the current playlist and continue the queue.
    private var skipPlaylistFlag = CancellationFlag()
    /// Skip the current song and continue remaining songs.
    private var skipSongFlag = CancellationFlag()
    private var signInCancelFlag = CancellationFlag()
    /// True while zotify printed a Spotify authorize URL and is waiting on the browser.
    private var awaitingSpotifyLogin = CancellationFlag()
    /// Abort current zotify so we can run the polished Preferences OAuth flow instead.
    private var reauthHandoff = CancellationFlag()
    /// Store for mid-download sign-in handoff (same success page as manual login).
    private weak var activeStore: AppStore?
    private var activeSongIndex: Int?
    private var downloadHadError = false
    private var toastHideTask: Task<Void, Never>?
    /// When true, do not invent extra song rows from CLI "Total Query Progress".
    private var songCountLocked = false
    private var sessionTrackIds: [String] = []
    private var lastZotifyOutput = ""
    /// Avoid spamming Spotify title lookups while tqdm advances.
    private var titlePrefetchInFlight = false
    /// Used so live disk sync can tell “already on disk” vs “just downloaded”.
    private var jobStartedAt = Date.distantPast
    /// Music root for the active download job (for disk recovery helpers).
    private var activeMusicRoot = ""
    /// Titles / track ids that existed before the current playlist attempt started.
    private var preexistingAudioTitleKeys = Set<String>()
    private var preexistingTrackIds = Set<String>()

    var totalFraction: Double {
        if isConverting {
            return min(1, max(0.05, convertFraction))
        }
        let expected = max(totalExpected, songItems.count, 1)
        let finished = songItems.filter(\.isFinished).count
        if expected > 0 {
            var fraction = Double(finished) / Double(expected)
            if let idx = activeSongIndex, songItems.indices.contains(idx), songItems[idx].status == .downloading {
                fraction = min(1, fraction + (songItems[idx].fraction / Double(expected)))
            }
            return min(1, fraction)
        }
        if isRunning { return 0.02 }
        return songItems.isEmpty ? 0 : (songItems.allSatisfy(\.isFinished) ? 1 : 0)
    }

    private func refreshTotalProgressFromSongs() {
        let expected = max(totalExpected, songItems.count, 1)
        totalExpected = expected
        totalCompleted = min(expected, songItems.filter(\.isFinished).count)
    }

    func clearLog() {
        logText = ""
        statusMessage = ""
        downloadPhase = .idle
        songItems = []
        queueItems = []
        currentQueueIndex = 0
        totalExpected = 0
        totalCompleted = 0
        downloadSpeedLabel = ""
        downloadErrorMessage = ""
        retryStatusMessage = ""
        isConverting = false
        convertFraction = 0
        convertLabel = ""
        convertSkipped = false
        songCountLocked = false
        activeSongIndex = nil
    }

    func clearTabBadge() {
        tabBadge = .none
    }

    func reopenSignInPage() {
        guard let raw = pendingAuthURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
        showToast("Sign-in page opened again")
    }

    func cancelSignIn() {
        guard isSigningIn else { return }
        signInCancelFlag.value = true
        // Free the local OAuth callback port in case Python is stuck listening.
        DispatchQueue.global(qos: .utility).async {
            Self.freeOAuthPort(4381)
        }
        appendLog("Sign-in cancelled.")
        showToast("Sign-in cancelled — you can try again")
    }

    nonisolated private static func freeOAuthPort(_ port: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        task.arguments = ["-tiTCP:\(port)", "-sTCP:LISTEN"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            for pid in text.split(whereSeparator: \.isNewline) {
                let killer = Process()
                killer.executableURL = URL(fileURLWithPath: "/bin/kill")
                killer.arguments = ["-TERM", String(pid)]
                killer.standardOutput = Pipe()
                killer.standardError = Pipe()
                try? killer.run()
                killer.waitUntilExit()
            }
        } catch {}
    }

    /// Kill leftover zotify / hung Spotify sessions that block new downloads.
    nonisolated static func killOrphanZotifyProcesses() -> Bool {
        let patterns = [
            "/opt/anaconda3/bin/zotify",
            "from zotify.config import Zotify",
            "UserPlaylist('gui')",
            "-m zotify",
            "Oz Downloader.app/Contents/Resources/runtime/bin/python",
            "Oz Downloader.app/Contents/Resources/runtime/bin/zotify",
            "Contents/Resources/runtime/bin/python",
            "Contents/Resources/runtime/bin/zotify"
        ]
        // Parallel pkills — sequential waitUntilExit made every download start feel slow.
        let group = DispatchGroup()
        for pattern in patterns {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                task.arguments = ["-f", pattern]
                task.standardOutput = Pipe()
                task.standardError = Pipe()
                try? task.run()
                task.waitUntilExit()
                group.leave()
            }
        }
        // Must wait for all pkills — timing out let late kills murder the new download.
        let waitResult = group.wait(timeout: .now() + 5.0)
        return waitResult == .timedOut
    }

    /// True when a leftover zotify-like process is still around (cheap check before killing).
    nonisolated static func hasOrphanZotifyProcesses() -> (Bool, String) {
        let probes = [
            "anaconda3/bin/zotify",
            "-m zotify",
            "UserPlaylist('gui')",
            "Oz Downloader.app/Contents/Resources/runtime/bin/zotify",
            "Oz Downloader.app/Contents/Resources/runtime/bin/python"
        ]
        for pattern in probes {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-f", pattern]
            let out = Pipe()
            task.standardOutput = out
            task.standardError = Pipe()
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let pids = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (true, "\(pattern) → \(pids)")
            }
        }
        return (false, "")
    }

    /// Never call `killOrphanZotifyProcesses` on the main thread — `waitUntilExit` blanks the UI.
    private func killOrphanZotifyProcessesAsync(source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let killT0 = Date()
            let timedOut = Self.killOrphanZotifyProcesses()
        }
    }

    /// Kill leftovers *before* spawning a new download — must finish first (async race kills the new job).
    private func killOrphanZotifyProcessesAwaiting(source: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let killT0 = Date()
                let (hadOrphans, probeHit) = Self.hasOrphanZotifyProcesses()
                var timedOut = false
                if hadOrphans {
                    timedOut = Self.killOrphanZotifyProcesses()
                }
                cont.resume()
            }
        }
    }

    func showToast(_ message: String, duration: TimeInterval = 3.0) {
        toastHideTask?.cancel()
        toastMessage = message
        toastVisible = true
        toastHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            toastVisible = false
        }
    }

    func appendLog(_ line: String) {
        if !logText.isEmpty { logText += "\n" }
        logText += line
    }

    func stop() {
        cancelFlag.value = true
        skipPlaylistFlag.value = true
        skipSongFlag.value = true
        showCelebration = false
        killOrphanZotifyProcessesAsync(source: "stop")
        convertSkipped = true
        if convertLabel.isEmpty || convertLabel == "Convert cancelled" {
            convertLabel = "Convert skipped"
        }
        if !isConverting {
            convertFraction = 1
        }
        for i in songItems.indices where !songItems[i].isFinished {
            songItems[i].status = .skipped
            songItems[i].skipReason = .cancelled
            songItems[i].fraction = 1
        }
        for i in queueItems.indices where queueItems[i].status == .pending || queueItems[i].status == .downloading {
            queueItems[i].status = .cancelled
            queueItems[i].lastError = "Cancelled"
        }
        totalCompleted = songItems.filter { $0.status == .done || $0.status == .skipped }.count
        setPhase(.stopping)
        showToast("Cancelled")
    }

    /// Cancel one playlist in the queue — skips it and continues with the rest.
    func cancelPlaylist(at index: Int) {
        guard queueItems.indices.contains(index) else { return }
        let item = queueItems[index]
        guard item.status == .pending || item.status == .downloading else { return }
        queueItems[index].status = .cancelled
        queueItems[index].lastError = "Cancelled"
        appendLog("Cancelled playlist — \(item.name)")
        showToast("Cancelled — \(item.name)")
        showCelebration = false
        let onlyOneActive = queueItems.filter {
            $0.status == .pending || $0.status == .downloading || $0.id == item.id
        }.count <= 1
        if index == currentQueueIndex, isRunning {
            skipPlaylistFlag.value = true
            skipSongFlag.value = true
            // Single playlist cancel should fully stop (same as Cancel), not “succeed”.
            if onlyOneActive || queueItems.count == 1 {
                cancelFlag.value = true
                statusMessage = "Stopping…"
                for i in songItems.indices where !songItems[i].isFinished {
                    songItems[i].status = .skipped
                    songItems[i].skipReason = .cancelled
                    songItems[i].fraction = 1
                }
                totalCompleted = songItems.filter { $0.status == .done || $0.status == .skipped }.count
            } else {
                statusMessage = "Skipping playlist…"
            }
            killOrphanZotifyProcessesAsync(source: "cancelPlaylist")
        }
    }

    /// Cancel/skip one song — continues with later songs in the playlist.
    func cancelSong(id: Int) {
        guard let idx = songItems.firstIndex(where: { $0.id == id }) else { return }
        guard !songItems[idx].isFinished else { return }
        let wasActive = (activeSongIndex == idx) || songItems[idx].status == .downloading
        songItems[idx].status = .skipped
        songItems[idx].skipReason = .cancelled
        songItems[idx].fraction = 1
        appendLog("Skipped song — \(songItems[idx].name)")
        showToast("Skipped — \(songItems[idx].name)")
        if wasActive, isRunning {
            skipSongFlag.value = true
            statusMessage = "Skipping song…"
            killOrphanZotifyProcessesAsync(source: "cancelSong")
        }
        // Pending songs: already marked skipped; track-by-track loop will ignore them.
    }

    /// Wipe Progress so a cancelled job never remains visible while the next one starts.
    func clearStaleProgressUI() {
        songItems = []
        queueItems = []
        totalExpected = 0
        totalCompleted = 0
        downloadSpeedLabel = ""
        downloadErrorMessage = ""
        retryStatusMessage = ""
        isConverting = false
        convertFraction = 0
        convertLabel = ""
        convertSkipped = false
        showCelebration = false
        activeSongIndex = nil
        if isRunning {
            statusMessage = "Stopping…"
        } else {
            statusMessage = "Starting…"
        }
    }

    /// Immediately replace Progress UI for a new job (before async work) so old lists never flash.
    func prepareJobUI(
        queue: [DownloadQueueItem],
        expectedTracks: Int,
        trackNames: [String],
        trackIds: [String] = []
    ) {
        skipPlaylistFlag.value = false
        skipSongFlag.value = false
        downloadErrorMessage = ""
        retryStatusMessage = ""
        downloadSpeedLabel = ""
        isConverting = false
        convertFraction = 0
        convertLabel = ""
        convertSkipped = false
        currentQueueIndex = 0
        var items = queue
        for i in items.indices {
            items[i].status = .pending
            items[i].retryAttempt = 0
            items[i].lastError = ""
            items[i].name = Self.sanitizePlaylistFolderName(items[i].name)
        }
        queueItems = items
        prepareProgress(expectedTracks: expectedTracks, trackNames: trackNames, trackIds: trackIds)
        if !items.isEmpty {
            beginQueueItem(at: 0)
            setPhase(.starting)
        }
    }

    func prepareProgress(expectedTracks: Int, trackNames: [String], trackIds: [String] = []) {
        var cleaned = trackNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var ids = trackIds

        // Keep real titles/ids already shown (prepareJobUI + background prefetch).
        // Callers often pass [] / "Song N" placeholders on retry and would wipe names.
        let incomingHasRealTitles = cleaned.contains {
            !$0.isEmpty && !$0.hasPrefix("Song ") && !$0.hasPrefix("Track ")
        }
        if !incomingHasRealTitles {
            let existingNames = songItems.map(\.name)
            if existingNames.contains(where: {
                !$0.isEmpty && !$0.hasPrefix("Song ") && !$0.hasPrefix("Track ")
            }) {
                cleaned = existingNames
            } else if cleaned.isEmpty, !existingNames.isEmpty {
                cleaned = existingNames
            }
        }
        if ids.allSatisfy(\.isEmpty) {
            let existingIds = songItems.map(\.trackId)
            if existingIds.contains(where: { !$0.isEmpty }) {
                ids = existingIds
            } else if !sessionTrackIds.isEmpty {
                ids = sessionTrackIds
            }
        }

        let known = cleaned.filter { !$0.isEmpty && !$0.hasPrefix("Song ") }
        sessionTrackIds = ids.filter { !$0.isEmpty }.isEmpty ? sessionTrackIds : ids
        let count: Int
        if !ids.filter({ !$0.isEmpty }).isEmpty {
            count = max(ids.count, expectedTracks, cleaned.count, 1)
            songCountLocked = true
        } else if !known.isEmpty {
            count = max(known.count, cleaned.filter { !$0.isEmpty }.count, expectedTracks, 1)
            songCountLocked = true
        } else if expectedTracks > 0 {
            count = expectedTracks
            songCountLocked = expectedTracks > 0
        } else {
            count = 1
            songCountLocked = false
        }
        totalExpected = max(count, 1)
        totalCompleted = 0
        activeSongIndex = nil
        isConverting = false
        convertFraction = 0
        convertLabel = ""
        convertSkipped = false

        // Preserve finished-row status when rebuilding the same job (retry / title refresh).
        let previousByIndex = songItems
        songItems = (0..<totalExpected).map { idx in
            let raw = idx < cleaned.count ? cleaned[idx] : ""
            let title: String
            if !raw.isEmpty, !raw.hasPrefix("Song "), !raw.hasPrefix("Track ") {
                title = raw
            } else if previousByIndex.indices.contains(idx),
                      !previousByIndex[idx].name.hasPrefix("Song "),
                      !previousByIndex[idx].name.hasPrefix("Track "),
                      !previousByIndex[idx].name.isEmpty {
                title = previousByIndex[idx].name
            } else {
                title = "Song \(idx + 1)"
            }
            let tid = idx < ids.count && !ids[idx].isEmpty
                ? ids[idx]
                : (previousByIndex.indices.contains(idx) ? previousByIndex[idx].trackId : "")
            var item = SongDownloadItem(
                id: idx + 1,
                number: idx + 1,
                name: title,
                status: .pending,
                fraction: 0,
                trackId: tid
            )
            if previousByIndex.indices.contains(idx) {
                let prev = previousByIndex[idx]
                if prev.isFinished {
                    item.status = prev.status
                    item.fraction = prev.fraction
                    item.skipReason = prev.skipReason
                }
            }
            return item
        }
        markDuplicateTracksAsSkipped()
        markNextDownloading()
    }

    /// Later playlist entries that repeat an earlier Spotify track id → Skipped (duplicate).
    /// Title-only matching is intentionally disabled — it falsely marked ~half the playlist
    /// when track ids weren’t loaded yet (logs: uniqueIds=0, duplicates=109).
    private func markDuplicateTracksAsSkipped() {
        // Restore ids if Progress rows were rebuilt without them.
        for i in songItems.indices where songItems[i].trackId.isEmpty && i < sessionTrackIds.count {
            songItems[i].trackId = sessionTrackIds[i]
        }
        var seenIds = Set<String>()
        var dupCount = 0
        var skippedAlreadySaved = 0
        let idCount = songItems.filter { !$0.trackId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        for i in songItems.indices {
            if songItems[i].status == .skipped, songItems[i].skipReason == .cancelled {
                continue
            }
            // Never reclassify a confirmed on-disk skip as a playlist duplicate.
            if songItems[i].status == .skipped, songItems[i].skipReason == .alreadySaved {
                skippedAlreadySaved += 1
                let tid = songItems[i].trackId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tid.isEmpty { seenIds.insert(tid) }
                continue
            }
            let tid = songItems[i].trackId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tid.isEmpty else { continue }
            if seenIds.contains(tid) {
                songItems[i].status = .skipped
                songItems[i].skipReason = .duplicate
                songItems[i].fraction = 1
                dupCount += 1
            } else {
                seenIds.insert(tid)
            }
        }
    }

    private nonisolated static func normalizedSongKey(_ name: String) -> String {
        let base = name.replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return base.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    @discardableResult
    func download(
        urls: [String],
        settings: AppSettings,
        store: AppStore,
        expectedTracks: Int = 0,
        trackNames: [String] = [],
        trackIds: [String] = [],
        startedToast: String? = nil,
        queue: [DownloadQueueItem] = []
    ) async -> Bool {
        guard !urls.isEmpty else {
            appendLog("Add a Spotify link or choose a playlist first.")
            return false
        }

        // Already downloading — append instead of interrupting.
        if isRunning, !cancelFlag.value {
            return enqueueWhileRunning(urls: urls, queue: queue, startedToast: startedToast)
        }

        // Previous job is stopping — wait briefly, then start fresh.
        if isRunning {
            statusMessage = "Stopping previous…"
            for _ in 0..<80 {
                if !isRunning { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard !isRunning else {
                appendLog("Still stopping the previous download — try again in a moment.")
                showToast("Still stopping — try again")
                return false
            }
        }

        guard let zotify = ZotifyCLI.realZotifyURL else {
            appendLog("Setup needed: install zotify on this Mac (use Install Dependencies on the DMG).")
            statusMessage = "Setup needed"
            tabBadge = .failure
            return false
        }

        // Clear previous job UI immediately so a new download never flashes old progress.
        songItems = []
        queueItems = []
        totalExpected = 0
        totalCompleted = 0
        sessionTrackIds = []
        cancelFlag.value = false
        skipPlaylistFlag.value = false
        skipSongFlag.value = false
        awaitingSpotifyLogin.value = false
        reauthHandoff.value = false
        pendingAuthURL = nil
        activeStore = store
        // Finish leftover kills *before* launching zotify (parallel kill was aborting new jobs).
        await killOrphanZotifyProcessesAwaiting(source: "downloadStart")
        downloadHadError = false
        isRunning = true
        setPhase(.starting)
        downloadSpeedLabel = "Starting…"
        downloadErrorMessage = ""
        retryStatusMessage = ""
        isConverting = false
        convertFraction = 0
        convertLabel = ""
        convertSkipped = false
        showCelebration = false
        autoConvertEnabled = false
        tabBadge = .inProgress
        activeSongIndex = nil
        requestShowGetMusic = true

        // Use the same OAuth UI as Preferences (success page + auto-close), not zotify’s raw callback.
        if !Self.hasSpotifyCredentials() {
            setPhase(.signingIn)
            downloadSpeedLabel = "Waiting for Spotify login…"
            showToast("Sign in with Spotify to download", duration: 8)
            let signedIn = await signInWithSpotify(store: store, forceFreshLogin: true)
            if !signedIn || cancelFlag.value {
                isRunning = false
                statusMessage = "Sign-in required"
                downloadPhase = .idle
                tabBadge = .failure
                activeStore = nil
                return false
            }
            store.syncToZotifyConfig()
            // Give librespot a moment to settle before the download CLI reuses credentials.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            setPhase(.starting)
            downloadSpeedLabel = "Starting…"
        }

        var items = buildQueueItems(urls: urls, queue: queue)
        for i in items.indices {
            items[i].status = .pending
            items[i].retryAttempt = 0
            items[i].lastError = ""
            items[i].name = Self.sanitizePlaylistFolderName(items[i].name)
        }
        queueItems = items
        currentQueueIndex = 0

        // Resolve real song titles before the Progress list renders only when we have no
        // metadata at all. This avoids blocking fresh Get Music downloads.
        var initialNames = trackNames
        var initialIds = trackIds
        var initialExpected = expectedTracks
        if let first = items.first, initialNames.isEmpty && initialIds.isEmpty && initialExpected == 0 {
            setPhase(.fetchingTrackInfo)
            downloadSpeedLabel = "Fetching track list…"
            let result = await LinkPreviewService.lookup(urlText: first.url, musicRoot: settings.rootPath)
            if let preview = result.preview {
                if preview.trackCount > 0 { initialExpected = max(initialExpected, preview.trackCount) }
                if !preview.trackNames.isEmpty { initialNames = preview.trackNames }
                if !preview.trackIds.isEmpty { initialIds = preview.trackIds }
                if queueItems.indices.contains(0) {
                    if queueItems[0].name == friendlyQueueName(for: first.url) || queueItems[0].name.isEmpty {
                        queueItems[0].name = preview.name
                    }
                    if preview.trackCount > 0 {
                        queueItems[0].trackCount = preview.trackCount
                    }
                }
            }
            setPhase(.starting)
            downloadSpeedLabel = "Starting…"
        }

        // Show song rows immediately (placeholders OK). Prefetch real titles in background.
        if let first = items.first {
            prepareProgress(
                expectedTracks: max(first.trackCount, initialExpected, initialIds.count, 1),
                trackNames: initialNames,
                trackIds: initialIds
            )
            let needsTitles = initialNames.isEmpty
                || initialNames.allSatisfy { $0.hasPrefix("Song ") || $0.isEmpty }
            if needsTitles {
                prefetchTrackTitlesInBackground(url: first.url, musicRoot: settings.rootPath)
            }
        }

        let toastLabel = startedToast ?? (items.count == 1
            ? "Download started — \(items[0].name)"
            : "Download started — \(items.count) playlists")
        showToast(toastLabel)
        store.syncToZotifyConfig()

        let post = ZotifyCLI.postprocessURL
        let flag = cancelFlag
        let root = settings.rootPath
        let format = settings.convertFormat
        let genre = settings.defaultGenre
        let autoPP = settings.autoPostprocess
        autoConvertEnabled = autoPP && format != "none" && format != "ogg"
        // Don't set convertLabel yet — Progress used to show “Converting…” before download began.
        let maxAttempts = 5
        let jobStartedAt = Date()
        self.jobStartedAt = jobStartedAt
        self.activeMusicRoot = root

        // Drain pending items so mid-run enqueue adds are processed.
        while !flag.value {
            guard let idx = queueItems.firstIndex(where: { $0.status == .pending }) else { break }
            let item = queueItems[idx]

            skipPlaylistFlag.value = false
            skipSongFlag.value = false
            beginQueueItem(at: idx)
            capturePreexistingDiskState(root: root, playlistName: item.name)
            appendLog("")
            let queueTotal = queueItems.count
            if queueTotal > 1 {
                appendLog("Playlist \(idx + 1) of \(queueTotal): \(item.name)")
            } else {
                appendLog("Downloading \(item.name)…")
            }

            // Prefer titles already filled by prefetch / prepareJobUI.
            var names = (idx == 0 && !trackNames.isEmpty) ? trackNames : []
            var resolvedTrackIds: [String] = (idx == 0 && !trackIds.isEmpty) ? trackIds : []
            var expected = item.trackCount > 0 ? item.trackCount : (idx == 0 ? expectedTracks : 0)
            if names.isEmpty || names.allSatisfy({ $0.hasPrefix("Song ") || $0.hasPrefix("Track ") || $0.isEmpty }) {
                let current = songItems.map(\.name)
                if current.contains(where: { !$0.hasPrefix("Song ") && !$0.hasPrefix("Track ") && !$0.isEmpty }) {
                    names = current
                }
            }
            if resolvedTrackIds.isEmpty || resolvedTrackIds.allSatisfy(\.isEmpty) {
                let currentIds = songItems.map(\.trackId)
                if currentIds.contains(where: { !$0.isEmpty }) {
                    resolvedTrackIds = currentIds
                } else if !sessionTrackIds.isEmpty {
                    resolvedTrackIds = sessionTrackIds
                }
            }

            if skipPlaylistFlag.value || flag.value {
                finishQueueItem(at: idx, succeeded: false, cancelled: true)
                continue
            }

            var playlistOK = false
            var finalError = ""
            var cancelledPlaylist = false

            for attempt in 1...maxAttempts {
                if flag.value || skipPlaylistFlag.value { break }
                if queueItems.indices.contains(idx), queueItems[idx].status == .cancelled {
                    cancelledPlaylist = true
                    break
                }
                if queueItems.indices.contains(idx) {
                    queueItems[idx].retryAttempt = attempt
                }
                retryStatusMessage = attempt == 1
                    ? ""
                    : "Retry \(attempt) of \(maxAttempts)…"
                if attempt > 1 {
                    setPhase(.retrying)
                    retryStatusMessage = "Retry \(attempt) of \(maxAttempts)…"
                    statusMessage = "Retrying \(item.name) (\(attempt)/\(maxAttempts))…"
                    appendLog("Retry \(attempt)/\(maxAttempts) for “\(item.name)”…")
                } else {
                    setPhase(.checkingExisting)
                }
                prepareProgress(
                    expectedTracks: max(expected, resolvedTrackIds.count, 1),
                    trackNames: names,
                    trackIds: resolvedTrackIds
                )
                Self.reconcilePlaylistSongArchive(
                    root: root,
                    playlistName: item.name,
                    trackIds: resolvedTrackIds.isEmpty ? songItems.map(\.trackId) : resolvedTrackIds,
                    trackNames: names.isEmpty ? songItems.map(\.name) : names
                )
                applyLiveDiskProgress(root: root, playlistName: item.name)

                let attemptResult = await runPlaylistAttempt(
                    playlistURL: item.url,
                    zotify: zotify,
                    root: root,
                    flag: flag
                )

                if skipPlaylistFlag.value || (queueItems.indices.contains(idx) && queueItems[idx].status == .cancelled) {
                    cancelledPlaylist = true
                    break
                }

                if attemptResult.0 {
                    playlistOK = true
                    reconcileWholePlaylistAfterZotify(root: root)
                    finishAllSongsForConvert()
                    markDuplicateTracksAsSkipped()
                    refreshTotalProgressFromSongs()
                    let shouldConvert = autoPP
                        && format != "none"
                        && format != "ogg"
                        && !flag.value
                        && !skipPlaylistFlag.value
                    let newlyDownloaded = songItems.contains { $0.status == .done }
                    let hasConvertibleOnDisk = Self.playlistHasConvertibleSource(
                        root: root,
                        playlistName: item.name
                    )
                    // Always attempt convert after a successful download when enabled —
                    // gate used to skip when songs were “already saved” even if .ogg still needed FLAC.
                    if shouldConvert {
                        guard let post else {
                            appendLog("Post-process tool missing (zotify-postprocess) — left files as downloaded.")
                            downloadErrorMessage = "Downloaded, but convert tool wasn’t found."
                            showToast("Downloaded — convert tool missing", duration: 5)
                            break
                        }
                        beginConvert(format: format)
                        var convertOutcome: PostprocessOutcome = .failed
                        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                            DispatchQueue.global(qos: .utility).async {
                                let outcome = Self.postprocessRecent(
                                    root: root,
                                    format: format,
                                    genre: genre,
                                    post: post,
                                    flag: flag,
                                    playlistNames: [item.name],
                                    since: jobStartedAt
                                ) { line in
                                    DispatchQueue.main.async { self.handleConvertLine(line) }
                                }
                                DispatchQueue.main.async {
                                    if flag.value || self.skipPlaylistFlag.value {
                                        convertOutcome = .failed
                                        self.finishConvert(cancelled: true, succeeded: false)
                                    } else {
                                        convertOutcome = outcome
                                        switch outcome {
                                        case .didConvert:
                                            self.finishConvert(cancelled: false, succeeded: true)
                                            self.syncSongItemsFromDisk(root: root, playlistName: item.name)
                                        case .nothingToConvert:
                                            self.finishConvertNothingToDo()
                                            self.syncSongItemsFromDisk(root: root, playlistName: item.name)
                                        case .failed:
                                            self.finishConvert(cancelled: false, succeeded: false)
                                            self.syncSongItemsFromDisk(root: root, playlistName: item.name)
                                        }
                                    }
                                    cont.resume()
                                }
                            }
                        }
                        if !flag.value, !skipPlaylistFlag.value {
                            switch convertOutcome {
                            case .nothingToConvert:
                                showToast("No new/changed download folders found to convert.", duration: 4)
                            case .failed:
                                downloadHadError = true
                                downloadErrorMessage = "Download finished, but converting / tagging failed."
                                showToast("Convert failed — check Progress", duration: 5)
                            case .didConvert:
                                break
                            }
                        }
                    }
                    break
                }

                finalError = attemptResult.1.isEmpty
                    ? "Download failed for “\(item.name)”"
                    : attemptResult.1
                if queueItems.indices.contains(idx) {
                    queueItems[idx].lastError = finalError
                }
                appendLog("Attempt \(attempt)/\(maxAttempts) failed: \(finalError)")

                if attempt >= maxAttempts || flag.value || skipPlaylistFlag.value { break }

                let wait = Self.retryDelaySeconds(attempt: attempt, error: finalError)
                appendLog(Self.retryWorkaroundDescription(attempt: attempt, error: finalError, wait: wait))
                retryStatusMessage = "Waiting \(wait)s before retry \(attempt + 1)/\(maxAttempts)…"
                statusMessage = retryStatusMessage
                store.syncToZotifyConfig()
                await Self.sleepSeconds(wait, cancelFlag: flag)
            }

            finishActiveSongIfNeeded()
            let downloadingBeforePromote = songItems.filter { $0.status == .downloading }.count
            let wasCancelled = cancelledPlaylist || skipPlaylistFlag.value || flag.value
            if !wasCancelled {
                for i in songItems.indices where songItems[i].status == .downloading {
                    songItems[i].status = .done
                    songItems[i].fraction = 1
                    totalCompleted = min(totalExpected, totalCompleted + 1)
                }
            } else {
                for i in songItems.indices where !songItems[i].isFinished {
                    songItems[i].status = .skipped
                    songItems[i].skipReason = .cancelled
                    songItems[i].fraction = 1
                }
                totalCompleted = songItems.filter { $0.status == .done || $0.status == .skipped }.count
            }

            if cancelledPlaylist || skipPlaylistFlag.value {
                retryStatusMessage = ""
                finishQueueItem(at: idx, succeeded: false, cancelled: true)
            } else if playlistOK {
                retryStatusMessage = ""
                finishQueueItem(at: idx, succeeded: true)
            } else if !flag.value {
                downloadHadError = true
                finishQueueItem(at: idx, succeeded: false)
                let shown = finalError.isEmpty
                    ? "Couldn’t download “\(item.name)” after \(maxAttempts) tries."
                    : finalError
                downloadErrorMessage = shown
                appendLog("Gave up on “\(item.name)” after \(maxAttempts) tries.")
                showToast("Failed — \(item.name)", duration: 5)
            }
        }

        if flag.value {
            for i in queueItems.indices where queueItems[i].status == .pending || queueItems[i].status == .downloading {
                queueItems[i].status = .cancelled
                queueItems[i].lastError = "Cancelled"
            }
            for i in songItems.indices where !songItems[i].isFinished {
                songItems[i].status = .skipped
                songItems[i].skipReason = .cancelled
                songItems[i].fraction = 1
            }
            totalCompleted = songItems.filter { $0.status == .done || $0.status == .skipped }.count
        }

        // If the loop exited early, playlists may still be .downloading with no files saved.
        let stalled = queueItems.contains(where: { $0.status == .downloading })
        let songsIncomplete = !songItems.isEmpty
            && !songItems.allSatisfy { $0.status == .done || $0.status == .skipped }
        let anySongFailed = songItems.contains(where: { $0.status == .failed })
        let noAudioSaved = Self.countAudioFiles(in: root) == 0 && !songItems.isEmpty
        if !flag.value, stalled || anySongFailed || (songsIncomplete && noAudioSaved) {
            downloadHadError = true
            for i in queueItems.indices where queueItems[i].status == .downloading {
                queueItems[i].status = .failed
                if queueItems[i].lastError.isEmpty {
                    queueItems[i].lastError = "Download didn’t finish"
                }
            }
            if downloadErrorMessage.isEmpty {
                downloadErrorMessage = "Download didn’t finish — try again."
            }
        }

        let finishedTotal = max(queueItems.count, 1)
        ZotifyCLI.scrubLogFiles(arguments: ZotifyCLI.isolatedFlags(rootPath: root))
        isRunning = false
        if downloadPhase != .idle {
            // Keep terminal statusMessage ("Done" / errors); clear live phase.
            if downloadPhase != .converting {
                downloadPhase = .idle
            }
        }
        activeStore = nil
        activeSongIndex = nil
        downloadSpeedLabel = ""
        retryStatusMessage = ""
        awaitingSpotifyLogin.value = false
        reauthHandoff.value = false
        // Final honesty pass: song Progress status + files across app + legacy libraries.
        if let q = queueItems.first(where: { $0.status == .done || $0.status == .failed || $0.status == .downloading })
            ?? queueItems.first {
            let statusDone = songItems.filter { $0.status == .done || $0.status == .skipped }.count
            let failedSongs = songItems.filter { $0.status == .failed }.count
            let scanPaths = Self.playlistScanPaths(root: root, playlistName: q.name)
            var uniqueNames = Set<String>()
            for path in scanPaths {
                for url in Self.audioFileURLs(in: path) {
                    uniqueNames.insert(url.deletingPathExtension().lastPathComponent.lowercased())
                }
            }
            let onDiskUnique = uniqueNames.count
            if failedSongs == 0, statusDone >= totalExpected, totalExpected > 0 {
                // Every playlist row is accounted for (Done / Already saved / Duplicate).
                downloadHadError = false
                downloadErrorMessage = ""
                totalCompleted = totalExpected
            } else if onDiskUnique < totalExpected || failedSongs > 0 {
                downloadHadError = true
                if downloadErrorMessage.isEmpty || downloadErrorMessage.contains("Saved ") {
                    downloadErrorMessage = "Saved \(min(onDiskUnique, totalExpected)) of \(totalExpected) songs on disk"
                        + (failedSongs > 0 ? " — \(failedSongs) couldn’t be downloaded from Spotify." : ".")
                }
            }
        }
        let anyQueueCancelled = queueItems.contains(where: { $0.status == .cancelled })
        let playlistSkipCancel = skipPlaylistFlag.value
        if flag.value || (anyQueueCancelled && !queueItems.contains(where: { $0.status == .done || $0.status == .failed || $0.status == .downloading || $0.status == .pending })) {
            convertSkipped = true
            if convertLabel.isEmpty || convertLabel == "Convert cancelled" {
                convertLabel = "Convert skipped"
            }
            if !isConverting {
                convertFraction = max(convertFraction, 1)
            }
            statusMessage = "Stopped"
            downloadPhase = .idle
            appendLog("Cancelled.")
            tabBadge = .none
            showCelebration = false
        } else if downloadHadError || queueItems.contains(where: { $0.status == .failed })
            || songItems.contains(where: { $0.status == .failed }) {
            statusMessage = "Finished with errors"
            downloadPhase = .idle
            appendLog("Finished \(finishedTotal) playlist(s) with some errors.")
            tabBadge = .failure
            showCelebration = false
            if downloadErrorMessage.isEmpty,
               let failed = queueItems.first(where: { $0.status == .failed }) {
                downloadErrorMessage = failed.lastError.isEmpty
                    ? "Download failed for “\(failed.name)” after \(maxAttempts) tries."
                    : failed.lastError
            }
            if downloadErrorMessage.isEmpty,
               songItems.contains(where: { $0.status == .failed }) {
                let reason = Self.extractFailureReason(from: lastZotifyOutput)
                downloadErrorMessage = reason
                    ?? "Spotify couldn’t provide audio for one or more tracks. Try again."
            }
            if !downloadErrorMessage.isEmpty {
                showToast(downloadErrorMessage, duration: 6)
            }
        } else if anyQueueCancelled {
            // Mixed queue: some cancelled, rest ok — never celebrate a cancel.
            statusMessage = "Stopped"
            downloadPhase = .idle
            tabBadge = .none
            showCelebration = false
            appendLog("Finished with cancelled playlist(s).")
        } else {
            let allSongsSucceeded = songItems.isEmpty
                || songItems.allSatisfy { $0.status == .done || $0.status == .skipped }
            if allSongsSucceeded {
                statusMessage = "Done"
                downloadPhase = .idle
                appendLog("Finished \(finishedTotal) playlist(s).")
                totalCompleted = songItems.filter { $0.status == .done || $0.status == .skipped }.count
                tabBadge = .success
                downloadErrorMessage = ""
                showCelebration = true
                let newCount = songItems.filter { $0.status == .done }.count
                let alreadyHere = songItems.filter {
                    $0.status == .skipped && $0.skipReason == .alreadySaved
                }.count
                if !songItems.isEmpty {
                    if newCount == 0 {
                        showToast("All already here")
                    } else if alreadyHere > 0 {
                        showToast("\(newCount) new · \(alreadyHere) already here")
                    }
                }
            } else {
                downloadHadError = true
                statusMessage = "Finished with errors"
                downloadPhase = .idle
                appendLog("Finished with incomplete songs.")
                tabBadge = .failure
                if downloadErrorMessage.isEmpty {
                    downloadErrorMessage = "Some songs didn’t finish downloading."
                }
                showToast(downloadErrorMessage, duration: 5)
            }
        }

        return !flag.value && !downloadHadError && statusMessage == "Done"
    }

    /// Append playlists while a download is already running.
    @discardableResult
    private func enqueueWhileRunning(
        urls: [String],
        queue: [DownloadQueueItem],
        startedToast: String?
    ) -> Bool {
        let built = buildQueueItems(urls: urls, queue: queue)
        var added: [DownloadQueueItem] = []
        for var item in built {
            let alreadyQueued = queueItems.contains { existing in
                AppStore.sameSpotifyURL(existing.url, item.url)
                    && (existing.status == .pending || existing.status == .downloading)
            }
            if alreadyQueued { continue }
            item.status = .pending
            item.retryAttempt = 0
            item.lastError = ""
            queueItems.append(item)
            added.append(item)
        }
        guard !added.isEmpty else {
            showToast("Already in the queue")
            appendLog("Skipped — already in the download queue.")
            return false
        }
        let toast = startedToast ?? (added.count == 1
            ? "Queued — \(added[0].name)"
            : "Queued \(added.count) playlists")
        let display = toast.replacingOccurrences(of: "Download started", with: "Queued")
        showToast(display)
        appendLog(added.count == 1
            ? "Queued — \(added[0].name)"
            : "Queued \(added.count) playlists.")
        tabBadge = .inProgress
        requestShowGetMusic = true
        return true
    }

    private func buildQueueItems(urls: [String], queue: [DownloadQueueItem]) -> [DownloadQueueItem] {
        var items = queue
        if items.isEmpty {
            items = urls.map { url in
                DownloadQueueItem(name: friendlyQueueName(for: url), url: url)
            }
        }
        if items.count != urls.count {
            items = urls.enumerated().map { idx, url in
                if let match = queue.first(where: { AppStore.sameSpotifyURL($0.url, url) }) {
                    return match
                }
                return DownloadQueueItem(name: friendlyQueueName(for: url), url: url)
            }
        }
        return items
    }

    private nonisolated static func countAudioFiles(in root: String) -> Int {
        let rootURL = URL(fileURLWithPath: root)
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
            return 0
        }
        var count = 0
        let ok: Set<String> = ["ogg", "flac", "mp3", "m4a", "wav"]
        for case let file as URL in enumerator {
            if ok.contains(file.pathExtension.lowercased()) { count += 1 }
        }
        return count
    }

    private nonisolated static func sleepSeconds(_ seconds: Int, cancelFlag: CancellationFlag) async {
        guard seconds > 0 else { return }
        let slice: UInt64 = 200_000_000
        var remaining = seconds * 5
        while remaining > 0, !cancelFlag.value {
            try? await Task.sleep(nanoseconds: slice)
            remaining -= 1
        }
    }

    private nonisolated static func retryDelaySeconds(attempt: Int, error: String) -> Int {
        let lower = error.lowercased()
        if lower.contains("429") || lower.contains("rate") || lower.contains("too many") {
            return min(60, 15 * attempt)
        }
        if lower.contains("network") || lower.contains("timed out") || lower.contains("timeout")
            || lower.contains("connection") || lower.contains("temporarily") {
            return min(40, 8 * attempt)
        }
        if lower.contains("content stream") || lower.contains("premium") || lower.contains("login") {
            return min(30, 6 * attempt)
        }
        return min(25, 4 * attempt)
    }

    private nonisolated static func retryWorkaroundDescription(attempt: Int, error: String, wait: Int) -> String {
        let lower = error.lowercased()
        if lower.contains("429") || lower.contains("rate") {
            return "Spotify rate limit — waiting \(wait)s, then retrying with a cooler request pace."
        }
        if lower.contains("content stream") {
            return "Stream hiccup — refreshing session config, waiting \(wait)s, then retrying."
        }
        if lower.contains("network") || lower.contains("timeout") || lower.contains("connection") {
            return "Network issue — waiting \(wait)s for a clearer connection, then retrying."
        }
        return "Applying workaround, waiting \(wait)s, then retry \(attempt + 1)."
    }

    private nonisolated static func extractFailureReason(from output: String) -> String? {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let priority = [
            "FAILED TO GET CONTENT STREAM",
            "SKIPPING TRACK",
            "rate limit",
            "429",
            "ERROR",
            "Exception",
            "Traceback",
            "login",
            "premium",
            "unavailable"
        ]
        for key in priority {
            if let hit = lines.last(where: { $0.localizedCaseInsensitiveContains(key) }) {
                return String(hit.prefix(180))
            }
        }
        return lines.last(where: {
            $0.localizedCaseInsensitiveContains("fail")
                || $0.localizedCaseInsensitiveContains("error")
                || $0.localizedCaseInsensitiveContains("could not")
                || $0.localizedCaseInsensitiveContains("couldn't")
        }).map { String($0.prefix(180)) }
    }

    private func friendlyQueueName(for url: String) -> String {
        let parts = url.split(separator: "/")
        if let last = parts.last {
            let id = last.split(separator: "?").first.map(String.init) ?? String(last)
            if id.count >= 6 { return "Playlist \(id.prefix(6))…" }
        }
        return "Playlist"
    }

    private static func isSpotifyPlaylistURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("/playlist/") || lower.contains("spotify:playlist:")
    }

    /// Download one playlist attempt.
    /// Prefer a single whole-playlist zotify run (one Python/Spotify cold start).
    /// Track-by-track is only used to finish leftovers after a mid-run song skip.
    private func runPlaylistAttempt(
        playlistURL: String,
        zotify: URL,
        root: String,
        flag: CancellationFlag
    ) async -> (Bool, String) {
        let playlistName = queueItems.indices.contains(currentQueueIndex)
            ? queueItems[currentQueueIndex].name
            : ""

        let pendingWithIds = songItems.filter { !$0.isFinished && !$0.trackId.isEmpty }
        let someAlreadyFinished = songItems.contains(where: \.isFinished)
        // Resume leftovers track-by-track so skip-song / partial retries stay precise.
        if someAlreadyFinished, !pendingWithIds.isEmpty {
            return await runTrackByTrackAttempt(
                tracks: pendingWithIds,
                playlistName: playlistName,
                zotify: zotify,
                root: root,
                flag: flag
            )
        }


        // Always download into a playlist subfolder (convert + library expect folders, not flat root .ogg).
        let cleanPlaylist = Self.sanitizePlaylistFolderName(playlistName)
        let downloadRoot: String = {
            guard !cleanPlaylist.isEmpty else { return root }
            let folder = URL(fileURLWithPath: root).appendingPathComponent(cleanPlaylist)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.path
        }()

        if let idx = songItems.firstIndex(where: { !$0.isFinished }) {
            activeSongIndex = idx
            // Stay .pending until real transfer (speed / ≥8% / DOWNLOADED).
        }
        // Start in "checking" — switch to downloading when bytes/speed appear.
        setPhase(.checkingExisting)
        if downloadSpeedLabel.isEmpty || downloadSpeedLabel.contains("Fetching") || downloadSpeedLabel == "Starting…" {
            let finished = songItems.filter(\.isFinished).count
            let expected = max(totalExpected, songItems.count, 1)
            downloadSpeedLabel = finished > 0
                ? "\(finished) of \(expected) on disk"
                : "Looking for existing songs…"
        }

        let result = await runZotifyOnce(
            zotify: zotify,
            url: playlistURL,
            root: downloadRoot,
            flag: flag,
            progressFolderName: ""
        )
        // Soft retry after LOGIN FAILED (61) without wiping credentials.
        var effective = result
        if !result.0,
           !flag.value,
           !skipPlaylistFlag.value,
           !reauthHandoff.value,
           Self.hasSpotifyCredentials(),
           (result.1.localizedCaseInsensitiveContains("login failed")
            || lastZotifyOutput.localizedCaseInsensitiveContains("login failed")) {
            activeStore?.syncToZotifyConfig()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            statusMessage = playlistName.isEmpty ? "Retrying…" : "Retrying \(playlistName)…"
            setPhase(.retrying)
            effective = await runZotifyOnce(
                zotify: zotify,
                url: playlistURL,
                root: downloadRoot,
                flag: flag,
                progressFolderName: ""
            )
        }
        if reauthHandoff.value, !flag.value, !skipPlaylistFlag.value {
            reauthHandoff.value = false
            awaitingSpotifyLogin.value = false
            killOrphanZotifyProcessesAsync(source: "reauthHandoff")
            if let store = activeStore {
                setPhase(.signingIn)
                downloadSpeedLabel = "Waiting for Spotify login…"
                showToast("Complete Spotify sign-in in your browser", duration: 10)
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global(qos: .utility).async {
                        Self.freeOAuthPort(4381)
                        cont.resume()
                    }
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                // Keep existing credentials unless missing — forceFresh was deleting good sessions.
                let signedIn = await signInWithSpotify(
                    store: store,
                    forceFreshLogin: !Self.hasSpotifyCredentials()
                )
                if signedIn, !flag.value {
                    store.syncToZotifyConfig()
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    setPhase(.checkingExisting)
                    downloadSpeedLabel = "Looking for existing songs…"
                    let retry = await runZotifyOnce(
                        zotify: zotify,
                        url: playlistURL,
                        root: downloadRoot,
                        flag: flag,
                        progressFolderName: ""
                    )
                    reconcileWholePlaylistAfterZotify(root: root)
                    if skipPlaylistFlag.value { return (false, "Cancelled") }
                    if flag.value { return (false, "Stopped") }
                    let hardFail = songItems.contains(where: { $0.status == .failed })
                    if hardFail, Self.countAudioFiles(in: root) == 0 {
                        let reason = Self.extractFailureReason(from: lastZotifyOutput) ?? retry.1
                        return (false, reason.isEmpty
                            ? "Spotify couldn’t provide audio for these tracks. Try again in a minute."
                            : reason)
                    }
                    return retry.0 ? (true, "") : retry
                }
                return (false, "Sign-in required")
            }
            return (false, "Sign-in required")
        }
        reconcileWholePlaylistAfterZotify(root: root)
        if skipPlaylistFlag.value {
            return (false, "Cancelled")
        }
        if skipSongFlag.value {
            if let idx = activeSongIndex, songItems.indices.contains(idx), !songItems[idx].isFinished {
                songItems[idx].status = .skipped
                songItems[idx].skipReason = .cancelled
                songItems[idx].fraction = 1
            }
            activeSongIndex = nil
            skipSongFlag.value = false
            // Finish remaining songs without re-downloading the whole playlist.
            let leftover = songItems.filter { !$0.isFinished && !$0.trackId.isEmpty }
            if !leftover.isEmpty, !flag.value, !skipPlaylistFlag.value {
                return await runTrackByTrackAttempt(
                    tracks: leftover,
                    playlistName: playlistName,
                    zotify: zotify,
                    root: root,
                    flag: flag
                )
            }
            return (false, "Song skipped — continuing")
        }
        let hardFail = songItems.contains(where: { $0.status == .failed })
        let audioSaved = Self.countAudioFiles(in: root)
        if hardFail, audioSaved == 0 {
            let reason = Self.extractFailureReason(from: lastZotifyOutput)
                ?? effective.1
            return (false, reason.isEmpty
                ? "Spotify couldn’t provide audio for these tracks. Try again in a minute."
                : reason)
        }
        if !effective.0 {
            return effective
        }
        return (true, "")
    }

    /// One zotify process per remaining track (slower start — used after song skip / partial resume).
    private func runTrackByTrackAttempt(
        tracks: [SongDownloadItem],
        playlistName: String,
        zotify: URL,
        root: String,
        flag: CancellationFlag
    ) async -> (Bool, String) {
        let cleanPlaylist = Self.sanitizePlaylistFolderName(playlistName)
        let trackRoot: String = {
            if cleanPlaylist.isEmpty { return root }
            let folder = URL(fileURLWithPath: root).appendingPathComponent(cleanPlaylist)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.path
        }()
        var anyFailed = false
        var lastError = ""
        for song in tracks {
            if flag.value || skipPlaylistFlag.value { break }
            guard let idx = songItems.firstIndex(where: { $0.id == song.id }) else { continue }
            if songItems[idx].isFinished { continue }

            skipSongFlag.value = false
            activeSongIndex = idx
            // Stay in Waiting (.pending) until real transfer progress — no fake 2% bar.
            setPhase(.checkingExisting)
            downloadSpeedLabel = "Looking for existing songs…"

            let trackURL = "https://open.spotify.com/track/\(songItems[idx].trackId)"
            let result = await runZotifyOnce(
                zotify: zotify,
                url: trackURL,
                root: trackRoot,
                flag: flag,
                progressFolderName: ""
            )

            if skipPlaylistFlag.value || flag.value {
                break
            }
            if skipSongFlag.value {
                if songItems[idx].status != .skipped {
                    songItems[idx].status = .skipped
                    songItems[idx].skipReason = .cancelled
                    songItems[idx].fraction = 1
                }
                activeSongIndex = nil
                continue
            }
            if result.0 {
                songItems[idx].status = .done
                songItems[idx].fraction = 1
                totalCompleted = min(totalExpected, totalCompleted + 1)
                activeSongIndex = nil
            } else {
                anyFailed = true
                lastError = result.1
                songItems[idx].status = .failed
                songItems[idx].fraction = 1
                activeSongIndex = nil
            }
        }
        if skipPlaylistFlag.value {
            return (false, "Cancelled")
        }
        if flag.value {
            return (false, "Stopped")
        }
        let hardFail = songItems.contains(where: { $0.status == .failed })
        return (!hardFail && !anyFailed, lastError)
    }

    private func runZotifyOnce(
        zotify: URL,
        url: String,
        root: String,
        flag: CancellationFlag,
        /// `nil` → use current queue playlist name; `""` → scan `root` itself (track-by-track folder).
        progressFolderName: String? = nil
    ) async -> (Bool, String) {
        let playlistName = progressFolderName ?? (
            queueItems.indices.contains(currentQueueIndex)
                ? queueItems[currentQueueIndex].name
                : ""
        )
        // Show already-saved tracks immediately so skip-existing runs don’t look frozen at Song 1.
        applyLiveDiskProgress(root: root, playlistName: playlistName)

        return await withCheckedContinuation { (cont: CheckedContinuation<(Bool, String), Never>) in
            let folderURL = playlistName.isEmpty
                ? URL(fileURLWithPath: root)
                : URL(fileURLWithPath: root).appendingPathComponent(playlistName)
            let scanPath = FileManager.default.fileExists(atPath: folderURL.path) ? folderURL.path : root
            let fileCountBox = ProgressHeartbeat(initial: Self.countAudioFiles(in: scanPath))

            let diskPoll = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            diskPoll.schedule(deadline: .now() + 0.4, repeating: 1.0)
            diskPoll.setEventHandler { [weak self] in
                guard let self else { return }
                self.applyLiveDiskProgress(root: root, playlistName: playlistName)
                let n = Self.countAudioFiles(in: scanPath)
                if n > fileCountBox.value {
                    fileCountBox.value = n
                    fileCountBox.bumped = true
                }
            }
            diskPoll.resume()

            DispatchQueue.global(qos: .userInitiated).async {
                var succeeded = true
                var errorText = ""
                var output = ""
                do {
                    let result = try ZotifyCLI.run(
                        executable: zotify,
                        arguments: ZotifyCLI.isolatedFlags(rootPath: root) + [url],
                        onLine: { line in
                            DispatchQueue.main.async { self.handleDownloadLine(line) }
                        },
                        isCancelled: {
                            flag.value || self.skipPlaylistFlag.value || self.skipSongFlag.value
                                || self.reauthHandoff.value
                        },
                        stallTimeout: 75,
                        stallHeartbeat: {
                            // Don't kill while handing off to polished OAuth.
                            if self.awaitingSpotifyLogin.value || self.reauthHandoff.value { return true }
                            if fileCountBox.bumped {
                                fileCountBox.bumped = false
                                return true
                            }
                            return false
                        }
                    )
                    output = result.output
                    ZotifyCLI.scrubLogFiles(in: root)
                    if self.skipPlaylistFlag.value || self.skipSongFlag.value {
                        succeeded = false
                        errorText = self.skipPlaylistFlag.value ? "Cancelled" : "Song skipped"
                    } else if result.exitCode == 124 || output.contains("download stalled") {
                        succeeded = false
                        errorText = "Spotify connection stalled — will retry"
                    } else if result.exitCode != 0 {
                        succeeded = false
                        errorText = Self.extractFailureReason(from: result.output)
                            ?? "Download failed (exit \(result.exitCode))"
                    }
                } catch {
                    succeeded = false
                    ZotifyCLI.scrubLogFiles(in: root)
                    errorText = error.localizedDescription
                }
                diskPoll.cancel()
                DispatchQueue.main.async {
                    self.applyLiveDiskProgress(root: root, playlistName: playlistName)
                    self.lastZotifyOutput = output
                }
                cont.resume(returning: (succeeded && !flag.value, errorText))
            }
        }
    }

    /// Thread-safe file-count heartbeat for stall detection.
    private final class ProgressHeartbeat: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Int
        private var _bumped = false
        var value: Int {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
        var bumped: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _bumped }
            set { lock.lock(); _bumped = newValue; lock.unlock() }
        }
        init(initial: Int) { _value = initial }
    }

    /// Fill Progress row titles without blocking download start.
    func applyTrackTitles(_ names: [String], trackIds: [String] = []) {
        guard !names.isEmpty else { return }
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        ensureSongCapacity(max(cleaned.count, trackIds.count))
        for i in songItems.indices {
            let placeholder = songItems[i].name.hasPrefix("Song ")
                || songItems[i].name.hasPrefix("Track ")
                || songItems[i].name.isEmpty
            if i < cleaned.count, !cleaned[i].isEmpty, placeholder {
                songItems[i].name = cleaned[i]
            }
            if i < trackIds.count, !trackIds[i].isEmpty, songItems[i].trackId.isEmpty {
                songItems[i].trackId = trackIds[i]
            }
        }
        if !trackIds.isEmpty {
            sessionTrackIds = trackIds
        }
        markDuplicateTracksAsSkipped()
        // Point at the first waiting song after dup marks (no fake progress).
        if activeSongIndex == nil || (activeSongIndex.map { songItems.indices.contains($0) && songItems[$0].isFinished } ?? false) {
            markNextDownloading()
        }
    }

    func prefetchTrackTitlesInBackground(url: String, musicRoot: String) {
        guard !url.isEmpty, !titlePrefetchInFlight else { return }
        titlePrefetchInFlight = true
        Task { @MainActor in
            defer { titlePrefetchInFlight = false }
            let result = await LinkPreviewService.lookup(urlText: url, musicRoot: musicRoot)
            guard let preview = result.preview else { return }
            applyTrackTitles(preview.trackNames, trackIds: preview.trackIds)
            if preview.trackCount > totalExpected {
                ensureSongCapacity(preview.trackCount)
                totalExpected = preview.trackCount
            }
        }
    }

    /// App download folder + legacy `Zotify Music` (read-only) for the same playlist name.
    private nonisolated static func playlistScanPaths(root: String, playlistName: String) -> [String] {
        var paths: [String] = []
        let cleanName = sanitizePlaylistFolderName(playlistName)
        let primary = cleanName.isEmpty
            ? root
            : URL(fileURLWithPath: root).appendingPathComponent(cleanName).path
        if FileManager.default.fileExists(atPath: primary) {
            paths.append(primary)
        }
        // Never fall back to scanning the entire music library — that falsely marks
        // unrelated songs (e.g. Dj HipHop) as “already saved” for a new playlist.
        // Also never treat an empty playlistName as “scan all of Zotify Music”.
        if !cleanName.isEmpty {
            let legacyRoot = AppPaths.terminalZotifyMusicRoot.path
            if URL(fileURLWithPath: root).standardizedFileURL.path
                != URL(fileURLWithPath: legacyRoot).standardizedFileURL.path {
                let legacy = URL(fileURLWithPath: legacyRoot).appendingPathComponent(cleanName).path
                if FileManager.default.fileExists(atPath: legacy), !paths.contains(legacy) {
                    paths.append(legacy)
                }
            }
        }
        return paths
    }

    /// Strip quotes / path junk so folder names stay valid (embed HTML used to leave a trailing `"`).
    nonisolated static func sanitizePlaylistFolderName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        let illegal = CharacterSet(charactersIn: "/:\\*?<>|")
        s = s.components(separatedBy: illegal).joined(separator: "-")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when playlist folder (or flat music root) still has unconverted source audio (.ogg, etc.).
    nonisolated static func playlistHasConvertibleSource(root: String, playlistName: String) -> Bool {
        let sourceExts: Set<String> = ["ogg", "mp3", "m4a", "aac", "opus", "wav"]
        let rootURL = URL(fileURLWithPath: root)
        var folders = [rootURL]
        let clean = sanitizePlaylistFolderName(playlistName)
        if !clean.isEmpty {
            folders.insert(rootURL.appendingPathComponent(clean, isDirectory: true), at: 0)
        }
        for folder in folders {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            if names.contains(where: { sourceExts.contains(($0 as NSString).pathExtension.lowercased()) }) {
                return true
            }
        }
        return false
    }

    /// Resolve the real Python postprocess script (bash wrappers cannot be passed to python3).
    nonisolated static func postprocessPythonScript(from post: URL) -> URL? {
        if post.pathExtension.lowercased() == "py",
           FileManager.default.fileExists(atPath: post.path) {
            return post
        }
        let sibling = post.appendingPathExtension("py")
        if FileManager.default.fileExists(atPath: sibling.path) {
            return sibling
        }
        let named = post.deletingLastPathComponent().appendingPathComponent("zotify-postprocess.py")
        if FileManager.default.fileExists(atPath: named.path) {
            return named
        }
        return nil
    }

    /// Snapshot both libraries before zotify starts, so a re-downloaded copy still
    /// shows as Already saved instead of Done.
    private func capturePreexistingDiskState(root: String, playlistName: String) {
        let scanPaths = Self.playlistScanPaths(root: root, playlistName: playlistName)
        var titleKeys = Set<String>()
        var trackIds = Set<String>()
        for path in scanPaths {
            for row in Self.readSongIdRows(in: path) {
                if !row.id.isEmpty { trackIds.insert(row.id) }
                let titleKey = Self.normalizedSongKey(row.title)
                if !titleKey.isEmpty { titleKeys.insert(titleKey) }
                let displayTitleKey = Self.normalizedSongKey(row.displayName)
                if !displayTitleKey.isEmpty { titleKeys.insert(displayTitleKey) }
            }
            for file in Self.audioFileURLs(in: path) {
                let title = Self.titleFromAudioFilename(file.lastPathComponent)
                let key = Self.normalizedSongKey(title)
                if !key.isEmpty { titleKeys.insert(key) }
            }
        }
        preexistingAudioTitleKeys = titleKeys
        preexistingTrackIds = trackIds
    }

    /// Update Progress rows from files already saved (so large playlists don’t look stuck at 2%).
    private func applyLiveDiskProgress(root: String, playlistName: String) {
        let scanPaths = Self.playlistScanPaths(root: root, playlistName: playlistName)
        guard !scanPaths.isEmpty, !songItems.isEmpty else { return }

        var rows: [SongIdRow] = []
        var seenRowIds = Set<String>()
        var files: [URL] = []
        var seenFilePaths = Set<String>()
        for path in scanPaths {
            for row in Self.readSongIdRows(in: path) {
                let key = row.id.isEmpty ? row.path : row.id
                if seenRowIds.insert(key).inserted { rows.append(row) }
            }
            for file in Self.audioFileURLs(in: path) {
                if seenFilePaths.insert(file.path).inserted { files.append(file) }
            }
        }
        let count = max(files.count, rows.count)
        guard count > 0 else { return }

        for i in songItems.indices where songItems[i].trackId.isEmpty && i < sessionTrackIds.count {
            songItems[i].trackId = sessionTrackIds[i]
        }
        let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if !byId.isEmpty, songItems.contains(where: { !$0.trackId.isEmpty }) {
            for i in songItems.indices {
                if songItems[i].isDuplicateSkip { continue }
                guard let row = byId[songItems[i].trackId] else { continue }
                let placeholder = songItems[i].name.hasPrefix("Song ")
                    || songItems[i].name.hasPrefix("Track ")
                    || songItems[i].name.isEmpty
                if placeholder || songItems[i].name != row.displayName {
                    songItems[i].name = row.displayName
                }
                if let path = Self.resolveAudioPath(for: row, files: files) {
                    markSongPresentOnDisk(at: i, filePath: path)
                }
            }
        } else if !rows.isEmpty {
            // No track ids yet — update names only. Do NOT mark status by song_ids order
            // (download order ≠ playlist order and caused false Done/Failed).
            for (i, row) in rows.enumerated() where i < songItems.count {
                if songItems[i].isDuplicateSkip { continue }
                let placeholder = songItems[i].name.hasPrefix("Song ")
                    || songItems[i].name.hasPrefix("Track ")
                    || songItems[i].name.isEmpty
                if placeholder {
                    songItems[i].name = row.displayName
                }
            }
        }
        // Match leftover audio (app folder + legacy Zotify Music) by title.
        matchUnmatchedSongsToAudioFiles(files: files, knownRows: rows)
        // Point at the next waiting song without fake “in progress” percent.
        if activeSongIndex == nil
            || (activeSongIndex.map { !songItems.indices.contains($0) || songItems[$0].isFinished } ?? true) {
            activeSongIndex = songItems.firstIndex(where: { $0.status == .pending })
        }
        totalCompleted = songItems.filter { $0.status == .done || $0.status == .skipped }.count
        refreshTotalProgressFromSongs()
        // Don't overwrite a live MB/s reading with the saved-count summary.
        let looksLikeSpeed = downloadSpeedLabel.contains("/s") || downloadSpeedLabel.contains("B/s")
        let skipped = songItems.filter { $0.status == .skipped && $0.skipReason == .alreadySaved }.count
        let expected = max(totalExpected, songItems.count, 1)
        if !looksLikeSpeed {
            if downloadPhase == .checkingExisting || downloadPhase == .starting {
                downloadSpeedLabel = skipped > 0 || totalCompleted > 0
                    ? "\(totalCompleted) of \(expected) on disk"
                    : "Looking for existing songs…"
            } else if downloadSpeedLabel.isEmpty
                || downloadSpeedLabel.contains("Fetching")
                || downloadSpeedLabel.contains(" of ")
                || downloadSpeedLabel.contains("Looking for")
                || downloadSpeedLabel.contains("on disk") {
                downloadSpeedLabel = "\(totalCompleted) of \(expected) saved"
            }
        }
        if downloadPhase == .starting || downloadPhase == .fetchingTrackInfo || statusMessage.isEmpty {
            setPhase(.checkingExisting)
        }
    }

    /// Files older than this job → Already saved; new/changed files → Done.
    private func markSongPresentOnDisk(at index: Int, filePath: String) {
        guard songItems.indices.contains(index) else { return }
        guard !filePath.isEmpty, FileManager.default.fileExists(atPath: filePath) else { return }
        let url = URL(fileURLWithPath: filePath)
        let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        let titleKey = Self.normalizedSongKey(Self.titleFromAudioFilename(url.lastPathComponent))
        let rowKeys = Self.candidateTitleKeys(for: songItems[index].name)
        let titleExistedBefore = (!titleKey.isEmpty && preexistingAudioTitleKeys.contains(titleKey))
            || rowKeys.contains(where: { preexistingAudioTitleKeys.contains($0) })
        let trackExistedBefore = !songItems[index].trackId.isEmpty
            && preexistingTrackIds.contains(songItems[index].trackId)
        let existedBeforeJob = mod < jobStartedAt.addingTimeInterval(-1)
            || titleExistedBefore
            || trackExistedBefore
        if songItems[index].status == .skipped { return }
        if songItems[index].status == .done, !existedBeforeJob { return }
        songItems[index].fraction = 1
        if existedBeforeJob {
            songItems[index].status = .skipped
            songItems[index].skipReason = .alreadySaved
        } else {
            songItems[index].status = .done
            songItems[index].skipReason = .none
        }
    }

    /// Match playlist rows that aren’t finished yet to audio files / archive rows by title.
    @discardableResult
    private func matchUnmatchedSongsToAudioFiles(files: [URL], knownRows: [SongIdRow]) -> Int {
        guard !files.isEmpty || !knownRows.isEmpty else { return 0 }

        var byTitle: [String: String] = [:]
        func rememberTitle(_ title: String, path: String) {
            let key = Self.normalizedSongKey(title)
            guard !key.isEmpty, !path.isEmpty else { return }
            guard FileManager.default.fileExists(atPath: path) else { return }
            if let existing = byTitle[key] {
                if path.lowercased().hasSuffix(".flac"), !existing.lowercased().hasSuffix(".flac") {
                    byTitle[key] = path
                }
            } else {
                byTitle[key] = path
            }
        }

        // Include archive paths too — previously these were excluded as "used", so
        // title matching could never mark "Central Cee — Doja" against Doja.flac.
        for row in knownRows {
            let path = row.path
            if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                rememberTitle(row.title, path: path)
                rememberTitle(row.displayName, path: path)
            }
        }
        for file in files {
            rememberTitle(Self.titleFromAudioFilename(file.lastPathComponent), path: file.path)
        }
        guard !byTitle.isEmpty else { return 0 }

        var usedPaths = Set<String>()
        var matched = 0
        for i in songItems.indices {
            if songItems[i].isDuplicateSkip { continue }
            if songItems[i].status == .done || songItems[i].status == .skipped { continue }
            let keys = Self.candidateTitleKeys(for: songItems[i].name)
            var hit: String?
            for key in keys {
                if let path = byTitle[key], !usedPaths.contains(path) {
                    hit = path
                    break
                }
            }
            // Fuzzy: title key contained in filename key or vice versa (feat. / remix variants).
            if hit == nil {
                for key in keys where key.count >= 6 {
                    if let pair = byTitle.first(where: {
                        !usedPaths.contains($0.value) && ($0.key.contains(key) || key.contains($0.key))
                    }) {
                        hit = pair.value
                        break
                    }
                }
            }
            guard let path = hit else { continue }
            markSongPresentOnDisk(at: i, filePath: path)
            if songItems[i].status == .done || songItems[i].status == .skipped {
                matched += 1
                usedPaths.insert(path)
            }
        }
        return matched
    }

    /// Convenience overload used by sync — scans given folder(s).
    @discardableResult
    private func matchUnmatchedSongsToAudioFiles(scanPath: String, knownRows: [SongIdRow]) -> Int {
        matchUnmatchedSongsToAudioFiles(files: Self.audioFileURLs(in: scanPath), knownRows: knownRows)
    }

    /// If this row already has audio on disk (app or legacy library), mark Already saved / Done.
    @discardableResult
    private func recoverSongFromDiskIfPresent(at index: Int) -> Bool {
        guard songItems.indices.contains(index) else { return false }
        let playlistName = queueItems.indices.contains(currentQueueIndex)
            ? queueItems[currentQueueIndex].name
            : ""
        let root = activeMusicRoot.isEmpty ? AppPaths.defaultMusicRoot.path : activeMusicRoot
        let scanPaths = Self.playlistScanPaths(root: root, playlistName: playlistName)
        var rows: [SongIdRow] = []
        var files: [URL] = []
        var seen = Set<String>()
        for path in scanPaths {
            for row in Self.readSongIdRows(in: path) {
                if seen.insert(row.id.isEmpty ? row.path : row.id).inserted { rows.append(row) }
            }
            files.append(contentsOf: Self.audioFileURLs(in: path))
        }
        let tid = songItems[index].trackId
        if !tid.isEmpty, let row = rows.first(where: { $0.id == tid }) {
            if songItems[index].status == .failed || songItems[index].status == .downloading {
                songItems[index].status = .pending
            }
            if let path = Self.resolveAudioPath(for: row, files: files) {
                markSongPresentOnDisk(at: index, filePath: path)
            }
            return songItems[index].status == .done || songItems[index].status == .skipped
        }
        if songItems[index].status == .failed || songItems[index].status == .downloading {
            songItems[index].status = .pending
        }
        _ = matchUnmatchedSongsToAudioFiles(files: files, knownRows: rows)
        return songItems[index].status == .done || songItems[index].status == .skipped
    }

    private nonisolated static func candidateTitleKeys(for name: String) -> [String] {
        var keys: [String] = []
        let full = normalizedSongKey(name)
        if !full.isEmpty { keys.append(full) }
        // "Artist — Title" / "Artist - Title" → also try title-only (matches "Title.flac")
        let seps = ["—", " – ", " - "]
        for sep in seps {
            if let r = name.range(of: sep) {
                let title = String(name[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let t = normalizedSongKey(title)
                if !t.isEmpty, !keys.contains(t) { keys.append(t) }
                break
            }
        }
        return keys
    }


    private nonisolated static func audioFileURLs(in root: String) -> [URL] {
        let rootURL = URL(fileURLWithPath: root)
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
            return []
        }
        let ok: Set<String> = ["ogg", "flac", "mp3", "m4a", "wav"]
        var files: [URL] = []
        for case let file as URL in enumerator {
            if ok.contains(file.pathExtension.lowercased()) { files.append(file) }
        }
        return files
    }

    private nonisolated static func playlistIndex(from filename: String) -> Int {
        let base = (filename as NSString).deletingPathExtension
        if let head = base.split(separator: "_").first, let n = Int(head) {
            return n
        }
        return 9999
    }

    private nonisolated static func titleFromAudioFilename(_ filename: String) -> String {
        var base = (filename as NSString).deletingPathExtension
        // "03_Artist_Title" → "Artist Title" (keep readable)
        if let range = base.range(of: #"^\d+_"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        return base.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginQueueItem(at index: Int) {
        currentQueueIndex = index
        for i in queueItems.indices {
            if i < index {
                if queueItems[i].status != .failed && queueItems[i].status != .cancelled {
                    queueItems[i].status = .done
                }
            } else if i == index {
                if queueItems[i].status != .cancelled {
                    queueItems[i].status = .downloading
                }
            } else if queueItems[i].status != .done
                && queueItems[i].status != .failed
                && queueItems[i].status != .cancelled {
                queueItems[i].status = .pending
            }
        }
        refreshQueueLabels()
        if downloadPhase != .converting && downloadPhase != .signingIn && downloadPhase != .stopping {
            setPhase(downloadPhase == .downloading ? .downloading : .checkingExisting)
        }
    }

    private func finishQueueItem(at index: Int, succeeded: Bool, cancelled: Bool = false) {
        guard queueItems.indices.contains(index) else { return }
        if cancelled {
            queueItems[index].status = .cancelled
            if queueItems[index].lastError.isEmpty {
                queueItems[index].lastError = "Cancelled"
            }
        } else {
            queueItems[index].status = succeeded ? .done : .failed
        }
        refreshQueueLabels()
    }

    /// Relabel pending items as Next / Then based on the current index.
    private func refreshQueueLabels() {
        objectWillChange.send()
    }

    func queueRole(for index: Int) -> String {
        guard queueItems.indices.contains(index) else { return "" }
        switch queueItems[index].status {
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Skipped"
        case .downloading: return "Now"
        case .pending:
            let current = queueItems.firstIndex(where: { $0.status == .downloading })
                ?? currentQueueIndex
            if index == current + 1 { return "Next" }
            return "Then"
        }
    }

    private func handleDownloadLine(_ line: String) {
        appendLog(line)

        // Mid-download Spotify OAuth — hand off to the same flow as Preferences (nice success page).
        // Do NOT open zotify’s raw authorize URL (that shows “librespot-python received callback”).
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains("click on the following link to login")
            || trimmed.contains("accounts.spotify.com/authorize") {
            awaitingSpotifyLogin.value = true
            setPhase(.signingIn)
            downloadSpeedLabel = "Waiting for Spotify login…"
            if !reauthHandoff.value {
                reauthHandoff.value = true
                showToast("Opening Spotify sign-in…", duration: 6)
            }
        }
        if trimmed.lowercased().contains("login failed") {
            awaitingSpotifyLogin.value = false
            // Do NOT set reauthHandoff here — that wiped fresh credentials and broke login
            // (LOGIN FAILED → signIn deletes creds → ConnectionResetError loop).
            downloadSpeedLabel = "Spotify session error — retrying…"
            setPhase(.retrying)
        }

        if let match = line.range(of: #"Total Query Progress:\s*(\d+)\s*/\s*(\d+)"#, options: .regularExpression) {
            let slice = String(line[match])
            let nums = slice.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if nums.count >= 2 {
                let finishedRows = songItems.filter(\.isFinished).count
                // tqdm can race ahead of per-song rows — never show 24/24 while songs still wait.
                totalCompleted = min(nums[1], max(finishedRows, nums[0]))
                if !songCountLocked, nums[1] > totalExpected {
                    totalExpected = nums[1]
                    ensureSongCapacity(totalExpected)
                } else if nums[1] > songItems.count {
                    ensureSongCapacity(nums[1])
                    totalExpected = max(totalExpected, nums[1])
                }
                // If capacity grew past known titles, refresh names once.
                let placeholders = songItems.contains {
                    $0.name.hasPrefix("Song ") || $0.name.hasPrefix("Track ") || $0.name.isEmpty
                }
                if placeholders,
                   let url = queueItems[safe: currentQueueIndex]?.url,
                   !url.isEmpty {
                    let root = activeMusicRoot.isEmpty ? AppPaths.defaultMusicRoot.path : activeMusicRoot
                    prefetchTrackTitlesInBackground(url: url, musicRoot: root)
                }
            }
        }

        // Ignore further song progress once converting.
        if isConverting { return }

        if let name = Self.extractHashtagQuoted(line, label: "SKIPPING") {
            if downloadPhase != .downloading {
                setPhase(.checkingExisting)
            }
            completeCurrentSong(name: cleanSongName(name), status: .skipped, skipReason: .alreadySaved)
            return
        }
        // zotify prints "SKIPPING TRACK" for skip-existing — must NOT mark Failed.
        if line.uppercased().contains("SKIPPING TRACK") {
            if downloadPhase != .downloading {
                setPhase(.checkingExisting)
            }
            let songName = songItems[safe: activeSongIndex ?? -1]?.name ?? "Song"
            completeCurrentSong(name: songName, status: .skipped, skipReason: .alreadySaved)
            return
        }
        if let path = Self.extractHashtagQuoted(line, label: "DOWNLOADED") {
            setPhase(.downloading)
            let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            completeCurrentSong(name: cleanSongName(base), status: .done)
            return
        }
        if line.contains("FAILED TO GET CONTENT STREAM") {
            // File may already exist (app folder or legacy Zotify Music) — don't show Failed.
            if let idx = activeSongIndex, songItems.indices.contains(idx),
               recoverSongFromDiskIfPresent(at: idx) {
                totalCompleted = songItems.filter { $0.status == .done || $0.status == .skipped }.count
                activeSongIndex = nil
                markNextDownloading()
                return
            }
            let songName = songItems[safe: activeSongIndex ?? -1]?.name ?? "Song"
            completeCurrentSong(name: songName, status: .failed)
            return
        }

        // tqdm-style percent for the active song (never after convert starts)
        if isConverting { return }
        if let speed = Self.extractSpeed(line) {
            awaitingSpotifyLogin.value = false
            downloadSpeedLabel = speed
            setPhase(.downloading)
            if let idx = activeSongIndex, songItems.indices.contains(idx),
               songItems[idx].status == .pending {
                songItems[idx].status = .downloading
            }
        }
        if let pct = Self.extractPercent(line), let idx = activeSongIndex, songItems.indices.contains(idx) {
            awaitingSpotifyLogin.value = false
            // Tiny % while skipping is common — only treat real transfer as In progress.
            if pct >= 0.08 {
                setPhase(.downloading)
                if songItems[idx].status == .pending {
                    songItems[idx].status = .downloading
                }
            }
            if songItems[idx].status == .downloading {
                songItems[idx].fraction = min(0.99, max(songItems[idx].fraction, pct))
                let placeholder = songItems[idx].name.hasPrefix("Song ")
                    || songItems[idx].name.hasPrefix("Track ")
                if placeholder,
                   let desc = Self.extractTqdmDesc(line), !desc.isEmpty {
                    songItems[idx].name = desc
                }
            }
        }
    }

    /// Point at the next waiting song without fake “in progress” bars.
    private func markNextDownloading() {
        if let idx = songItems.firstIndex(where: { $0.status == .pending }) {
            activeSongIndex = idx
        } else {
            activeSongIndex = nil
        }
    }

    private func finishActiveSongIfNeeded() {
        guard let idx = activeSongIndex, songItems.indices.contains(idx),
              songItems[idx].status == .downloading else { return }
        songItems[idx].status = .done
        songItems[idx].fraction = 1
        refreshTotalProgressFromSongs()
    }

    private func finishAllSongsForConvert() {
        // Keep the playlist's expected size — never shrink to "only what finished".
        let preservedExpected = max(totalExpected, songItems.count, 1)
        songCountLocked = true
        totalExpected = preservedExpected
        activeSongIndex = nil
        downloadSpeedLabel = ""
        refreshTotalProgressFromSongs()
    }

    private func beginConvert(format: String) {
        isConverting = true
        convertSkipped = false
        convertFraction = 0.05
        let fmt = format.uppercased()
        convertLabel = fmt == "FLAC" || format.lowercased() == "flac"
            ? "Converting to FLAC + lyrics…"
            : "Converting, tagging & renaming…"
        setPhase(.converting)
        downloadSpeedLabel = ""
        retryStatusMessage = ""
        activeSongIndex = nil
        appendLog(convertLabel)
    }

    private func finishConvert(cancelled: Bool, succeeded: Bool = true) {
        if cancelled {
            convertSkipped = true
            convertLabel = "Convert skipped"
            convertFraction = 1
            isConverting = false
            return
        }
        convertFraction = 1
        isConverting = false
        if succeeded {
            convertLabel = "Converted · lyrics embedded · renamed"
            statusMessage = "Done"
        } else {
            convertLabel = "Convert failed"
            statusMessage = "Finished with errors"
        }
    }

    private func finishConvertNothingToDo() {
        convertFraction = 1
        isConverting = false
        convertSkipped = true
        convertLabel = "No new/changed folders to convert"
        if songItems.contains(where: { $0.status == .failed }) {
            statusMessage = "Finished with errors"
        } else {
            statusMessage = "Done"
        }
        appendLog("No new/changed download folders found to convert.")
    }

    private func handleConvertLine(_ line: String) {
        appendLog(line)
        let lower = line.lowercased()
        if lower.contains("no new/changed") || lower.contains("nothing to convert") {
            convertLabel = "No new/changed folders to convert"
            convertSkipped = true
            if !songItems.contains(where: { $0.status == .failed }) {
                statusMessage = "Done"
            }
            convertFraction = 1
            return
        }
        if lower.contains("converted:") {
            convertFraction = min(0.85, max(convertFraction, convertFraction + 0.08))
            convertLabel = "Converting to FLAC…"
            statusMessage = "Converting…"
        } else if lower.contains("lyrics") {
            convertFraction = min(0.95, max(convertFraction, 0.7))
            convertLabel = "Embedding lyrics…"
            statusMessage = "Adding lyrics…"
        } else if lower.contains("renamed") || lower.contains("rename") {
            convertFraction = min(0.98, max(convertFraction, 0.85))
            convertLabel = "Renaming songs…"
            statusMessage = "Renaming…"
        } else if lower.contains("post-process") {
            if convertFraction < 0.1 { convertFraction = 0.12 }
            convertLabel = "Preparing files…"
            statusMessage = "Converting…"
        } else if lower.contains("failed") || lower.contains("error") {
            convertLabel = "Convert issue…"
        }
        if let pct = Self.extractPercent(line) {
            convertFraction = min(0.99, max(convertFraction, pct))
        }
    }

    private func completeCurrentSong(
        name: String,
        status: SongDownloadItem.Status,
        skipReason: SongDownloadItem.SkipReason = .none
    ) {
        if isConverting { return }
        // Never invent phantom "Song N" rows just because we finished one.
        ensureSongCapacity(totalExpected)

        // Prefer matching the reported title to an unfinished row — skip/download lines
        // often arrive while activeSongIndex still points at a different placeholder.
        var idx: Int?
        if !name.isEmpty {
            let keys = Set(Self.candidateTitleKeys(for: name))
            if !keys.isEmpty {
                idx = songItems.firstIndex { song in
                    !song.isFinished && Self.candidateTitleKeys(for: song.name).contains(where: keys.contains)
                }
            }
        }
        if idx == nil,
           let active = activeSongIndex, songItems.indices.contains(active),
           songItems[active].status == .downloading || songItems[active].status == .pending {
            idx = active
        } else if idx == nil, let next = songItems.firstIndex(where: { !$0.isFinished }) {
            idx = next
        }

        guard let idx else {
            if !songCountLocked {
                let n = songItems.count + 1
                songItems.append(SongDownloadItem(
                    id: n, number: n, name: name, status: status, fraction: 1,
                    skipReason: status == .skipped ? skipReason : .none
                ))
                totalExpected = max(totalExpected, songItems.count)
                totalCompleted = min(totalExpected, totalCompleted + 1)
                markNextDownloading()
            } else if let last = songItems.indices.last(where: { songItems[$0].status == .downloading }) {
                songItems[last].name = name.isEmpty ? songItems[last].name : name
                songItems[last].status = status
                songItems[last].fraction = 1
                if status == .skipped { songItems[last].skipReason = skipReason }
                activeSongIndex = nil
            }
            return
        }

        // Keep richer "Artist — Title" labels when skip line only has a filename stem.
        if !name.isEmpty {
            let current = songItems[idx].name
            let currentIsPlaceholder = current.hasPrefix("Song ") || current.hasPrefix("Track ") || current.isEmpty
            if currentIsPlaceholder || current.count <= name.count {
                songItems[idx].name = name
            }
        }
        songItems[idx].status = status
        songItems[idx].fraction = 1
        if status == .skipped {
            songItems[idx].skipReason = skipReason == .none ? .alreadySaved : skipReason
        }
        activeSongIndex = nil
        markNextDownloading()
        refreshTotalProgressFromSongs()
    }

    /// After a whole-playlist zotify run, sync Progress from disk — never invent success.
    private func reconcileWholePlaylistAfterZotify(root: String) {
        let playlistName = queueItems.indices.contains(currentQueueIndex)
            ? queueItems[currentQueueIndex].name
            : ""
        syncSongItemsFromDisk(root: root, playlistName: playlistName)
    }

    /// Rebuild Progress names/statuses from `.song_ids` + audio files on disk.
    private func syncSongItemsFromDisk(root: String, playlistName: String) {
        let scanPaths = Self.playlistScanPaths(root: root, playlistName: playlistName)
        var rows: [SongIdRow] = []
        var seenRowIds = Set<String>()
        var files: [URL] = []
        var seenFilePaths = Set<String>()
        for path in scanPaths {
            for row in Self.readSongIdRows(in: path) {
                let key = row.id.isEmpty ? row.path : row.id
                if seenRowIds.insert(key).inserted { rows.append(row) }
            }
            for file in Self.audioFileURLs(in: path) {
                if seenFilePaths.insert(file.path).inserted { files.append(file) }
            }
        }
        let expected = max(totalExpected, songItems.count, sessionTrackIds.count, 1)
        ensureSongCapacity(expected)

        // Prefer Spotify track-id match so mid-playlist failures don’t shift names.
        for i in songItems.indices where songItems[i].trackId.isEmpty && i < sessionTrackIds.count {
            songItems[i].trackId = sessionTrackIds[i]
        }
        let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hasIds = songItems.contains { !$0.trackId.isEmpty } && !byId.isEmpty
        var matched = 0

        if hasIds {
            for i in songItems.indices {
                let tid = songItems[i].trackId
                guard !tid.isEmpty, let row = byId[tid] else { continue }
                songItems[i].name = row.displayName
                if songItems[i].isDuplicateSkip { matched += 1; continue }
                if songItems[i].status == .skipped && songItems[i].skipReason == .alreadySaved {
                    matched += 1
                    continue
                }
                if songItems[i].status != .skipped {
                    if songItems[i].status == .failed { songItems[i].status = .pending }
                    if let path = Self.resolveAudioPath(for: row, files: files) {
                        markSongPresentOnDisk(at: i, filePath: path)
                    }
                }
                matched += 1
            }
        }

        // Recover rows that have audio on disk but no .song_ids entry (either library).
        for i in songItems.indices where songItems[i].status == .failed {
            songItems[i].status = .pending
        }
        matchUnmatchedSongsToAudioFiles(files: files, knownRows: rows)

        for i in songItems.indices {
            if songItems[i].status == .done || songItems[i].status == .skipped { continue }
            songItems[i].status = .failed
            songItems[i].fraction = 1
            if songItems[i].name.hasPrefix("Song ") || songItems[i].name.hasPrefix("Track ") {
                songItems[i].name = "Track \(i + 1) — couldn’t get audio"
            }
        }

        totalExpected = expected
        let statusDone = songItems.filter { $0.status == .done || $0.status == .skipped }.count
        let failed = songItems.filter { $0.status == .failed }.count
        if failed == 0 && statusDone >= expected {
            downloadHadError = false
            downloadErrorMessage = ""
        } else if failed > 0 || statusDone < expected {
            downloadHadError = true
            var uniqueNames = Set<String>()
            for file in files {
                uniqueNames.insert(file.deletingPathExtension().lastPathComponent.lowercased())
            }
            let uniqueCount = uniqueNames.count
            downloadErrorMessage = "Saved \(min(max(uniqueCount, statusDone), expected)) of \(expected) songs on disk"
                + (failed > 0 ? " — \(failed) couldn’t be downloaded from Spotify." : ".")
        }
        markDuplicateTracksAsSkipped()
        let statusAfterDup = songItems.filter { $0.status == .done || $0.status == .skipped }.count
        let failedAfterDup = songItems.filter { $0.status == .failed }.count
        if failedAfterDup == 0 && statusAfterDup >= expected {
            downloadHadError = false
            downloadErrorMessage = ""
        }
        refreshTotalProgressFromSongs()
    }

    private struct SongIdRow {
        let id: String
        let date: String
        let artist: String
        let title: String
        let path: String

        var displayName: String {
            let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty, !t.isEmpty { return "\(a) — \(t)" }
            return t.isEmpty ? a : t
        }
    }

    private nonisolated static func readSongIdRows(in folder: String) -> [SongIdRow] {
        let url = URL(fileURLWithPath: folder).appendingPathComponent(".song_ids")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var rows: [SongIdRow] = []
        var seen = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            // id, date, artist, title, path
            guard parts.count >= 5 else { continue }
            let id = parts[0]
            let artist = parts[2]
            let title = parts[3]
            let path = parts[4]
            let key = id.isEmpty ? (path.isEmpty ? "\(artist)|\(title)" : path) : id
            guard seen.insert(key).inserted else { continue }
            rows.append(SongIdRow(id: id, date: parts[1], artist: artist, title: title, path: path))
        }
        return rows
    }

    private nonisolated static func writeSongIdRows(_ rows: [SongIdRow], in folder: String) {
        let url = URL(fileURLWithPath: folder).appendingPathComponent(".song_ids")
        let stamp = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: Date())
        }()
        var seen = Set<String>()
        var lines: [String] = []
        for row in rows {
            guard !row.id.isEmpty, seen.insert(row.id).inserted else { continue }
            let date = row.date.isEmpty ? stamp : row.date
            lines.append("\(row.id)\t\(date)\t\(row.artist)\t\(row.title)\t\(row.path)")
        }
        let body = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Repair `.song_ids` paths and register title matches so zotify skips renamed / re-id tracks.
    private nonisolated static func reconcilePlaylistSongArchive(
        root: String,
        playlistName: String,
        trackIds: [String],
        trackNames: [String]
    ) {
        guard let folder = playlistScanPaths(root: root, playlistName: playlistName).first else { return }

        var titleToPath: [String: String] = [:]
        func rememberTitle(_ title: String, path: String) {
            let key = normalizedSongKey(title)
            guard !key.isEmpty else { return }
            if let existing = titleToPath[key] {
                if path.lowercased().hasSuffix(".flac"), !existing.lowercased().hasSuffix(".flac") {
                    titleToPath[key] = path
                }
            } else {
                titleToPath[key] = path
            }
        }

        for file in audioFileURLs(in: folder) {
            rememberTitle(titleFromAudioFilename(file.lastPathComponent), path: file.path)
        }

        var rows = readSongIdRows(in: folder)
        var knownIds = Set(rows.map(\.id))

        for i in rows.indices {
            var path = rows[i].path
            if path.isEmpty || !FileManager.default.fileExists(atPath: path) {
                if let hit = titleToPath[normalizedSongKey(rows[i].title)] {
                    path = hit
                    rows[i] = SongIdRow(
                        id: rows[i].id, date: rows[i].date, artist: rows[i].artist,
                        title: rows[i].title, path: hit
                    )
                }
            }
            if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                rememberTitle(rows[i].title, path: path)
            }
        }

        let count = max(trackIds.count, trackNames.count)
        for i in 0..<count {
            let tid = i < trackIds.count ? trackIds[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            guard !tid.isEmpty, !knownIds.contains(tid) else { continue }
            let display = i < trackNames.count ? trackNames[i] : ""
            var matchedPath: String?
            for key in candidateTitleKeys(for: display) {
                if let path = titleToPath[key] {
                    matchedPath = path
                    break
                }
            }
            guard let path = matchedPath else { continue }
            let artist: String
            let title: String
            if let sep = display.range(of: " — ") ?? display.range(of: " - ") {
                artist = String(display[..<sep.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                title = String(display[sep.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                artist = ""
                title = display.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            rows.append(SongIdRow(id: tid, date: "", artist: artist, title: title, path: path))
            knownIds.insert(tid)
        }

        writeSongIdRows(rows, in: folder)
    }

    private nonisolated static func resolveAudioPath(for row: SongIdRow, files: [URL]) -> String? {
        if !row.path.isEmpty, FileManager.default.fileExists(atPath: row.path) {
            return row.path
        }
        let want = normalizedSongKey(row.title)
        guard !want.isEmpty else { return nil }
        for file in files {
            let key = normalizedSongKey(titleFromAudioFilename(file.lastPathComponent))
            if key == want || key.contains(want) || want.contains(key) {
                return file.path
            }
        }
        return nil
    }

    private func ensureSongCapacity(_ count: Int) {
        guard count > songItems.count else { return }
        for i in songItems.count..<count {
            songItems.append(
                SongDownloadItem(id: i + 1, number: i + 1, name: "Song \(i + 1)", status: .pending, fraction: 0)
            )
        }
        totalExpected = max(totalExpected, count)
    }

    private func cleanSongName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading index prefixes like "12_Artist_Title"
        if let r = try? NSRegularExpression(pattern: #"^\d+_"#),
           let match = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let range = Range(match.range, in: s) {
            s = String(s[range.upperBound...])
        }
        return s.replacingOccurrences(of: "_", with: " ")
    }

    private static func extractHashtagQuoted(_ line: String, label: String) -> String? {
        guard line.uppercased().contains(label.uppercased()) else { return nil }
        guard let first = line.firstIndex(of: "\""),
              let second = line[line.index(after: first)...].firstIndex(of: "\"")
        else { return nil }
        return String(line[line.index(after: first)..<second])
    }

    private static func extractPercent(_ line: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})\s*%"#) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        let pct = Double(ns.substring(with: match.range(at: 1))) ?? 0
        return min(1, max(0, pct / 100))
    }

    /// Spotify OAuth URL printed by zotify during an interactive login.
    private nonisolated static func extractSpotifyAuthURL(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"https://accounts\.spotify\.com/authorize[^\s\"']+"#,
            options: []
        ) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: match.range)
    }

    private nonisolated static func hasSpotifyCredentials() -> Bool {
        FileManager.default.fileExists(atPath: AppPaths.zotifyCredentialsURL.path)
    }

    /// Parse tqdm rates like "850.2kB/s", "1.24MB/s", "1.05MiB/s", "420 B/s".
    private static func extractSpeed(_ line: String) -> String? {
        let patterns = [
            #"([\d]+(?:\.\d+)?)\s*([KMG]i?[Bb])/s"#,
            #"([\d]+(?:\.\d+)?)\s*([KkMmGg][Bb])/s"#,
            #"([\d]+(?:\.\d+)?)\s*([Bb])/s"#
        ]
        let ns = line as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  match.numberOfRanges >= 3
            else { continue }
            let value = ns.substring(with: match.range(at: 1))
            let unitRaw = ns.substring(with: match.range(at: 2)).uppercased()
            let unit: String
            switch unitRaw {
            case "B": unit = "B"
            case "KB", "KIB", "K": unit = "KB"
            case "MB", "MIB", "M": unit = "MB"
            case "GB", "GIB", "G": unit = "GB"
            default: unit = unitRaw.hasSuffix("B") ? unitRaw : "\(unitRaw)B"
            }
            return "\(value) \(unit)/s"
        }
        return nil
    }

    private static func extractTqdmDesc(_ line: String) -> String? {
        // "Song Name:  45%|" or "Song Name 45%"
        guard let pctRange = line.range(of: #"\d{1,3}\s*%"#, options: .regularExpression) else { return nil }
        let prefix = String(line[..<pctRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.isEmpty || prefix.hasPrefix("###") || prefix.count > 120 { return nil }
        let lower = prefix.lowercased()
        // Ignore overall tqdm bars (these were overwriting the first song title).
        if lower.contains("progress") || lower == "total" || lower.hasPrefix("total ") {
            return nil
        }
        return prefix
    }

    private enum PostprocessOutcome {
        case didConvert
        case nothingToConvert
        case failed
    }

    private nonisolated static func postprocessRecent(
        root: String,
        format: String,
        genre: String,
        post: URL,
        flag: CancellationFlag,
        playlistNames: [String] = [],
        since: Date = Date().addingTimeInterval(-6 * 60 * 60),
        onLine: @escaping (String) -> Void
    ) -> PostprocessOutcome {
        let rootURL = URL(fileURLWithPath: root)
        let sourceExts: Set<String> = ["ogg", "mp3", "m4a", "aac", "opus", "wav"]
        let postprocessExts = sourceExts.union(["flac"])

        func folderHasSourceAudio(_ url: URL) -> Bool {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return names.contains { sourceExts.contains(($0 as NSString).pathExtension.lowercased()) }
        }

        func folderNeedsPostprocess(_ url: URL) -> Bool {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return names.contains { postprocessExts.contains(($0 as NSString).pathExtension.lowercased()) }
        }

        let folderQualifies = playlistNames.isEmpty ? folderHasSourceAudio : folderNeedsPostprocess

        var targets: [URL] = []
        for name in playlistNames {
            let trimmed = sanitizePlaylistFolderName(name)
            guard !trimmed.isEmpty else { continue }
            // Prefer the same scan paths used for Progress / skip-existing (handles Unicode forms).
            for path in playlistScanPaths(root: root, playlistName: name) {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                if folderQualifies(url), !targets.contains(where: { $0.path == url.path }) {
                    targets.append(url)
                }
            }
            let exact = rootURL.appendingPathComponent(trimmed, isDirectory: true)
            if folderQualifies(exact), !targets.contains(where: { $0.path == exact.path }) {
                targets.append(exact)
                continue
            }
            if let dirs = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                let match = dirs.first { dir in
                    dir.lastPathComponent.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                        && folderQualifies(dir)
                }
                if let match, !targets.contains(where: { $0.path == match.path }) {
                    targets.append(match)
                    continue
                }
            }
            // Rescue flat downloads: move root-level source audio into the playlist folder.
            if folderHasSourceAudio(rootURL) {
                try? FileManager.default.createDirectory(at: exact, withIntermediateDirectories: true)
                let names = (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []
                var moved = 0
                for fileName in names {
                    let ext = (fileName as NSString).pathExtension.lowercased()
                    guard sourceExts.contains(ext) else { continue }
                    let src = rootURL.appendingPathComponent(fileName)
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                    let dest = exact.appendingPathComponent(fileName)
                    if FileManager.default.fileExists(atPath: dest.path) { continue }
                    do {
                        try FileManager.default.moveItem(at: src, to: dest)
                        moved += 1
                    } catch {
                        continue
                    }
                }
                if folderQualifies(exact), !targets.contains(where: { $0.path == exact.path }) {
                    targets.append(exact)
                }
            }
            // Always post-process the playlist folder after a download when it has audio.
            if folderNeedsPostprocess(exact), !targets.contains(where: { $0.path == exact.path }) {
                targets.append(exact)
            }
        }


        if targets.isEmpty {
            guard let folders = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                onLine("Post-process: couldn’t read download folder.")
                return .failed
            }

            let recent = folders.filter { url in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                    return false
                }
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return mod > since
            }

            targets = recent.filter { folderHasSourceAudio($0) }
        }

        // Also pick up any older folders that still have unconverted source audio
        // from previous downloads (e.g. convert was skipped or failed last time).
        if let allFolders = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let targetPaths = Set(targets.map(\.path))
            for folder in allFolders {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir),
                      isDir.boolValue,
                      !targetPaths.contains(folder.path),
                      folderHasSourceAudio(folder)
                else { continue }
                targets.append(folder)
            }
        }

        if targets.isEmpty {
            onLine("No new/changed download folders found to convert.")
            return .nothingToConvert
        }

        var didConvert = false
        var allOK = true
        for folder in targets {
            if flag.value { return .failed }
            if !format.isEmpty, format.lowercased() != "flac", format.lowercased() != "none" {
                onLine("Note: converting to FLAC (preferred). Requested “\(format)” isn’t supported by the converter yet.")
            }
            onLine("Post-process → \(folder.lastPathComponent)")
            var args = [folder.path, "--format", format.isEmpty ? "flac" : format.lowercased()]
            if !genre.isEmpty { args += ["--genre", genre] }
            do {
                let result: CommandResult
                // `zotify-postprocess` is a bash wrapper — never pass it to python3 as a script.
                // Prefer the real .py next to it when invoking via a Python interpreter.
                let script = Self.postprocessPythonScript(from: post)
                let python = AppPaths.bundledPythonURL ?? ZotifyCLI.anacondaPythonURL
                if let py = python, let script {
                    result = try ZotifyCLI.run(
                        executable: py,
                        arguments: [script.path] + args,
                        onLine: onLine,
                        isCancelled: { flag.value },
                        // Convert can hash/tag hundreds of files with quiet stretches —
                        // never apply the Spotify download stall killer here.
                        stallTimeout: 0
                    )
                } else {
                    result = try ZotifyCLI.run(
                        executable: post,
                        arguments: args,
                        onLine: onLine,
                        isCancelled: { flag.value },
                        stallTimeout: 0
                    )
                }
                if result.exitCode != 0 {
                    allOK = false
                    onLine("Post-process failed for \(folder.lastPathComponent) (exit \(result.exitCode)).")
                } else {
                    didConvert = true
                }
            } catch {
                allOK = false
                onLine("Post-process error: \(error.localizedDescription)")
            }
        }
        if flag.value { return .failed }
        if !allOK { return .failed }
        return didConvert ? .didConvert : .nothingToConvert
    }

    func fetchPlaylists(store: AppStore) async -> [FetchedPlaylist] {
        store.syncToZotifyConfig()
        appendLog("Connecting to Spotify… A browser window may open so you can sign in.")

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
        from zotify.termoutput import Printer, PrintChannel
        Printer.splash = staticmethod(lambda: None)
        # Keep noisy API retries off stdout so they don't break JSON parsing.
        try:
            Printer._Printer__print_channel_settings[PrintChannel.WARNING] = False  # type: ignore
        except Exception:
            pass
        Zotify.CONFIG = Config()
        Zotify.start()
        Zotify.CONFIG.load(args)
        for i in range(5):
            try:
                Zotify.login(args); break
            except Exception as e:
                print('LOGIN_RETRY', e, file=sys.stderr); time.sleep(3)
        else:
            print("OZ_JSON|" + json.dumps({"ok": False, "error": "login failed"}))
            raise SystemExit(1)

        from google.protobuf.json_format import MessageToDict
        from librespot.proto import Playlist4External_pb2 as PlaylistPB
        from zotify.api import Playlist, UserPlaylist

        # Seed token cache for fast previews
        try:
            tok = Zotify.SESSION.tokens().get_token(
                'user-read-email', 'playlist-read-private', 'user-library-read'
            ).access_token
            cache_path = __OZ_TOKEN_CACHE__
            with open(cache_path, 'w') as f:
                json.dump({"token": tok, "ts": time.time(), "expires_in": 3600}, f)
        except Exception:
            pass

        cred = {}
        try:
            cred = json.loads(Path(Zotify.CONFIG.get_credentials_location()).read_text())
        except Exception:
            pass
        username = (cred.get('username') or '').strip()

        out = []
        seen = set()
        source = "none"
        rate_limited = False

        def add(name, pid, owner='', owned=False, spotify=False, tracks=0, image=''):
            if not pid or pid in seen:
                return
            name = (name or '').strip()
            if not name:
                return
            seen.add(pid)
            row = {
                'name': name,
                'id': pid,
                'url': f'https://open.spotify.com/playlist/{pid}',
                'isOwned': bool(owned),
                'isSpotify': bool(spotify) or str(pid).startswith('37i9'),
                'trackCount': int(tracks or 0),
            }
            if owner:
                row['owner'] = owner
            img = (image or '').strip()
            if img:
                row['imageURL'] = img
            out.append(row)

        def cover_from(md):
            if not isinstance(md, dict):
                return ''
            imgs = md.get('images')
            if isinstance(imgs, list) and imgs:
                # Prefer ~300px when sizes exist; otherwise first url.
                best = ''
                best_score = 10**9
                for im in imgs:
                    if not isinstance(im, dict):
                        continue
                    u = (im.get('url') or '').strip()
                    if not u:
                        continue
                    h = im.get('height') or im.get('width') or 0
                    try:
                        h = int(h)
                    except Exception:
                        h = 0
                    if not best:
                        best = u
                    if h:
                        score = abs(h - 300)
                        if score < best_score:
                            best_score = score
                            best = u
                if best:
                    return best
            attrs = md.get('attributes') if isinstance(md.get('attributes'), dict) else {}
            for key in ('picture', 'cover', 'image_url', 'imageUrl', 'cover_image_url'):
                v = attrs.get(key) or md.get(key)
                if isinstance(v, str) and v.strip():
                    v = v.strip()
                    if v.startswith('http'):
                        return v
                    # librespot file id / hex → Spotify CDN
                    if len(v) >= 16 and all(c in '0123456789abcdefABCDEF' for c in v.replace('-', '')):
                        return f'https://i.scdn.co/image/{v}'
            fmt = md.get('format')
            if isinstance(fmt, list):
                for item in fmt:
                    if isinstance(item, dict):
                        u = (item.get('url') or '').strip()
                        if u.startswith('http'):
                            return u
            return ''

        # 1) Preferred: Spotify library rootlist via librespot (owned + private + followed).
        #    Avoids api.spotify.com /v1/me/playlists which is easily rate-limited.
        try:
            if not username:
                raise RuntimeError('missing username')
            resp = Zotify.SESSION.api().send('GET', f'/playlist/v2/user/{username}/rootlist', None, None)
            if resp.status_code != 200 or not resp.content:
                raise RuntimeError(f'rootlist HTTP {resp.status_code}')
            proto = PlaylistPB.SelectedListContent()
            proto.ParseFromString(resp.content)
            data = MessageToDict(proto, preserving_proto_field_name=True)
            root_items = (data.get('contents') or {}).get('items') or []
            uris = []
            for it in root_items:
                if not isinstance(it, dict):
                    continue
                uri = it.get('uri') or ''
                if uri.startswith('spotify:playlist:'):
                    uris.append(uri)
            print(f'ROOTLIST {len(uris)}', file=sys.stderr)
            for uri in uris:
                pid = uri.split(':')[-1]
                md = Zotify.invoke_libre_md(Playlist, uri) or {}
                attrs = md.get('attributes') if isinstance(md, dict) else {}
                if not isinstance(attrs, dict):
                    attrs = {}
                name = (attrs.get('name') or md.get('name') or '').strip()
                owner_id = (md.get('owner_username') or attrs.get('owner_username') or '').strip()
                owner = owner_id
                tracks = 0
                try:
                    tracks = int(md.get('length') or attrs.get('length') or 0)
                except Exception:
                    tracks = 0
                if tracks <= 0:
                    contents = md.get('contents') if isinstance(md, dict) else {}
                    if isinstance(contents, dict):
                        items = contents.get('items') or []
                        if isinstance(items, list):
                            tracks = len(items)
                if not name:
                    name = f'Playlist {pid[:8]}'
                is_spotify = pid.startswith('37i9') or owner_id in ('spotify', 'Spotify')
                is_owned = (not is_spotify) and bool(username) and owner_id == username
                if is_spotify and not owner:
                    owner = 'Spotify'
                add(name, pid, owner, owned=is_owned, spotify=is_spotify, tracks=tracks, image=cover_from(md))
            if out:
                source = "rootlist"
        except Exception as e:
            print('ROOTLIST_ERR', e, file=sys.stderr)

        # 2) Fallback: Web API /me/playlists (often 429 while downloading).
        if not out:
            items = []
            for attempt in range(2):
                try:
                    items = UserPlaylist('gui').fetch_user_items() or []
                    if items:
                        break
                    rate_limited = True
                    time.sleep(2 + attempt * 2)
                except Exception as e:
                    if '429' in str(e).lower() or 'rate' in str(e).lower():
                        rate_limited = True
                    time.sleep(1)
            for resp in items:
                if not isinstance(resp, dict):
                    continue
                pid = resp.get('id') or ''
                uri = resp.get('uri') or ''
                if not pid and uri.startswith('spotify:playlist:'):
                    pid = uri.split(':')[-1]
                owner = ''
                owner_id = ''
                o = resp.get('owner') or {}
                if isinstance(o, dict):
                    owner = (o.get('display_name') or o.get('id') or '').strip()
                    owner_id = (o.get('id') or '').strip()
                is_spotify = str(pid).startswith('37i9') or owner_id == 'spotify'
                is_owned = (not is_spotify) and bool(username) and (owner_id == username)
                tracks = 0
                t = resp.get('tracks')
                if isinstance(t, dict):
                    tracks = int(t.get('total') or 0)
                elif isinstance(t, int):
                    tracks = t
                else:
                    tracks = int(resp.get('total_tracks') or 0)
                add(resp.get('name'), pid, owner, owned=is_owned, spotify=is_spotify, tracks=tracks, image=cover_from(resp))
            if out:
                source = "web"

        # 3) Last resort: public profile playlists only.
        if not out and username:
            try:
                profile = Zotify.SESSION.api().get_user_profile(username, playlist_limit=500) or {}
                def walk(o):
                    if isinstance(o, dict):
                        uri = o.get('uri') or ''
                        name = o.get('name') or ''
                        if uri.startswith('spotify:playlist:') and name:
                            add(name, uri.split(':')[-1], (o.get('owner_name') or ''))
                        for v in o.values():
                            walk(v)
                    elif isinstance(o, list):
                        for v in o:
                            walk(v)
                walk(profile)
                # Mark owned heuristically when profile belongs to the user.
                for row in out:
                    row['isOwned'] = True
                    row['isSpotify'] = str(row.get('id','')).startswith('37i9')
                if out:
                    source = "public_profile"
                    rate_limited = True
            except Exception as e:
                print('PROFILE_ERR', e, file=sys.stderr)

        # Refresh display name for Preferences.
        try:
            if username:
                profile = Zotify.SESSION.api().get_user_profile(username, playlist_limit=1) or {}
                disp = (profile.get('name') or '').strip() if isinstance(profile, dict) else ''
                print('ACCOUNT|' + json.dumps({'userId': username, 'displayName': disp}), file=sys.stderr)
        except Exception:
            pass

        payload = {
            "ok": True,
            "playlists": out,
            "source": source,
            "rateLimited": bool(rate_limited and source != "rootlist"),
        }
        if not out:
            payload = {
                "ok": False,
                "error": "Couldn’t load playlists from Spotify library",
                "rateLimited": rate_limited,
            }
        print("OZ_JSON|" + json.dumps(payload), flush=True)
        """#
            .replacingOccurrences(of: "__OZ_CONFIG__", with: AppPaths.pythonPathLiteral(AppPaths.zotifyConfigURL))
            .replacingOccurrences(of: "__OZ_TOKEN_CACHE__", with: AppPaths.pythonPathLiteral(
                AppPaths.zotifySupportDir.appendingPathComponent(".token_cache.json")
            ))

        let python = ZotifyCLI.which("python3") ?? URL(fileURLWithPath: "/usr/bin/python3")
        do {
            let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CommandResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try ZotifyCLI.run(
                            executable: python,
                            arguments: ["-c", script],
                            onLine: { line in
                                let trimmed = line.trimmingCharacters(in: .whitespaces)
                                if trimmed.hasPrefix("ACCOUNT|"),
                                   let data = trimmed.dropFirst(8).data(using: .utf8),
                                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    let userId = obj["userId"] as? String ?? ""
                                    let name = obj["displayName"] as? String ?? ""
                                    if !userId.isEmpty {
                                        DispatchQueue.main.async {
                                            store.updateAccount(userId: userId, displayName: name)
                                        }
                                    }
                                    return
                                }
                                if trimmed.hasPrefix("OZ_JSON|") || trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                                    return
                                }
                                if !trimmed.isEmpty {
                                    DispatchQueue.main.async { self.appendLog(line) }
                                }
                            }
                        )
                        cont.resume(returning: r)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }

            guard let obj = result.ozJSON() else {
                appendLog("Could not parse playlist list. Exit \(result.exitCode)")
                playlistStatusMessage = "Couldn’t load playlists"
                return []
            }

            if let ok = obj["ok"] as? Bool, !ok {
                let err = obj["error"] as? String ?? "unknown error"
                appendLog("Could not load playlists: \(err)")
                playlistStatusMessage = "Couldn’t load playlists"
                return []
            }

            let rateLimited = (obj["rateLimited"] as? Bool) ?? false
            let source = obj["source"] as? String ?? ""
            let arr = (obj["playlists"] as? [[String: Any]]) ?? []
            let fetched = arr.compactMap { row -> FetchedPlaylist? in
                guard let id = row["id"] as? String,
                      let name = row["name"] as? String,
                      let url = row["url"] as? String else { return nil }
                let owner = row["owner"] as? String
                let isOwned = (row["isOwned"] as? Bool) ?? false
                let isSpotify = (row["isSpotify"] as? Bool) ?? id.hasPrefix("37i9")
                let trackCount = (row["trackCount"] as? Int)
                    ?? (row["trackCount"] as? NSNumber)?.intValue
                    ?? 0
                let imageURL = row["imageURL"] as? String ?? ""
                return FetchedPlaylist(
                    id: id,
                    name: name,
                    url: url,
                    owner: owner,
                    isOwned: isOwned,
                    isSpotify: isSpotify,
                    trackCount: trackCount,
                    imageURL: imageURL
                )
            }
            if rateLimited && source == "public_profile" {
                appendLog("Spotify library API was busy — showing \(fetched.count) public playlist(s) only. Try again in a moment.")
                playlistStatusMessage = "Rate limited — public playlists only"
            } else {
                appendLog("Found \(fetched.count) playlists.")
                playlistStatusMessage = ""
            }
            return fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            appendLog("Fetch failed: \(error.localizedDescription)")
            playlistStatusMessage = "Fetch failed"
        }
        return []
    }

    /// Interactive Spotify OAuth — opens the login URL in the default browser.
    /// - Parameter forceFreshLogin: When true (Preferences), delete existing credentials first.
    ///   Mid-download handoff should pass false so a just-saved session isn’t wiped.
    @discardableResult
    func signInWithSpotify(store: AppStore, forceFreshLogin: Bool = true) async -> Bool {
        if isSigningIn {
            cancelSignIn()
            // Brief pause so the previous listener can exit.
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        store.syncToZotifyConfig()
        signInCancelFlag.value = false
        isSigningIn = true
        pendingAuthURL = nil
        defer {
            isSigningIn = false
            pendingAuthURL = nil
        }

        // Preflight: friend Macs often install only the DMG (no zotify/python deps).
        guard let python = ZotifyCLI.pythonWithZotifyURL else {
            appendLog("Setup needed: install zotify on this Mac first (see Help / zotify-tools).")
            showToast("Install zotify first, then sign in")
            return false
        }


        appendLog("Opening Spotify sign-in in your browser…")

        let script = #"""
        import json, sys, time
        from argparse import Namespace
        from pathlib import Path
        fields = dict(persist=False, update_config=False, update_archive=False, debug=False,
                      no_splash=True, config_location=__OZ_CONFIG__, username=None, token=None, urls='',
                      file_of_urls=None, liked_songs=False, user_playlists=False,
                      followed_artists=False, followed_albums=False, search=None, verify_library=False)
        args = Namespace(**fields)
        from zotify.config import Zotify, Config
        from zotify.termoutput import Printer
        from zotify.const import SCOPES, API_CLIENT_ID
        from librespot.core import Session, OAuth, MercuryRequests
        Printer.splash = staticmethod(lambda: None)
        Zotify.CONFIG = Config()
        Zotify.start()
        Zotify.CONFIG.load(args)

        cred_path = Path(Zotify.CONFIG.get_credentials_location())
        # Only wipe credentials for an explicit Preferences re-login.
        if __FORCE_FRESH__ and cred_path.exists():
            try:
                cred_path.unlink()
            except Exception:
                pass

        port = 4381
        # Free a stuck previous OAuth listener if needed.
        try:
            import socket, subprocess, os, signal
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                in_use = s.connect_ex(("127.0.0.1", port)) == 0
            if in_use:
                subprocess.run(["pkill", "-f", f":{port}"], check=False)
                out = subprocess.check_output(["lsof", "-tiTCP:%d" % port, "-sTCP:LISTEN"], text=True, stderr=subprocess.DEVNULL)
                for pid in out.split():
                    try: os.kill(int(pid), signal.SIGTERM)
                    except Exception: pass
                time.sleep(0.6)
        except Exception:
            pass

        redirect_url = f"http://{Zotify.CONFIG.get_oauth_address()}:{port}/login"

        # Only emit the URL — the Mac app opens the browser once.
        def oauth_print(url):
            print(f"AUTH_URL|{url}", flush=True)

        success_html = (
            "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'/>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'/>"
            "<title>Signed in — Oz Downloader</title>"
            "<style>"
            "body{margin:0;min-height:100vh;display:grid;place-items:center;"
            "font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;"
            "background:radial-gradient(1200px 600px at 50% -10%,#2a3344 0%,#12151c 55%,#0c0e12 100%);"
            "color:#f2f4f8}"
            ".card{width:min(420px,92vw);padding:36px 32px;border-radius:20px;"
            "background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);"
            "box-shadow:0 24px 60px rgba(0,0,0,.35);text-align:center}"
            ".check{width:64px;height:64px;margin:0 auto 18px;border-radius:50%;"
            "display:grid;place-items:center;"
            "background:linear-gradient(145deg,#3dd68c,#1f9d5c);"
            "box-shadow:0 10px 28px rgba(61,214,140,.28);font-size:32px;color:#04140c}"
            "h1{margin:0 0 8px;font-size:1.45rem;font-weight:700;letter-spacing:-.02em}"
            "p{margin:0;color:rgba(242,244,248,.72);line-height:1.45;font-size:.98rem}"
            ".brand{margin-top:22px;font-size:.8rem;color:rgba(242,244,248,.42)}"
            "</style></head><body><div class='card'><div class='check'>&#10003;</div>"
            "<h1>You&rsquo;re signed in</h1>"
            "<p>You can close this tab and return to <strong>Oz Downloader</strong>.</p>"
            "<div class='brand'>Oz Downloader</div></div>"
            "<script>setTimeout(function(){try{window.close()}catch(e){}},1800);</script>"
            "</body></html>"
        )

        client_id = Zotify.CONFIG.get_api_client_id()
        if not client_id:
            client_id = MercuryRequests.keymaster_client_id

        oauth = (
            OAuth(client_id, redirect_url, oauth_print)
            .set_scopes(SCOPES)
            .set_listen_all(True)
            .set_success_page_content(success_html)
        )
        session_builder = Session.Builder()
        session_builder.conf.store_credentials = False
        try:
            session_builder.login_credentials = oauth.flow()
        except Exception as e:
            print("OZ_JSON|" + json.dumps({"ok": False, "error": str(e)}), flush=True)
            raise SystemExit(1)

        if Zotify.CONFIG.get_save_credentials():
            Zotify.CRED_FILE = cred_path
            if client_id != MercuryRequests.keymaster_client_id:
                Zotify.OAUTH = oauth
                oauth.save_creds(str(Zotify.CRED_FILE))
            else:
                session_builder.conf.store_credentials = True
                session_builder.conf.stored_credentials_file = str(Zotify.CRED_FILE)

        Zotify.SESSION = session_builder.create()
        print("OZ_JSON|" + json.dumps({"ok": True, "saved": Path(cred_path).exists()}), flush=True)
        """#
            .replacingOccurrences(of: "__OZ_CONFIG__", with: AppPaths.pythonPathLiteral(AppPaths.zotifyConfigURL))
            .replacingOccurrences(of: "__FORCE_FRESH__", with: forceFreshLogin ? "True" : "False")

        let cancel = signInCancelFlag

        do {
            let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CommandResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try ZotifyCLI.run(
                            executable: python,
                            arguments: ["-c", script],
                            onLine: { line in
                                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.hasPrefix("AUTH_URL|") {
                                    let urlString = String(trimmed.dropFirst("AUTH_URL|".count))
                                    guard let url = URL(string: urlString) else { return }
                                    DispatchQueue.main.async {
                                        let firstOpen = self.pendingAuthURL == nil
                                        self.pendingAuthURL = urlString
                                        Self.writeE2EAuthURL(urlString)
                                        if firstOpen {
                                            NSWorkspace.shared.open(url)
                                            self.appendLog("Browser opened — finish signing in with Spotify.")
                                            self.showToast("Complete sign-in in your browser")
                                        }
                                    }
                                    return
                                }
                                if trimmed.hasPrefix("OZ_JSON|") || trimmed.hasPrefix("{") { return }
                                if !trimmed.isEmpty {
                                    DispatchQueue.main.async { self.appendLog(line) }
                                }
                            },
                            isCancelled: { cancel.value },
                            // OAuth waits on the browser with no stdout — never stall-kill.
                            stallTimeout: 0
                        )
                        cont.resume(returning: r)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }

            if cancel.value {
                appendLog("Sign-in cancelled.")
                return false
            }

            if let obj = result.ozJSON(), (obj["ok"] as? Bool) == true {
                appendLog("Signed in successfully.")
                store.syncAccountFromCredentials()
                store.objectWillChange.send()
                showToast("Signed in")
                return true
            }

            let detail = Self.signInFailureDetail(from: result)

            if result.exitCode != 0 {
                appendLog("Sign-in didn’t finish. \(detail)")
                showToast(detail)
            } else if pendingAuthURL == nil {
                appendLog("Sign-in started but no browser URL was received. Try again.")
                showToast("Sign-in couldn’t open the browser — try again")
            }
        } catch {
            appendLog("Sign-in failed: \(error.localizedDescription)")
            showToast("Sign-in failed")
        }
        return false
    }

    private nonisolated static func signInFailureDetail(from result: CommandResult) -> String {
        if result.exitCode == 124 {
            return "Sign-in timed out — try again"
        }
        if let obj = result.ozJSON(), let err = obj["error"] as? String, !err.isEmpty {
            let lower = err.lowercased()
            if lower.contains("module") || lower.contains("zotify") {
                return "Install zotify first, then sign in"
            }
            return "Sign-in didn’t finish — try again"
        }
        let lower = result.output.lowercased()
        if lower.contains("no module named 'zotify'") || lower.contains("no module named \"zotify\"") {
            return "Install zotify first, then sign in"
        }
        if lower.contains("modulenotfounderror") || lower.contains("no module named") {
            return "Install zotify first, then sign in"
        }
        return "Sign-in didn’t finish — try again"
    }

    /// When OZ_E2E=1, write the authorize URL so oauth_browser_helper.py can complete login.
    nonisolated private static func writeE2EAuthURL(_ urlString: String) {
        guard ProcessInfo.processInfo.environment["OZ_E2E"] == "1" else { return }
        let dir = AppPaths.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("e2e_oauth_url.txt")
        try? urlString.write(to: file, atomically: true, encoding: .utf8)
    }
}
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
