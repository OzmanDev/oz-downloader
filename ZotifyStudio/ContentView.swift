import SwiftUI

private enum AppTab: Hashable, CaseIterable {
    case getMusic
    case playlists
    case preferences
    case help

    var title: String {
        switch self {
        case .getMusic: return "Get Music"
        case .playlists: return "My Playlists"
        case .preferences: return "Preferences"
        case .help: return "Help"
        }
    }

    var systemImage: String {
        switch self {
        case .getMusic: return "arrow.down.circle.fill"
        case .playlists: return "music.note.list"
        case .preferences: return "gearshape.fill"
        case .help: return "questionmark.circle.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var downloads: DownloadService
    @State private var selectedTab: AppTab = .getMusic

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                customTabBar
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Group {
                    switch selectedTab {
                    case .getMusic:
                        DownloadView()
                    case .playlists:
                        PlaylistsView()
                    case .preferences:
                        SettingsView()
                    case .help:
                        AboutView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ContactFooter()
            }

            if downloads.toastVisible, !downloads.toastMessage.isEmpty {
                toastBanner
                    .padding(.top, 52)
                    .zIndex(10)
            }
        }
        // Avoid animating toast in/out — it was blanking Get Music content on cancel/finish.
        .frame(minWidth: 980, minHeight: 680)
        .onChange(of: selectedTab) { tab in
            if tab == .getMusic {
                if downloads.tabBadge == .success || downloads.tabBadge == .failure {
                    downloads.clearTabBadge()
                }
            }
        }
        .onChange(of: downloads.requestShowGetMusic) { show in
            guard show else { return }
            selectedTab = .getMusic
            downloads.requestShowGetMusic = false
        }
        .onAppear {
            if selectedTab == .getMusic,
               downloads.tabBadge == .success || downloads.tabBadge == .failure {
                downloads.clearTabBadge()
            }
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                if tab == .getMusic, let color = badgeColor {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(badgeAccessibilityLabel)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.55))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tabAccessibilityId(tab))
    }

    private func tabAccessibilityId(_ tab: AppTab) -> String {
        switch tab {
        case .getMusic: return "tab.getMusic"
        case .playlists: return "tab.playlists"
        case .preferences: return "tab.preferences"
        case .help: return "tab.help"
        }
    }

    private var toastBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: toastIcon)
                .foregroundStyle(.tint)
            Text(downloads.toastMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var toastIcon: String {
        let msg = downloads.toastMessage.lowercased()
        if msg.contains("copied") { return "doc.on.doc.fill" }
        if msg.contains("failed") || msg.contains("error") || msg.contains("couldn't") || msg.contains("couldn’t") {
            return "exclamationmark.triangle.fill"
        }
        if msg.contains("saved") { return "checkmark.circle.fill" }
        if msg.contains("sign") { return "person.crop.circle.badge.checkmark" }
        return "arrow.down.circle.fill"
    }

    /// Dot is hidden on Get Music; shown on other tabs while a download state is active.
    private var badgeColor: Color? {
        guard selectedTab != .getMusic else { return nil }
        switch downloads.tabBadge {
        case .none: return nil
        case .inProgress: return .yellow
        case .success: return .green
        case .failure: return .red
        }
    }

    private var badgeAccessibilityLabel: String {
        switch downloads.tabBadge {
        case .none: return ""
        case .inProgress: return "Download in progress"
        case .success: return "Download finished"
        case .failure: return "Download failed"
        }
    }
}
