import SwiftUI

@main
struct ZotifyStudioApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var downloads = DownloadService()
    @StateObject private var previews = LinkPreviewService()

    var body: some Scene {
        WindowGroup("Oz Downloader") {
            ContentView()
                .environmentObject(store)
                .environmentObject(downloads)
                .environmentObject(previews)
                .task {
                    store.syncAccountFromCredentials()
                    if store.isLoggedIn {
                        await store.refreshAccountProfile()
                        // Refresh Spotify playlist cache on every launch (UI shows cache immediately).
                        let items = await downloads.fetchPlaylists(store: store)
                        if !items.isEmpty {
                            store.replaceSpotifyPlaylists(items)
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(downloads)
                .frame(width: 560, height: 520)
        }
    }
}
