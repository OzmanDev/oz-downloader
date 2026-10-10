import Foundation

struct PlaylistDebugSong: Equatable {
    var number: Int
    var outcome: String
    var detail: String
}

enum PlaylistDebugLog {
    static let fileName = "debug.log"
    static let allowedDetails: Set<String> = [
        "Already here",
        "Downloaded previously",
        "Already downloaded",
        "Filtered",
        "Duplicate",
        "Cancelled",
        "Unavailable",
        "Local file",
        "No audio stream",
        "Failed",
        "Skipped",
    ]

    static func text(version: String, songs: [PlaylistDebugSong]) -> String {
        let downloaded = songs.filter { $0.outcome == "downloaded" }.count
        let skipped = songs.filter { $0.outcome == "skipped" }.count
        let failed = songs.filter { $0.outcome == "failed" }.count
        var lines = [
            "v\(version)",
            "downloaded \(downloaded)",
            "skipped \(skipped)",
            "failed \(failed)",
        ]
        for song in songs where song.outcome != "downloaded" {
            if allowedDetails.contains(song.detail) {
                lines.append("\(song.number) \(song.outcome) \(song.detail)")
            } else {
                lines.append("\(song.number) \(song.outcome)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func fileURL(playlistFolder: URL) -> URL {
        playlistFolder.appendingPathComponent(fileName)
    }
}
