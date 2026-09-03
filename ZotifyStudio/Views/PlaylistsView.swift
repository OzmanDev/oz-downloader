import SwiftUI
import AppKit

struct PlaylistsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var previews: LinkPreviewService

    @State private var selectedFetched: Set<String> = []
    @State private var selectedSaved: Set<String> = []
    @State private var url = ""
    @State private var busy = false
    @State private var showAddSheet = false
    @State private var filter: PlaylistFilter = .all
    @State private var searchText: String = ""
    @State private var addLookupTask: Task<Void, Never>?
    @State private var addIsLookingUp = false
    @State private var addError: String?
    @State private var addPreview: LinkPreview?

    private var fetched: [FetchedPlaylist] { store.spotifyPlaylists }

    /// Playlists in the selected category (before search).
    private var categoryFetched: [FetchedPlaylist] {
        let items = fetched.map(classify)
        switch filter {
        case .all: return items
        case .byMe: return items.filter(\.isOwned)
        case .followed: return items.filter { !$0.isOwned && !$0.isSpotify }
        case .spotify: return items.filter(\.isSpotify)
        }
    }

    /// Category filter + search query.
    private var filteredFetched: [FetchedPlaylist] {
        let items = categoryFetched
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { pl in
            pl.name.localizedCaseInsensitiveContains(q)
                || (pl.owner?.localizedCaseInsensitiveContains(q) ?? false)
                || categoryLabel(for: pl).localizedCaseInsensitiveContains(q)
        }
    }

    private func filterCount(_ f: PlaylistFilter) -> Int {
        let items = fetched.map(classify)
        switch f {
        case .all: return items.count
        case .byMe: return items.filter(\.isOwned).count
        case .followed: return items.filter { !$0.isOwned && !$0.isSpotify }.count
        case .spotify: return items.filter(\.isSpotify).count
        }
    }

    private func classify(_ pl: FetchedPlaylist) -> FetchedPlaylist {
        var copy = pl
        if copy.id.hasPrefix("37i9") {
            copy.isSpotify = true
            copy.isOwned = false
            if (copy.owner ?? "").isEmpty { copy.owner = "Spotify" }
            return copy
        }
        let userId = store.account.userId
        let display = store.account.displayName
        if let owner = copy.owner, !owner.isEmpty {
            if (!userId.isEmpty && owner == userId)
                || (!display.isEmpty && owner.caseInsensitiveCompare(display) == .orderedSame) {
                copy.isOwned = true
            }
        } else if copy.isOwned {
            // keep existing flag
        }
        return copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            toolbar

            HStack(alignment: .top, spacing: 16) {
                spotifySide
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                savedSide
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showAddSheet, onDismiss: resetAddSheet) {
            addSheet
        }
        .onAppear {
            if store.isLoggedIn, !busy {
                Task { await fetch() }
            }
        }
        .onChange(of: store.isLoggedIn) { loggedIn in
            if loggedIn {
                Task { await fetch() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("My playlists")
                .font(.largeTitle.bold())
            Text("Select one or more playlists, then tap Download selected for a single or bulk download. Progress shows on Get Music.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hasDownloadSelection: Bool {
        !selectedFetched.isEmpty || !selectedSaved.isEmpty
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if store.isLoggedIn {
                Button {
                    Task { await fetch() }
                } label: {
                    Label(busy ? "Refreshing…" : "Load from Spotify", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || downloads.isSigningIn)
                .accessibilityIdentifier("playlists.refresh")
            }

            if hasDownloadSelection {
                Button(downloads.isRunning ? "Add selected to queue" : "Download selected") { downloadSelected() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("playlists.downloadSelected")
            }

            Spacer()

            Button {
                showAddSheet = true
            } label: {
                Label("Add playlist link", systemImage: "plus")
            }
        }
    }

    private var spotifySide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On Spotify")
                .font(.headline)
            Text(store.isLoggedIn
                  ? "Tap the circle next to a playlist to select it — pick several for bulk download."
                  : "Sign in to see playlists from your Spotify account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !downloads.playlistStatusMessage.isEmpty, store.isLoggedIn {
                Text(downloads.playlistStatusMessage)
                    .font(.caption)
                    .foregroundStyle(downloads.playlistStatusMessage.localizedCaseInsensitiveContains("rate") ? .orange : .red)
                    .accessibilityIdentifier("playlists.status")
            }

            if store.isLoggedIn, !fetched.isEmpty {
                Picker("Filter", selection: $filter) {
                    ForEach(PlaylistFilter.allCases) { f in
                        Text("\(f.title) (\(filterCount(f)))").tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search \(filter.title.lowercased()) playlists", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if busy {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            }

            Group {
                if !store.isLoggedIn {
                    loginRequiredPanel
                } else if busy && fetched.isEmpty {
                    ProgressView("Talking to Spotify…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if fetched.isEmpty {
                    emptyPanel(
                        title: "No playlists loaded",
                        systemImage: "music.note.list",
                        detail: "Press “Load from Spotify” to see your playlists here."
                    )
                } else if categoryFetched.isEmpty {
                    emptyPanel(
                        title: "Nothing in this filter",
                        systemImage: "line.3.horizontal.decrease.circle",
                        detail: "Try another filter, or reload from Spotify."
                    )
                } else if filteredFetched.isEmpty {
                    emptyPanel(
                        title: "No matches",
                        systemImage: "magnifyingglass",
                        detail: "No playlists match “\(searchText)” in \(filter.title)."
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredFetched) { pl in
                                playlistRow(pl)
                                Divider()
                                    .opacity(0.35)
                                    .padding(.leading, 90)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func playlistRow(_ pl: FetchedPlaylist) -> some View {
        let selected = selectedFetched.contains(pl.id)
        return Button {
            if selected {
                selectedFetched.remove(pl.id)
            } else {
                selectedFetched.insert(pl.id)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.55))
                    .frame(width: 22)

                PlaylistArtworkView(imageURL: pl.imageURL, spotifyURL: pl.url, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pl.name)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    Text(spotifySubtitle(for: pl))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playlists.row.\(pl.id)")
    }

    private func spotifySubtitle(for pl: FetchedPlaylist) -> String {
        var parts: [String] = ["Playlist"]
        if let owner = friendlyOwner(pl) {
            parts.append(owner)
        } else if pl.isSpotify {
            parts.append("Spotify")
        }
        if !pl.tracksLabel.isEmpty {
            parts.append(pl.tracksLabel)
        }
        return parts.joined(separator: " · ")
    }

    private func categoryLabel(for pl: FetchedPlaylist) -> String {
        if pl.isSpotify { return "Spotify" }
        if pl.isOwned { return "By me" }
        return "Followed"
    }

    private func friendlyOwner(_ pl: FetchedPlaylist) -> String? {
        guard let owner = pl.owner, !owner.isEmpty else { return nil }
        if pl.isOwned {
            let display = store.account.displayName
            return display.isEmpty ? "You" : display
        }
        if pl.isSpotify { return "Spotify" }
        if owner == store.account.userId {
            let display = store.account.displayName
            return display.isEmpty ? nil : display
        }
        // Hide opaque Spotify user ids (hex hashes or long numeric ids).
        if owner.allSatisfy(\.isNumber) { return nil }
        if owner.allSatisfy({ $0.isNumber || $0.isLetter }) && owner.count > 20 {
            return nil
        }
        return owner
    }

    private var loginRequiredPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Login required")
                .font(.headline)
            Text("Sign in with Spotify to load your playlists here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if downloads.isSigningIn {
                ProgressView("Waiting for Spotify…")
                    .controlSize(.small)
                HStack(spacing: 10) {
                    Button("Open page again") {
                        downloads.reopenSignInPage()
                    }
                    .disabled(downloads.pendingAuthURL == nil)
                    Button("Cancel") {
                        downloads.cancelSignIn()
                    }
                }
            } else {
                Button {
                    Task { await signIn() }
                } label: {
                    Label("Sign in with Spotify", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var savedSide: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved here")
                        .font(.headline)
                    Text("Select saved playlists too — same Download selected button for bulk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !store.playlists.isEmpty {
                Text("\(store.playlists.count) saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                if store.playlists.isEmpty {
                    emptyPanel(
                        title: "Nothing saved yet",
                        systemImage: "tray",
                        detail: "Add a link manually, or finish a download on Get Music — playlists are saved here automatically."
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.playlists) { pl in
                                savedPlaylistRow(pl)
                                Divider()
                                    .opacity(0.35)
                                    .padding(.leading, 90)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func savedPlaylistRow(_ pl: SavedPlaylist) -> some View {
        let selected = selectedSaved.contains(pl.alias)
        return HStack(alignment: .center, spacing: 8) {
            Button {
                if selected {
                    selectedSaved.remove(pl.alias)
                } else {
                    selectedSaved.insert(pl.alias)
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.55))
                        .frame(width: 22)

                    PlaylistArtworkView(imageURL: pl.imageURL, spotifyURL: pl.url, size: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pl.name)
                            .font(.body.weight(selected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)

                        Text(
                            pl.tracksLabel.isEmpty
                                ? "Playlist"
                                : "Playlist · \(pl.tracksLabel)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                selectedSaved.remove(pl.alias)
                store.removePlaylist(alias: pl.alias)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from saved")
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
    }

    private func emptyPanel(title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a playlist")
                .font(.title2.bold())
            Text("Paste a Spotify link — we’ll check it and use the name from Spotify.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Spotify link", text: $url, prompt: Text("https://open.spotify.com/playlist/…"))
                .textFieldStyle(.roundedBorder)
                .onChange(of: url) { newValue in
                    scheduleAddLookup(newValue)
                }

            if addIsLookingUp {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking link…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let err = addError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let preview = addPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview.name)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(addKindLabel(preview.kind))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        if !preview.tracksLabel.isEmpty {
                            Text(preview.tracksLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !preview.detail.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(preview.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }

            HStack {
                Spacer()
                Button("Cancel") { showAddSheet = false }
                Button("Add") {
                    saveValidatedAdd()
                }
                .buttonStyle(.borderedProminent)
                .disabled(addPreview == nil || addIsLookingUp)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func addKindLabel(_ kind: String) -> String {
        switch kind {
        case "album": return "Album"
        case "track": return "Song"
        case "playlist": return "Playlist"
        default: return "Link"
        }
    }

    private func resetAddSheet() {
        addLookupTask?.cancel()
        url = ""
        addIsLookingUp = false
        addError = nil
        addPreview = nil
    }

    private func scheduleAddLookup(_ text: String) {
        addLookupTask?.cancel()
        addPreview = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            addIsLookingUp = false
            addError = nil
            return
        }

        let urls = LinkPreviewService.extractSpotifyURLs(from: trimmed)
        guard !urls.isEmpty else {
            addIsLookingUp = false
            addError = "That doesn’t look like a Spotify playlist, album, or song link."
            return
        }

        addError = nil
        addIsLookingUp = true
        let root = store.settings.rootPath
        addLookupTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            let result = await LinkPreviewService.lookup(urlText: trimmed, musicRoot: root)
            guard !Task.isCancelled else { return }
            addIsLookingUp = false
            if let preview = result.preview {
                addPreview = preview
                addError = nil
            } else {
                addPreview = nil
                addError = result.error
            }
        }
    }

    private func saveValidatedAdd() {
        guard let preview = addPreview else { return }
        let name = preview.name
        let url = preview.url
        let tracks = preview.trackCount
        showAddSheet = false
        resetAddSheet()
        downloads.showToast("Saved — \(name)")
        Task {
            let thumb = await PlaylistImageCache.shared.oEmbedThumbnail(for: url) ?? ""
            store.rememberPlaylist(
                name: name,
                url: url,
                trackCount: tracks,
                imageURL: thumb
            )
        }
    }

    private func fetch() async {
        guard store.isLoggedIn else { return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let items = await downloads.fetchPlaylists(store: store)
        if !items.isEmpty {
            store.replaceSpotifyPlaylists(items)
        }
        selectedFetched = []
    }

    private func signIn() async {
        let ok = await downloads.signInWithSpotify(store: store)
        store.syncAccountFromCredentials()
        if ok {
            store.clearAvatar()
            await store.refreshAccountProfile()
            await fetch()
        }
    }

    private func downloadSelected() {
        let fromSpotify = filteredFetched.filter { selectedFetched.contains($0.id) }
        let fromSaved = store.playlists.filter { selectedSaved.contains($0.alias) }
        guard !fromSpotify.isEmpty || !fromSaved.isEmpty else { return }

        var queue: [DownloadQueueItem] = []
        var seen = Set<String>()

        for pl in fromSpotify {
            let key = AppStore.normalizeSpotifyURL(pl.url)
            guard seen.insert(key).inserted else { continue }
            queue.append(
                DownloadQueueItem(
                    name: pl.name,
                    url: pl.url,
                    trackCount: pl.trackCount,
                    imageURL: pl.imageURL
                )
            )
        }
        for pl in fromSaved {
            let key = AppStore.normalizeSpotifyURL(pl.url)
            guard seen.insert(key).inserted else { continue }
            queue.append(
                DownloadQueueItem(
                    name: pl.name,
                    url: pl.url,
                    trackCount: pl.trackCount,
                    imageURL: pl.imageURL
                )
            )
        }
        guard !queue.isEmpty else { return }

        let toast: String
        if queue.count == 1 {
            toast = "Working on — \(queue[0].name)"
        } else {
            toast = "Working on — \(queue.count) playlists"
        }

        downloads.showProgressDetails = true
        // Playlist downloads: no link-preview card — only Progress.
        previews.clear()
        let urls = queue.map(\.url)
        let expected = queue.reduce(0) { $0 + max($1.trackCount, 0) }
        let firstCount = max(queue.first?.trackCount ?? 0, expected > 0 ? min(expected, queue.first?.trackCount ?? expected) : 1, 1)
        let placeholders = (0..<firstCount).map { "Song \($0 + 1)" }

        // Show Progress on Get Music immediately (do not wait for metadata lookup).
        if !downloads.isRunning {
            downloads.prepareJobUI(
                queue: queue,
                expectedTracks: max(expected, firstCount),
                trackNames: placeholders,
                trackIds: []
            )
        }
        downloads.requestShowGetMusic = true
        // Prefetch real track titles in background (Progress already visible with placeholders).
        if let first = queue.first {
            downloads.prefetchTrackTitlesInBackground(url: first.url, musicRoot: store.settings.rootPath)
        }

        Task {
            let toastForRun: String
            if downloads.isRunning {
                toastForRun = queue.count == 1
                    ? "Queued — \(queue[0].name)"
                    : "Queued \(queue.count) playlists"
            } else {
                toastForRun = toast
            }
            let ok = await downloads.download(
                urls: urls,
                settings: store.settings,
                store: store,
                expectedTracks: expected,
                trackNames: [],
                trackIds: [],
                startedToast: toastForRun,
                queue: queue
            )
            if ok {
                for pl in fromSpotify {
                    store.rememberPlaylist(
                        name: pl.name,
                        url: pl.url,
                        trackCount: pl.trackCount,
                        imageURL: pl.imageURL
                    )
                }
            }
        }
    }
}
