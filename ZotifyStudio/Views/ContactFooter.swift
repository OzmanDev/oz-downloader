import SwiftUI
import AppKit

struct ContactFooter: View {
    @EnvironmentObject private var downloads: DownloadService

    private let email = "mailosman.dev@gmail.com"
    private let instagramURL = URL(string: "https://www.instagram.com/oz.suliman/")!

    var body: some View {
        HStack(spacing: 16) {
            Text("Oz Downloader v0.0.1 · made with \u{2764}\u{FE0F} by Oz")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(email, forType: .string)
                downloads.showToast("Email copied")
            } label: {
                Label(email, systemImage: "envelope")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy email to clipboard")
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            Button {
                NSWorkspace.shared.open(instagramURL)
            } label: {
                Label("@oz.suliman", systemImage: "camera")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("instagram.com/oz.suliman")
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
