import SwiftUI
import AppKit

struct LinkPreviewCard: View {
    let preview: LinkPreview
    var downloadTitle: String = "Download"
    var isDownloading: Bool = false
    var canDownload: Bool = true
    var onDownload: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: kindIcon)
                .font(.system(size: 28))
                .foregroundStyle(preview.error == nil ? Color.secondary : Color.red.opacity(0.85))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 8) {
            Text(preview.error == nil ? preview.name : "Not found")
                .font(.headline)
                .lineLimit(2)
                .accessibilityIdentifier("preview.title")

            if let err = preview.error {
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("preview.error")
            } else {
                HStack(spacing: 8) {
                    Text(kindLabel)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))

                    Text(preview.tracksLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("preview.tracks")

                    if !preview.detail.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(preview.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let onDownload {
                    HStack(spacing: 10) {
                        Button(action: onDownload) {
                            Label(
                                isDownloading ? "Add to queue" : downloadTitle,
                                systemImage: isDownloading ? "plus.circle.fill" : "arrow.down.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canDownload)
                        .accessibilityIdentifier("preview.download")

                            Text(preview.matchLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Label(preview.matchLabel, systemImage: preview.statusSystemImage)
                            .font(.subheadline)
                            .foregroundStyle(statusColor)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(preview.error == nil ? statusColor.opacity(0.35) : Color.red.opacity(0.45), lineWidth: 1)
        )
    }

    private var kindIcon: String {
        if preview.error != nil { return "exclamationmark.triangle.fill" }
        switch preview.kind {
        case "album": return "square.stack"
        case "track": return "music.note"
        default: return "music.note.list"
        }
    }

    private var kindLabel: String {
        switch preview.kind {
        case "album": return "Album"
        case "track": return "Song"
        case "playlist": return "Playlist"
        default: return "Link"
        }
    }

    private var statusColor: Color {
        switch preview.status {
        case .fullyDownloaded: return .green
        case .partiallyDownloaded: return .orange
        case .noneDownloaded: return .accentColor
        case .unknown: return .secondary
        }
    }
}
