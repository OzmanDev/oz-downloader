import Foundation

@main
enum TestPlaylistDebugLog {
    static func main() {
        var failures: [String] = []

        var songs: [PlaylistDebugSong] = (1...18).map { number in
            PlaylistDebugSong(number: number, outcome: "downloaded", detail: "")
        }
        songs.append(contentsOf: [20, 21, 22, 23].map { number in
            PlaylistDebugSong(number: number, outcome: "skipped", detail: "Already here")
        })
        songs.append(PlaylistDebugSong(number: 19, outcome: "failed", detail: "No audio stream"))

        let text = PlaylistDebugLog.text(version: "2.1.2", songs: songs)
        let expected = """
        v2.1.2
        downloaded 18
        skipped 4
        failed 1
        20 skipped Already here
        21 skipped Already here
        22 skipped Already here
        23 skipped Already here
        19 failed No audio stream
        """
        if text != expected {
            failures.append("1. playlist log expected counts and non-downloaded lines, got \(text)")
        }

        let privateSongs = [
            PlaylistDebugSong(number: 1, outcome: "failed", detail: "/Users/someone/Music/secret"),
            PlaylistDebugSong(number: 2, outcome: "failed", detail: "user@email.com"),
            PlaylistDebugSong(number: 3, outcome: "failed", detail: "https://accounts.spotify.com/token"),
        ]
        let privateText = PlaylistDebugLog.text(version: "2.1.2", songs: privateSongs)
        let privateExpected = """
        v2.1.2
        downloaded 0
        skipped 0
        failed 3
        1 failed
        2 failed
        3 failed
        """
        if privateText != privateExpected || privateText.contains("/Users") || privateText.contains("@") || privateText.contains("://") {
            failures.append("2. private details must be omitted, got \(privateText)")
        }

        let folder = URL(fileURLWithPath: "/tmp/playlist-folder")
        let logURL = PlaylistDebugLog.fileURL(playlistFolder: folder)
        if logURL.lastPathComponent != "debug.log" {
            failures.append("3. debug log file name expected debug.log, got \(logURL.lastPathComponent)")
        }

        let waitingText = PlaylistDebugLog.text(
            version: "2.1.2",
            songs: [PlaylistDebugSong(number: 7, outcome: "waiting", detail: "")]
        )
        let waitingLines = waitingText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if !waitingLines.contains("7 waiting") || waitingLines.contains(where: { $0.hasPrefix("waiting ") }) {
            failures.append("4. waiting song 7 expected \"7 waiting\" and no waiting count line, got \(waitingText)")
        }

        let detailText = PlaylistDebugLog.text(
            version: "2.1.2",
            songs: [
                PlaylistDebugSong(number: 1, outcome: "failed", detail: "No audio stream"),
                PlaylistDebugSong(number: 2, outcome: "failed", detail: "No audio stream /Users/me"),
            ]
        )
        let detailExpected = """
        v2.1.2
        downloaded 0
        skipped 0
        failed 2
        1 failed No audio stream
        2 failed
        """
        if detailText != detailExpected || detailText.contains("/Users/me") {
            failures.append("5. exact \"No audio stream\" kept and path suffix omitted, got \(detailText)")
        }

        let downloadedOnly = PlaylistDebugLog.text(
            version: "2.1.2",
            songs: [PlaylistDebugSong(number: 1, outcome: "downloaded", detail: "")]
        )
        let downloadedExpected = """
        v2.1.2
        downloaded 1
        skipped 0
        failed 0
        """
        let downloadedLines = downloadedOnly.split(separator: "\n", omittingEmptySubsequences: false)
        if downloadedOnly != downloadedExpected || downloadedLines.count != 4 {
            failures.append("6. downloaded-only playlist expected exactly four lines, got \(downloadedOnly)")
        }

        if failures.isEmpty {
            return
        }
        for failure in failures {
            print(failure)
        }
        exit(1)
    }
}
