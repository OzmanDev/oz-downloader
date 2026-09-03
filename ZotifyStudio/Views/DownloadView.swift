import SwiftUI
import AppKit

struct DownloadView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var previews: LinkPreviewService

    @State private var linkFieldFocused = false
    @State private var celebrationScale: CGFloat = 0
    @State private var celebrationOpacity: Double = 0
    @State private var confettiPhase: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                pasteCard
                previewSection

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
            // Hard-disable layout animations when Preview / Progress appear or resize.
            .transaction { $0.disablesAnimations = true }
        }
        .onChange(of: previews.urlsText) { newValue in
            previews.schedulePreview(for: newValue, musicRoot: store.settings.rootPath)
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
            // No withAnimation — animating celebration was blanking the whole Get Music scroll view.
            celebrationScale = show ? 1 : 0
            celebrationOpacity = show ? 1 : 0
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

                TextField("Paste a Spotify playlist, album, or song link", text: $previews.urlsText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .accessibilityIdentifier("getMusic.urlField")
                    .onSubmit {
                        previews.refreshNow(urlsText: previews.urlsText, musicRoot: store.settings.rootPath)
                    }

                if previews.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if !previews.urlsText.isEmpty {
                    Button {
                        previews.clear()
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
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .onTapGesture { linkFieldFocused = true }

            if previews.isLoading {
                Text("Searching Spotify…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let err = previews.inputError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Playlist, album, or song from Spotify.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var linkBorderColor: Color {
        if previews.inputError != nil { return .red.opacity(0.75) }
        if previews.isLoading { return Color.accentColor.opacity(0.7) }
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
                }
            }
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

    private var actionsRow: some View {
        HStack(spacing: 12) {
            if downloads.isRunning {
                Button("Cancel", role: .destructive) {
                    downloads.stop()
                }
                .controlSize(.large)
                .accessibilityIdentifier("getMusic.cancel")
            }

            Button {
                openMusic()
            } label: {
                Label("Open default download folder", systemImage: "folder")
            }
            .controlSize(.large)
            .accessibilityIdentifier("getMusic.openFolder")

            Spacer()

            if downloads.isConverting {
                Text(downloads.convertLabel.isEmpty ? "Converting…" : downloads.convertLabel)
                    .foregroundStyle(.secondary)
            } else if downloads.isRunning {
                Text(downloads.phaseStatusLabel.isEmpty
                     ? friendlyStatus(downloads.statusMessage)
                     : downloads.phaseStatusLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Progress", systemImage: "waveform")
                    .font(.headline)
                    .accessibilityIdentifier("progress.card")
                Spacer()
                if downloads.isRunning {
                    Button("Cancel", role: .destructive) {
                        downloads.stop()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("progress.cancel")
                }
                if downloads.isConverting {
                    Text(downloads.convertLabel.isEmpty ? "Converting…" : downloads.convertLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView()
                        .controlSize(.small)
                } else if downloads.isRunning {
                    if downloads.isConverting == false,
                       downloads.downloadPhase == .converting {
                        Text("Preparing convert…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if !downloads.downloadSpeedLabel.isEmpty {
                        Text(downloads.downloadSpeedLabel)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Download status")
                    } else {
                        Text(downloads.phaseStatusLabel.isEmpty ? "Starting…" : downloads.phaseStatusLabel)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
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
                    .accessibilityIdentifier("progress.summary")
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

            if !downloads.queueItems.isEmpty {
                playlistQueueSection
            }

            if showsConvertProgress {
                convertProgressSection
            } else {
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
            }

            Button {
                downloads.showProgressDetails.toggle()
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
                        let waiting = downloads.songItems.filter { $0.status == .pending }
                        let inProgress = downloads.songItems.filter {
                            $0.status == .downloading || $0.status == .failed
                        }
                        let skipped = downloads.songItems.filter { $0.status == .skipped }
                        let downloaded = downloads.songItems.filter { $0.status == .done }

                        HStack(alignment: .top, spacing: 8) {
                            progressColumn(title: "Waiting", songs: waiting, accent: .secondary)
                            progressColumn(title: "In progress", songs: inProgress, accent: .accentColor)
                            progressColumn(title: "Skipped", songs: skipped, accent: .orange)
                            progressColumn(title: "Downloaded", songs: downloaded, accent: .green)
                        }
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
                    }
                }
            }
            .opacity(celebrationOpacity)
        }
        .padding(.vertical, 4)
    }

    /// True once songs are done and convert is next / active / finished this run.
    private var showsConvertProgress: Bool {
        guard downloads.autoConvertEnabled else { return false }
        if downloads.isConverting || downloads.convertFraction > 0 { return true }
        if downloads.convertSkipped
            || downloads.convertLabel.localizedCaseInsensitiveContains("fail")
            || downloads.convertLabel.localizedCaseInsensitiveContains("converted")
            || downloads.convertLabel.localizedCaseInsensitiveContains("no new")
            || downloads.convertLabel.localizedCaseInsensitiveContains("nothing new")
            || downloads.convertLabel.localizedCaseInsensitiveContains("no .ogg") {
            return true
        }
        // Don't claim convert while library check / download is still running.
        switch downloads.downloadPhase {
        case .checkingExisting, .downloading, .starting, .fetchingTrackInfo, .signingIn, .retrying:
            return false
        default:
            break
        }
        guard !downloads.songItems.isEmpty, downloads.songItems.allSatisfy(\.isFinished) else { return false }
        return downloads.isRunning
    }

    private var isPreparingConvert: Bool {
        showsConvertProgress
            && downloads.isRunning
            && !downloads.isConverting
            && downloads.convertFraction <= 0
            && !downloads.convertSkipped
            && downloads.downloadPhase != .checkingExisting
            && downloads.downloadPhase != .downloading
    }

    private var convertProgressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Convert")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(convertStatusLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(convertProgressDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ProgressView(value: convertBarValue)
                .progressViewStyle(.linear)
                .tint(convertBarTint)
        }
    }

    private var convertProgressDetail: String {
        if downloads.convertSkipped {
            return downloads.convertLabel.isEmpty ? "Convert skipped" : downloads.convertLabel
        }
        if downloads.convertLabel.localizedCaseInsensitiveContains("fail") {
            return downloads.convertLabel
        }
        if downloads.convertFraction >= 1, !downloads.isConverting {
            return downloads.convertLabel.isEmpty
                ? "Converted · lyrics embedded · renamed"
                : downloads.convertLabel
        }
        if downloads.isConverting {
            return downloads.convertLabel.isEmpty ? "Converting to FLAC + lyrics…" : downloads.convertLabel
        }
        if isPreparingConvert {
            return "Download done — starting convert…"
        }
        return downloads.convertLabel.isEmpty ? "Converting to FLAC + lyrics…" : downloads.convertLabel
    }

    private var convertBarValue: Double {
        if downloads.isConverting || downloads.convertFraction > 0 {
            return max(0.02, downloads.convertFraction)
        }
        if isPreparingConvert { return 0.02 }
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
        if isPreparingConvert { return "Starting…" }
        if downloads.songItems.allSatisfy(\.isFinished), !downloads.songItems.isEmpty { return "Waiting" }
        return "—"
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
                    if role == "Now", downloads.isConverting {
                        ProgressView()
                            .controlSize(.mini)
                    } else if role == "Now", downloads.isRunning {
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
        if downloads.isConverting {
            return "\(Int(downloads.convertFraction * 100))%"
        }
        let expected = max(downloads.totalExpected, downloads.songItems.count, 0)
        if expected > 0 {
            let finished = downloads.songItems.filter(\.isFinished).count
            return "\(finished) of \(expected)"
        }
        if downloads.isRunning {
            return "Starting…"
        }
        return downloads.statusMessage.lowercased().contains("done") ? "Complete" : "—"
    }

    private var progressSummary: String {
        if downloads.isConverting {
            return downloads.convertLabel.isEmpty
                ? "Converting downloaded files to FLAC, embedding lyrics, and renaming…"
                : downloads.convertLabel
        }
        if downloads.isRunning {
            let finished = downloads.songItems.filter(\.isFinished).count
            let expected = max(downloads.totalExpected, downloads.songItems.count, 0)
            if !downloads.songItems.isEmpty,
               downloads.songItems.allSatisfy(\.isFinished),
               downloads.autoConvertEnabled {
                switch downloads.downloadPhase {
                case .checkingExisting, .downloading, .starting, .fetchingTrackInfo, .signingIn, .retrying:
                    break
                default:
                    return "Download done — starting convert…"
                }
            }
            if downloads.queueItems.count > 1,
               let current = downloads.queueItems.first(where: { $0.status == .downloading }) {
                let n = downloads.currentQueueIndex + 1
                let total = downloads.queueItems.count
                let phaseBit: String
                switch downloads.downloadPhase {
                case .checkingExisting: phaseBit = "Checking library"
                case .downloading: phaseBit = "Downloading new songs"
                case .fetchingTrackInfo: phaseBit = "Fetching track list"
                case .signingIn: phaseBit = "Waiting for Spotify sign-in"
                case .retrying: phaseBit = "Retrying"
                default: phaseBit = "Working on"
                }
                return "\(phaseBit) “\(current.name)” (\(n) of \(total)). You can leave this window open."
            }
            let summary = downloads.phaseProgressSummary
            if !summary.isEmpty { return summary }
            if expected > 0, finished > 0 {
                return "Working on your music (\(finished) of \(expected) saved). You can leave this window open."
            }
            return "Working on your music. You can leave this window open."
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressColumn(title: String, songs: [SongDownloadItem], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("(\(songs.count))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if songs.isEmpty {
                Text("None yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            } else {
                ForEach(songs) { song in
                    compactSongRow(song)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func compactSongRow(_ song: SongDownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 4) {
                Text("\(song.number).")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(song.name)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if downloads.isRunning,
                   song.status == .pending || song.status == .downloading {
                    Button {
                        downloads.cancelSong(id: song.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Skip this song")
                }
            }
            HStack {
                Text(songStatusLabel(song))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if song.status == .downloading || song.status == .failed
                || song.status == .done || song.status == .skipped {
                ProgressView(value: songBarValue(song))
                    .progressViewStyle(.linear)
                    .tint(songBarColor(song))
                    .controlSize(.mini)
            }
        }
    }

    private func songStatusLabel(_ song: SongDownloadItem) -> String {
        if downloads.isConverting, !song.isFinished {
            return "Converting…"
        }
        switch song.status {
        case .pending: return "Waiting"
        case .downloading:
            return "\(Int(max(song.fraction, 0) * 100))%"
        case .done: return "Downloaded"
        case .skipped:
            switch song.skipReason {
            case .duplicate: return "Duplicate"
            case .alreadySaved: return "Already here"
            case .cancelled: return "Cancelled"
            case .none: return "Skipped"
            }
        case .failed: return "Failed"
        }
    }

    private func songBarValue(_ song: SongDownloadItem) -> Double {
        if downloads.isConverting, !song.isFinished {
            return max(0.08, downloads.convertFraction)
        }
        switch song.status {
        case .done, .skipped, .failed: return 1
        case .downloading: return max(song.fraction, 0.05)
        case .pending: return 0
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

    private func songRow(_ song: SongDownloadItem) -> some View {
        compactSongRow(song)
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
        case "checking existing songs…", "checking existing songs...",
             "checking library…", "checking library...": return "Checking library…"
        case "fetching track list…", "fetching track list...",
             "fetching track info…", "fetching track info...": return "Fetching track list…"
        case "converting…", "converting...": return "Converting to FLAC…"
        case "adding lyrics…", "adding lyrics...": return "Adding lyrics…"
        case "renaming…", "renaming...": return "Renaming songs…"
        case "done": return "Finished"
        case "stopped": return "Cancelled"
        case "setup needed": return "Setup needed — install zotify first"
        case "stopping…", "stopping...", "cancelling…", "cancelling...": return "Cancelling…"
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
