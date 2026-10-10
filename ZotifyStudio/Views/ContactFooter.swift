import SwiftUI
import AppKit

struct ContactFooter: View {
    @EnvironmentObject private var downloads: DownloadService
    @State private var pulseStart = Date()
    @State private var pulsing = false

    private let email = "mailosman.dev@gmail.com"
    private let instagramURL = URL(string: "https://www.instagram.com/oz.suliman/")!
    private let portfolioURL = URL(string: "https://osmandev.me/")!
    private let djPortfolioURL = URL(string: "https://osmandev.me/dj")!

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !pulsing)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(pulseStart)
            let highlight = FooterLinkPulse.scale(elapsed: elapsed)
            HStack(spacing: 16) {
                Text("Oz Downloader v" + WhatsNew.version + " · made with \u{2764}\u{FE0F} by Oz")
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

                footerLink(title: "@oz.suliman", systemImage: "camera", url: instagramURL, help: "instagram.com/oz.suliman", scale: highlight)
                footerLink(title: "Portfolio", systemImage: "globe", url: portfolioURL, help: "osmandev.me", scale: highlight)
                footerLink(title: "DJ", systemImage: "music.note", url: djPortfolioURL, help: "osmandev.me/dj", scale: highlight)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear {
            pulseStart = Date()
            pulsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + FooterLinkPulse.duration) {
                pulsing = false
            }
        }
    }

    private func footerLink(title: String, systemImage: String, url: URL, help: String, scale: Double) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .scaleEffect(scale)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
