import Foundation

@main
enum TestDownloadFinish {
    static func main() {
        var failures: [String] = []

        if DownloadFinish.mayStopEarly(trackListReady: false, rows: [.finished]) {
            failures.append("1. track list not ready, all rows finished: mayStopEarly should be false")
        }
        if DownloadFinish.mayStopEarly(trackListReady: true, rows: [.waiting]) {
            failures.append("2. track list ready, one waiting row: mayStopEarly should be false")
        }
        if !DownloadFinish.mayStopEarly(trackListReady: true, rows: [.finished, .finished]) {
            failures.append("3. track list ready, all finished: mayStopEarly should be true")
        }
        if DownloadFinish.mayStopEarly(trackListReady: true, rows: []) {
            failures.append("4. empty rows: mayStopEarly should be false")
        }
        if DownloadFinish.mayMarkPlaylistDone(rows: [.finished, .waiting]) {
            failures.append("5. any waiting row: mayMarkPlaylistDone should be false")
        }
        if !DownloadFinish.mayMarkPlaylistDone(rows: [.finished, .finished]) {
            failures.append("6. all finished: mayMarkPlaylistDone should be true")
        }
        let stopEarlyInProgress = DownloadFinish.mayStopEarly(trackListReady: true, rows: [.inProgress])
        if stopEarlyInProgress != false {
            failures.append("7. track list ready, one inProgress row: mayStopEarly expected false, got \(stopEarlyInProgress)")
        }
        let stopEarlyNotReadyWaiting = DownloadFinish.mayStopEarly(trackListReady: false, rows: [.waiting])
        if stopEarlyNotReadyWaiting != false {
            failures.append("8. track list not ready, one waiting row: mayStopEarly expected false, got \(stopEarlyNotReadyWaiting)")
        }
        let markDoneInProgress = DownloadFinish.mayMarkPlaylistDone(rows: [.inProgress])
        if markDoneInProgress != false {
            failures.append("9. one inProgress row: mayMarkPlaylistDone expected false, got \(markDoneInProgress)")
        }
        let markDoneEmpty = DownloadFinish.mayMarkPlaylistDone(rows: [])
        if markDoneEmpty != true {
            failures.append("10. empty rows: mayMarkPlaylistDone expected true, got \(markDoneEmpty)")
        }
        let stopEarlyWithFailed = DownloadFinish.mayStopEarly(
            trackListReady: true,
            rows: [.finished, .failed]
        )
        if stopEarlyWithFailed != false {
            failures.append("11. track list ready, a failed row among finished: mayStopEarly expected false, got \(stopEarlyWithFailed)")
        }
        let markDoneAllFailed = DownloadFinish.mayMarkPlaylistDone(rows: [.failed])
        if markDoneAllFailed != false {
            failures.append("12. every row failed: mayMarkPlaylistDone expected false, got \(markDoneAllFailed)")
        }
        let markDoneMixedFailed = DownloadFinish.mayMarkPlaylistDone(rows: [.finished, .failed])
        if markDoneMixedFailed != false {
            failures.append("13. a failed row among finished: mayMarkPlaylistDone expected false, got \(markDoneMixedFailed)")
        }
        let stopEarlyNotReadyFailed = DownloadFinish.mayStopEarly(trackListReady: false, rows: [.failed])
        if stopEarlyNotReadyFailed != false {
            failures.append("14. track list not ready, one failed row: mayStopEarly expected false, got \(stopEarlyNotReadyFailed)")
        }
        let markDoneWaitingFailed = DownloadFinish.mayMarkPlaylistDone(rows: [.waiting, .failed])
        if markDoneWaitingFailed != false {
            failures.append("15. waiting and failed rows: mayMarkPlaylistDone expected false, got \(markDoneWaitingFailed)")
        }
        let stopEarlyInProgressFailed = DownloadFinish.mayStopEarly(
            trackListReady: true,
            rows: [.inProgress, .failed]
        )
        if stopEarlyInProgressFailed != false {
            failures.append("16. track list ready, inProgress and failed rows: mayStopEarly expected false, got \(stopEarlyInProgressFailed)")
        }

        let queuedBehind = DownloadQueue.mergedStartURLs(
            started: ["https://open.spotify.com/playlist/first"],
            existing: [
                "https://open.spotify.com/playlist/first",
                "https://open.spotify.com/playlist/second",
            ]
        )
        if queuedBehind != [
            "https://open.spotify.com/playlist/first",
            "https://open.spotify.com/playlist/second",
        ] {
            failures.append("17. a second playlist is appended behind the one already started, got \(queuedBehind)")
        }
        let sameLink = DownloadQueue.mergedStartURLs(
            started: ["https://open.spotify.com/playlist/first"],
            existing: ["https://open.spotify.com/playlist/first?si=abc"]
        )
        if sameLink.count != 1 {
            failures.append("18. the same playlist link is not queued twice, got \(sameLink)")
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
