import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var downloads: DownloadService

    @State private var confirmSignOut = false
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section {
                accountRow
            } header: {
                Text("Spotify account")
            }

            Section("Where files go") {
                HStack {
                    TextField("Default Download Folder", text: $store.settings.rootPath)
                    Button("Choose…") { chooseRoot() }
                }
                Button("Open default download folder") {
                    let url = URL(fileURLWithPath: store.settings.rootPath)
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
            }

            Section("Music quality") {
                Picker("Preferred quality", selection: $store.settings.downloadQuality) {
                    ForEach(QualityChoice.allCases) { q in
                        Text(q.label).tag(q.rawValue)
                    }
                }
                Picker("Save downloads as", selection: $store.settings.convertFormat) {
                    ForEach(AudioFormatChoice.allCases) { opt in
                        Text(opt.label).tag(opt.rawValue)
                    }
                }
                Toggle("Convert automatically after each download", isOn: $store.settings.autoPostprocess)
                TextField("Default genre (optional)", text: $store.settings.defaultGenre)
            }

            Section("When re-downloading") {
                Toggle("Skip songs I already have", isOn: $store.settings.skipExisting)
                Toggle("Skip songs downloaded before (even if moved)", isOn: $store.settings.skipPreviouslyDownloaded)
            }

            DisclosureGroup("Advanced options", isExpanded: $showAdvanced) {
                TextField("Pause between songs (seconds)", text: $store.settings.bulkWaitTime)
                TextField("Download speed limit (0 = fastest)", text: $store.settings.downloadRateLimiter)
                TextField("Retry failed songs", text: $store.settings.retryAttempts)
                Picker("Temporary download type", selection: $store.settings.downloadFormat) {
                    Text("OGG (recommended)").tag("ogg")
                    Text("MP3").tag("mp3")
                    Text("FLAC").tag("flac")
                }
                TextField("Optional Spotify app ID", text: $store.settings.apiClientId)
                Text("Only needed for some advanced Spotify features. Most people can leave this blank.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Spotify developer site") {
                    if let url = URL(string: "https://developer.spotify.com/dashboard") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section {
                Button("Save preferences") {
                    store.syncToZotifyConfig()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            store.syncAccountFromCredentials()
            if store.isLoggedIn {
                await store.refreshAccountProfile()
            }
        }
        .alert("Sign out of Spotify?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                store.clearCredentials()
            }
        } message: {
            Text("You’ll need to sign in again the next time you load playlists or download.")
        }
    }

    private var accountRow: some View {
        HStack(spacing: 16) {
            accountAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(store.accountTitle)
                    .font(.headline)
                Text(store.accountSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isLoggedIn {
                Button("Sign out…") { confirmSignOut = true }
            } else if downloads.isSigningIn {
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for Spotify…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Open page again") {
                            downloads.reopenSignInPage()
                        }
                        .disabled(downloads.pendingAuthURL == nil)
                        Button("Cancel") {
                            downloads.cancelSignIn()
                        }
                    }
                }
            } else {
                Button("Sign in with Spotify") {
                    Task { await signIn() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var accountAvatar: some View {
        ZStack {
            if let image = store.avatarImage, store.isLoggedIn {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
            } else if store.isLoggedIn, store.isRefreshingProfile {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 40, height: 40)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
                    .overlay(Circle().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
            } else {
                Image(systemName: store.isLoggedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(store.isLoggedIn ? Color.accentColor : .secondary)
            }
        }
        .frame(width: 40, height: 40)
    }

    private func signIn() async {
        let ok = await downloads.signInWithSpotify(store: store)
        store.syncAccountFromCredentials()
        if ok {
            store.clearAvatar()
            await store.refreshAccountProfile()
            let items = await downloads.fetchPlaylists(store: store)
            if !items.isEmpty {
                store.replaceSpotifyPlaylists(items)
            }
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: store.settings.rootPath)
        panel.message = "Choose where downloaded music should be saved"
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.rootPath = url.path
            store.syncToZotifyConfig()
        }
    }
}
