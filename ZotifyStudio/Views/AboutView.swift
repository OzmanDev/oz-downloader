import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Oz Downloader")
                        .font(.largeTitle.bold())
                    Text("Download your Spotify playlists to this Mac — simply.")
                        .foregroundStyle(.secondary)
                }

                tipCard(
                    title: "How to get started",
                    body: "1. Open Preferences and sign in with Spotify.\n2. Go to My Playlists and load your lists.\n3. Keep the ones you want, then download.\n\nOr paste a Spotify link on Get Music."
                )

                tipCard(
                    title: "Your privacy",
                    body: "Oz Downloader keeps its own Spotify login, settings, and download folder. It doesn’t share them with anyone."
                )

                tipCard(
                    title: "Need help?",
                    body: "Something not working? Contact me and I’ll help you out."
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Contact")
                        .font(.headline)
                    Link("mailosman.dev@gmail.com", destination: URL(string: "mailto:mailosman.dev@gmail.com")!)
                    Link("instagram.com/oz.suliman", destination: URL(string: "https://www.instagram.com/oz.suliman/")!)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

                Spacer(minLength: 0)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func tipCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
