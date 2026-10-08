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

        if failures.isEmpty {
            return
        }
        for failure in failures {
            print(failure)
        }
        exit(1)
    }
}
