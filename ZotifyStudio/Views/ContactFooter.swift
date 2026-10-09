import SwiftUI
import AppKit

struct ContactFooter: View {
    @EnvironmentObject private var downloads: DownloadService

    private let email = "mailosman.dev@gmail.com"
    private let instagramURL = URL(string: "https://www.instagram.com/oz.suliman/")!
    private let portfolioURL = URL(string: "https://osmandev.me/")!
    private let djPortfolioURL = URL(string: "https://osmandev.me/dj")!

    var body: some View {
        HStack(spacing: 16) {
            Text("Oz Downloader v2.1.0 · made with \u{2764}\u{FE0F} by Oz")
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

            footerLink(title: "@oz.suliman", systemImage: "camera", url: instagramURL, help: "instagram.com/oz.suliman")
            footerLink(title: "Portfolio", systemImage: "globe", url: portfolioURL, help: "osmandev.me")
            footerLink(title: "DJ", systemImage: "music.note", url: djPortfolioURL, help: "osmandev.me/dj")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func footerLink(title: String, systemImage: String, url: URL, help: String) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
