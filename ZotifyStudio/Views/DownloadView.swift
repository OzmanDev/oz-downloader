import SwiftUI
import AppKit

struct DownloadView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var previews: LinkPreviewService

    @State private var linkFieldFocused = false
    @State private var searchPulse = false
    @State private var celebrationScale: CGFloat = 0
    @State private var celebrationOpacity: Double = 0
    @State private var confettiPhase: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                pasteCard
                previewSection

                if hasActiveLinkPreview {
                    optionsCard
                }

                actionsRow

                // Keep Progress visible during + after a job so Get Music isn’t blank.
                if downloads.isRunning
                    || downloads.isConverting
                    || !downloads.queueItems.isEmpty
                    || !downloads.songItems.isEmpty
                    || !downloads.downloadErrorMessage.isEmpty
                    || downloads.statusMessage.lowercased().contains("stop") {
                    progressCard
                }
            }
            .padding(24)
        }
        .onChange(of: previews.urlsText) { newValue in
            previews.schedulePreview(for: newValue, musicRoot: store.settings.rootPath)
        }
        .onChange(of: previews.isLoading) { loading in
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                searchPulse = loading
            }
            if !loading {
                searchPulse = false
            }
        }
        .onAppear {
            if !previews.urlsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !previews.hasRenderablePreview,
               !previews.isLoading {
                previews.schedulePreview(for: previews.urlsText, musicRoot: store.settings.rootPath)
            }
            if downloads.showCelebration {
                celebrationScale = 1
                celebrationOpacity = 1
            }
        }
        .onDisappear {
            celebrationScale = 0
            celebrationOpacity = 0
        }
        .onChange(of: downloads.showCelebration) { show in
            if show {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55, blendDuration: 0)) {
                    celebrationScale = 1
                }
                withAnimation(.easeOut(duration: 0.4)) {
                    celebrationOpacity = 1
                }
            } else {
                celebrationScale = 0
                celebrationOpacity = 0
            }
        }
    }

    private var hasActiveLinkPreview: Bool {
        // Preview only when the user pasted a link (urlsText), not playlist downloads.
        !previews.urlsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && previews.hasRenderablePreview
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Get music")
                .font(.largeTitle.bold())
            Text("Paste a Spotify link to download.")
                .foregroundStyle(.secondary)
        }
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spotify link")
                .font(.headline)

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(linkFieldFocused || previews.isLoading ? Color.accentColor : .secondary)
                    .scaleEffect(previews.isLoading && searchPulse ? 1.12 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: searchPulse)

                TextField("Paste a Spotify playlist, album, or song link", text: $previews.urlsText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit {
                        previews.refreshNow(urlsText: previews.urlsText, musicRoot: store.settings.rootPath)
                    }

                if previews.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity.combined(with: .scale))
                } else if !previews.urlsText.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            previews.clear()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(linkBorderColor, lineWidth: previews.isLoading || previews.inputError != nil ? 1.5 : 1)
            )
            .shadow(
                color: previews.isLoading
                    ? Color.accentColor.opacity(searchPulse ? 0.28 : 0.08)
                    : .black.opacity(0.12),
                radius: previews.isLoading ? 10 : 4,
                y: 2
            )
            .animation(.easeInOut(duration: 0.25), value: previews.isLoading)
            .animation(.easeInOut(duration: 0.25), value: previews.inputError)
            .onTapGesture { linkFieldFocused = true }

            if previews.isLoading {
                HStack(spacing: 8) {
                    SearchingDots()
                    Text("Searching Spotify…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let err = previews.inputError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Playlist, album, or song from Spotify.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: previews.isLoading)
        .animation(.easeInOut(duration: 0.22), value: previews.inputError)
    }

    private var linkBorderColor: Color {
        if previews.inputError != nil { return .red.opacity(0.75) }
        if previews.isLoading { return Color.accentColor.opacity(searchPulse ? 0.9 : 0.45) }
        if linkFieldFocused { return Color.accentColor.opacity(0.55) }
        return Color.secondary.opacity(0.28)
    }

    @ViewBuilder
    private var previewSection: some View {
        let okPreviews = previews.previews.enumerated().filter { $0.element.error == nil }
        if hasActiveLinkPreview, !okPreviews.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview")
                    .font(.headline)
                ForEach(Array(okPreviews), id: \.element.id) { index, preview in
                    LinkPreviewCard(
                        preview: preview,
                        downloadTitle: downloadButtonTitle(for: preview),
                        isDownloading: downloads.isRunning,
                        canDownload: !collectURLs().isEmpty,
                        onDownload: index == okPreviews.first?.offset ? { start() } : nil
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: previews.previews)
        } else if shouldShowPreviewLoader {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview")
                    .font(.headline)
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading preview…")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    private var shouldShowPreviewLoader: Bool {
        // Loader only for pasted links — never for My Playlists downloads.
        let hasInput = !previews.urlsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasError = previews.inputError != nil
        return hasInput && !hasError && !previews.hasRenderablePreview && previews.isLoading
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save as")
                .font(.headline)

            Picker("File format", selection: Binding(
                get: { store.settings.convertFormat },
                set: { store.settings.convertFormat = $0 }
            )) {
                ForEach(AudioFormatChoice.allCases) { opt in
                    Text(opt.label).tag(opt.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 320, alignment: .leading)

            Toggle("Convert files after downloading", isOn: Binding(
                get: { store.settings.autoPostprocess },
                set: { store.settings.autoPostprocess = $0 }
            ))

            VStack(alignment: .leading, spacing: 6) {
                Text("Genre tag")
                    .font(.subheadline.weight(.medium))
                Text("Optional — written into each file’s tags when converting (e.g. for DJing / library sorting).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "",
                    text: Binding(
                        get: { store.settings.defaultGenre },
                        set: { store.settings.defaultGenre = $0 }
                    ),
                    prompt: Text("e.g. Afrobeats, House")
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {
            if downloads.isRunning {
                Button("Cancel", role: .destructive) {
                    downloads.stop()
                }
                .controlSize(.large)
            }

            Button {
                openMusic()
            } label: {
                Label("Open default download folder", systemImage: "folder")
            }
            .controlSize(.large)

            Spacer()

            if downloads.isRunning, !downloads.statusMessage.isEmpty {
                Text(friendlyStatus(downloads.statusMessage))
                    .foregroundStyle(.secondary)
            } else if downloads.isConverting {
                Text("Converting…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Progress", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                if downloads.isConverting {
                    Text(downloads.convertLabel.isEmpty ? "Converting…" : downloads.convertLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView()
                        .controlSize(.small)
                } else if downloads.isRunning {
                    if downloads.songItems.allSatisfy(\.isFinished), !downloads.songItems.isEmpty {
                        Text("Preparing convert…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if downloads.downloadSpeedLabel.isEmpty {
                        Text("Fetching track info…")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(downloads.downloadSpeedLabel)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Download speed")
                    }
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if downloads.showCelebration {
                celebrationBanner
            } else {
                Text(progressSummary)
                    .foregroundStyle(.secondary)
            }

            if !downloads.retryStatusMessage.isEmpty, downloads.isRunning {
                Text(downloads.retryStatusMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
            }

            if !downloads.downloadErrorMessage.isEmpty {
                Label(downloads.downloadErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if downloads.queueItems.count > 1 || downloads.queueItems.contains(where: { $0.status == .pending }) {
                playlistQueueSection
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(downloads.queueItems.count > 1 ? "This playlist" : "Total")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(totalProgressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: downloads.totalFraction)
                    .progressViewStyle(.linear)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    downloads.showProgressDetails.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(downloads.showProgressDetails ? 90 : 0))
                    Text(downloads.showProgressDetails ? "Hide details" : "Show details")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if downloads.showProgressDetails {
                VStack(alignment: .leading, spacing: 10) {
                    if downloads.songItems.isEmpty {
                        Text("Song-by-song progress will appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(downloads.songItems) { song in
                                    songRow(song)
                                }
                                if showsConvertStep {
                                    convertStepRow
                                }
                            }
                            .padding(.top, 4)
                        }
                        .frame(minHeight: 140, maxHeight: 280)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var celebrationBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
                .scaleEffect(celebrationScale)
                .shadow(color: .green.opacity(0.4), radius: 8, y: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hell yeah, all done!")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text("Open Downloads to listen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(celebrationOpacity)

            Spacer()

            TimelineView(.animation(minimumInterval: 0.4, paused: !downloads.showCelebration)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 4
                HStack(spacing: 4) {
                    ForEach(["🎵", "🎶", "🔥", "🎉"], id: \.self) { emoji in
                        let idx = ["🎵", "🎶", "🔥", "🎉"].firstIndex(of: emoji)!
                        Text(emoji)
                            .font(.title2)
                            .scaleEffect(tick == idx ? 1.3 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: tick)
                    }
                }
            }
            .opacity(celebrationOpacity)
        }
        .padding(.vertical, 4)
    }

    private var showsConvertStep: Bool {
        downloads.autoConvertEnabled && !downloads.songItems.isEmpty
    }

    private var convertStepRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("•")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(downloads.convertLabel.isEmpty ? "Converting to FLAC + lyrics…" : downloads.convertLabel)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text(convertStatusLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: convertBarValue)
                .progressViewStyle(.linear)
                .tint(convertBarTint)
        }
        .padding(.top, 2)
    }

    private var convertBarValue: Double {
        if downloads.isConverting || downloads.convertFraction > 0 {
            return max(0.02, downloads.convertFraction)
        }
        if downloads.songItems.allSatisfy(\.isFinished), !downloads.songItems.isEmpty {
            return 0.02
        }
        return 0
    }

    private var convertBarTint: Color {
        if downloads.convertSkipped { return .orange }
        if downloads.convertFraction >= 1, !downloads.isConverting { return .green }
        if downloads.convertLabel.localizedCaseInsensitiveContains("fail") { return .orange }
        return .accentColor
    }

    private var convertStatusLabel: String {
        if downloads.convertSkipped { return "Skipped" }
        if downloads.convertLabel.localizedCaseInsensitiveContains("fail") { return "Failed" }
        if downloads.convertFraction >= 1, !downloads.isConverting { return "Done" }
        if downloads.isConverting { return "\(Int(downloads.convertFraction * 100))%" }
        if downloads.songItems.allSatisfy(\.isFinished), !downloads.songItems.isEmpty { return "Waiting" }
        return "—"
    }

    private func songRow(_ song: SongDownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(song.number).")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                    .monospacedDigit()
                Text(song.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if downloads.isRunning, !song.isFinished {
                    Button {
                        downloads.cancelSong(id: song.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Skip this song")
                }
                Text(songStatusLabel(song))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: song.fraction)
                .progressViewStyle(.linear)
                .tint(songBarColor(song))
        }
    }

    private var playlistQueueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(downloads.queueItems.enumerated()), id: \.element.id) { index, item in
                let role = downloads.queueRole(for: index)
                HStack(alignment: .center, spacing: 10) {
                    Text(role)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(roleColor(role))
                        .frame(width: 44, alignment: .leading)

                    PlaylistArtworkView(imageURL: item.imageURL, spotifyURL: item.url, size: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.subheadline.weight(role == "Now" ? .semibold : .regular))
                            .foregroundStyle((role == "Done" || role == "Skipped") ? .secondary : .primary)
                            .lineLimit(1)
                        if role == "Now", item.retryAttempt > 1 {
                            Text("Retry \(item.retryAttempt) of 5")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else if role == "Failed", !item.lastError.isEmpty {
                            Text(item.lastError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        } else if item.trackCount > 0 {
                            Text(item.trackCount == 1 ? "1 song" : "\(item.trackCount) songs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if downloads.isRunning, role == "Now" || role == "Next" || role == "Then" {
                        Button {
                            downloads.cancelPlaylist(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel this playlist")
                    }
                    if role == "Now", downloads.isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    } else if role == "Done" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if role == "Failed" {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    } else if role == "Skipped" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "Now": return .accentColor
        case "Next": return .primary
        case "Done": return .secondary
        case "Skipped": return .orange
        case "Failed": return .orange
        default: return .secondary
        }
    }

    private var totalProgressLabel: String {
        if downloads.totalExpected > 0 {
            return "\(downloads.totalCompleted) of \(downloads.totalExpected)"
        }
        if downloads.isRunning {
            return "Starting…"
        }
        return downloads.statusMessage.lowercased().contains("done") ? "Complete" : "—"
    }

    private var progressSummary: String {
        if downloads.isConverting {
            return downloads.convertLabel.isEmpty
                ? "Converting downloaded files…"
                : downloads.convertLabel
        }
        if downloads.isRunning {
            if !downloads.songItems.isEmpty, downloads.songItems.allSatisfy(\.isFinished) {
                return "Download done — converting to FLAC, embedding lyrics, and renaming…"
            }
            if downloads.queueItems.count > 1,
               let current = downloads.queueItems.first(where: { $0.status == .downloading }) {
                let n = downloads.currentQueueIndex + 1
                let total = downloads.queueItems.count
                return "Downloading “\(current.name)” (\(n) of \(total)). You can leave this window open."
            }
            return "Downloading your music. You can leave this window open."
        }
        if downloads.songItems.isEmpty && downloads.queueItems.isEmpty {
            return "Ready when you are."
        }
        let status = downloads.statusMessage.lowercased()
        let anyFailed = downloads.songItems.contains(where: { $0.status == .failed })
        if status.contains("done"), !anyFailed {
            if downloads.queueItems.count > 1 {
                return "All \(downloads.queueItems.count) playlists finished."
            }
            return "All finished. Open Downloads to listen."
        }
        if anyFailed || status.contains("fail") || status.contains("error") {
            if !downloads.downloadErrorMessage.isEmpty {
                return downloads.downloadErrorMessage
            }
            let n = downloads.songItems.filter { $0.status == .failed }.count
            if n > 0 {
                return "\(n) song\(n == 1 ? "" : "s") couldn’t download. Spotify may have blocked the stream — try again."
            }
        }
        if status.contains("stop") {
            return "Cancelled."
        }
        if status.contains("setup") {
            if !downloads.downloadErrorMessage.isEmpty {
                return downloads.downloadErrorMessage
            }
            return "Something went wrong after retries. Check the error above, then try again."
        }
        return friendlyStatus(downloads.statusMessage)
    }

    private func songStatusLabel(_ song: SongDownloadItem) -> String {
        switch song.status {
        case .pending: return "Waiting"
        case .downloading: return "\(Int(song.fraction * 100))%"
        case .done: return "Done"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        }
    }

    private func songBarColor(_ song: SongDownloadItem) -> Color {
        switch song.status {
        case .done: return .green
        case .skipped: return .orange
        case .failed: return .red
        case .downloading: return .accentColor
        case .pending: return .secondary
        }
    }

    private func downloadButtonTitle(for preview: LinkPreview) -> String {
        switch preview.status {
        case .fullyDownloaded: return "Download again"
        case .partiallyDownloaded: return "Download remaining"
        default: return "Download"
        }
    }

    private func friendlyStatus(_ raw: String) -> String {
        switch raw.lowercased() {
        case "downloading…", "downloading...": return "Downloading…"
        case "converting…", "converting...": return "Converting to FLAC…"
        case "adding lyrics…", "adding lyrics...": return "Adding lyrics…"
        case "renaming…", "renaming...": return "Renaming songs…"
        case "done": return "Finished"
        case "stopped": return "Cancelled"
        case "setup needed": return "Setup needed — install zotify first"
        case "stopping…", "stopping...": return "Cancelling…"
        default: return raw
        }
    }

    private func collectURLs() -> [String] {
        var urls: [String] = []
        for line in previews.urlsText.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { urls.append(s) }
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    private func start() {
        let urls = collectURLs()
        guard !urls.isEmpty else { return }
        downloads.showProgressDetails = true
        let preview = previews.previews.first(where: { $0.error == nil })
        let expected = preview?.trackCount ?? 0
        let names = preview?.trackNames ?? []
        let trackIds = preview?.trackIds ?? []
        let toRemember = previews.previews.filter { preview in
            preview.error == nil && urls.contains(where: { AppStore.sameSpotifyURL($0, preview.url) })
        }
        let initialQueue: [DownloadQueueItem] = urls.enumerated().map { idx, url in
            let preview = toRemember.first(where: { AppStore.sameSpotifyURL($0.url, url) })
                ?? (idx == 0 ? previews.previews.first(where: { $0.error == nil }) : nil)
            return DownloadQueueItem(
                name: preview?.name ?? "Playlist",
                url: url,
                trackCount: preview?.trackCount ?? (idx == 0 ? expected : 0),
                imageURL: ""
            )
        }
        // Keep paste-based preview; show Progress immediately.
        if !downloads.isRunning {
            downloads.prepareJobUI(
                queue: initialQueue,
                expectedTracks: max(expected, names.count, trackIds.count, 1),
                trackNames: names.isEmpty
                    ? (0..<max(expected, 1)).map { "Song \($0 + 1)" }
                    : names,
                trackIds: trackIds
            )
        }
        Task {
            let startedToast: String? = {
                if let preview, preview.status == .fullyDownloaded {
                    return "Already on this Mac — checking for anything new…"
                }
                if let preview, preview.status == .partiallyDownloaded {
                    return "Downloading remaining — \(preview.name)"
                }
                return nil
            }()

            let ok = await downloads.download(
                urls: urls,
                settings: store.settings,
                store: store,
                expectedTracks: expected,
                trackNames: names,
                trackIds: trackIds,
                startedToast: startedToast,
                queue: initialQueue
            )
            if ok {
                for preview in toRemember {
                    let thumb = await PlaylistImageCache.shared.oEmbedThumbnail(for: preview.url) ?? ""
                    store.rememberPlaylist(
                        name: preview.name,
                        url: preview.url,
                        trackCount: preview.trackCount,
                        imageURL: thumb
                    )
                }
                // Don’t overwrite the “nothing to convert” toast when everything was already local.
                let allAlreadyLocal = toRemember.allSatisfy { $0.status == .fullyDownloaded }
                if !toRemember.isEmpty, !allAlreadyLocal {
                    downloads.showToast(toRemember.count == 1
                        ? "Saved to My Playlists"
                        : "Saved \(toRemember.count) playlists")
                }
            }
            previews.refreshNow(urlsText: previews.urlsText, musicRoot: store.settings.rootPath)
        }
    }

    private func openMusic() {
        let url = URL(fileURLWithPath: store.settings.rootPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

private struct SearchingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.28, paused: false)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.28) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.accentColor.opacity(phase == i ? 1 : 0.35))
                        .frame(width: 5, height: 5)
                        .scaleEffect(phase == i ? 1.25 : 1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: phase)
        }
    }
}
