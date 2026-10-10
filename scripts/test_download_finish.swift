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

        let noAudio = DownloadLineOutcome.classify("ERROR:  SKIPPING TRACK - FAILED TO GET CONTENT STREAM   ###")
        if noAudio?.kind != .failed
            || noAudio?.label != "No audio stream"
            || noAudio?.alreadySaved != false
            || noAudio?.quotedName != nil {
            failures.append("19. FAILED TO GET CONTENT STREAM is failed, label No audio stream, alreadySaved false, quotedName nil, got \(String(describing: noAudio))")
        }

        let unavailable = DownloadLineOutcome.classify("SKIPPING:  \"Nova Song\" (TRACK IS UNAVAILABLE)   ###")
        if unavailable?.kind != .failed
            || unavailable?.label != "Unavailable"
            || unavailable?.alreadySaved != false {
            failures.append("20. IS UNAVAILABLE is failed with label Unavailable, got \(String(describing: unavailable))")
        }
        if unavailable?.quotedName != "Nova Song" {
            failures.append("46. IS UNAVAILABLE keeps the quoted song name Nova Song, got \(String(describing: unavailable?.quotedName))")
        }

        let localFile = DownloadLineOutcome.classify("SKIPPING:  \"Nova Song\" (TRACK IS A LOCAL FILE)   ###")
        if localFile?.kind != .failed
            || localFile?.label != "Local file"
            || localFile?.alreadySaved != false {
            failures.append("21. IS A LOCAL FILE is failed with label Local file, got \(String(describing: localFile))")
        }
        if localFile?.quotedName != "Nova Song" {
            failures.append("47. IS A LOCAL FILE keeps the quoted song name Nova Song, got \(String(describing: localFile?.quotedName))")
        }

        let alreadyHere = DownloadLineOutcome.classify("SKIPPING:  \"Dj House/19_Some Song.ogg\" (FILE ALREADY EXISTS)   ###")
        if alreadyHere?.kind != .skipped
            || alreadyHere?.label != "Already here"
            || alreadyHere?.alreadySaved != true
            || alreadyHere?.quotedName != "Dj House/19_Some Song.ogg" {
            failures.append("22. FILE ALREADY EXISTS is skipped Already here with the quoted filename, got \(String(describing: alreadyHere))")
        }

        let downloadedPreviously = DownloadLineOutcome.classify("SKIPPING:  \"Some Song\" (TRACK DOWNLOADED PREVIOUSLY)   ###")
        if downloadedPreviously?.kind != .skipped
            || downloadedPreviously?.label != "Downloaded previously"
            || downloadedPreviously?.alreadySaved != true {
            failures.append("23. DOWNLOADED PREVIOUSLY is skipped Downloaded previously, alreadySaved true, got \(String(describing: downloadedPreviously))")
        }

        let alreadyThisSession = DownloadLineOutcome.classify("SKIPPING:  \"Some Song\" (TRACK ALREADY DOWNLOADED THIS SESSION)   ###")
        if alreadyThisSession?.kind != .skipped
            || alreadyThisSession?.label != "Already downloaded"
            || alreadyThisSession?.alreadySaved != true {
            failures.append("24. ALREADY DOWNLOADED THIS SESSION is skipped Already downloaded, alreadySaved true, got \(String(describing: alreadyThisSession))")
        }

        let filtered = DownloadLineOutcome.classify("SKIPPING:  TRACK MATCHES REGEX FILTER   ###")
        if filtered?.kind != .skipped
            || filtered?.label != "Filtered"
            || filtered?.alreadySaved != false {
            failures.append("25. MATCHES REGEX FILTER is skipped Filtered, alreadySaved false, got \(String(describing: filtered))")
        }

        let lyricsSkip = DownloadLineOutcome.classify("SKIPPING:  LYRICS FOR \"Some Song\" (not found)   ###")
        if lyricsSkip != nil {
            failures.append("26. a lyrics skip line does not classify a song, got \(String(describing: lyricsSkip))")
        }

        let onlySkipping = DownloadLineOutcome.classify("SKIPPING:  \"Some Song\"   ###")
        if onlySkipping != nil {
            failures.append("27. a line that only skips does not classify a song, got \(String(describing: onlySkipping))")
        }

        let failedColumn = ProgressBoard.column(for: .failed)
        if failedColumn != .failed {
            failures.append("28. a failed song is in the failed column, got \(failedColumn)")
        }

        let waitingColumn = ProgressBoard.column(for: .waiting)
        if waitingColumn != .waiting {
            failures.append("29. a waiting song is in the waiting column, got \(waitingColumn)")
        }

        let skippedColumn = ProgressBoard.column(for: .skipped)
        if skippedColumn != .skipped {
            failures.append("30. a skipped song is in the skipped column, got \(skippedColumn)")
        }

        let downloadedColumn = ProgressBoard.column(for: .downloaded)
        if downloadedColumn != .downloaded {
            failures.append("31. a downloaded song is in the downloaded column, got \(downloadedColumn)")
        }

        let inProgressColumn = ProgressBoard.column(for: .inProgress)
        if inProgressColumn != .inProgress {
            failures.append("32. an in-progress song is in the in-progress column, got \(inProgressColumn)")
        }

        let previousLabel = ProgressBoard.rowLabel(
            status: .skipped,
            reasonLabel: "Downloaded previously",
            skipReason: ""
        )
        if previousLabel != "Downloaded previously" {
            failures.append("33. a skipped row shows its reason label, got \(previousLabel)")
        }

        let noStreamLabel = ProgressBoard.rowLabel(
            status: .failed,
            reasonLabel: "No audio stream",
            skipReason: ""
        )
        if noStreamLabel != "No audio stream" {
            failures.append("34. a failed row shows its reason label, got \(noStreamLabel)")
        }

        let alreadyHereLabel = ProgressBoard.rowLabel(
            status: .skipped,
            reasonLabel: "",
            skipReason: "alreadySaved"
        )
        if alreadyHereLabel != "Already here" {
            failures.append("35. a skipped already-saved row with no reason label shows Already here, got \(alreadyHereLabel)")
        }

        let duplicateLabel = ProgressBoard.rowLabel(
            status: .skipped,
            reasonLabel: "",
            skipReason: "duplicate"
        )
        if duplicateLabel != "Duplicate" {
            failures.append("36. a duplicate skip shows Duplicate, got \(duplicateLabel)")
        }

        let cancelledLabel = ProgressBoard.rowLabel(
            status: .skipped,
            reasonLabel: "",
            skipReason: "cancelled"
        )
        if cancelledLabel != "Cancelled" {
            failures.append("37. a cancelled skip shows Cancelled, got \(cancelledLabel)")
        }

        let plainSkipped = ProgressBoard.rowLabel(status: .skipped, reasonLabel: "", skipReason: "")
        if plainSkipped != "Skipped" {
            failures.append("38. a skipped row with no reason shows Skipped, got \(plainSkipped)")
        }

        let plainFailed = ProgressBoard.rowLabel(status: .failed, reasonLabel: "", skipReason: "")
        if plainFailed != "Failed" {
            failures.append("39. a failed row with no reason shows Failed, got \(plainFailed)")
        }

        let waitingLabel = ProgressBoard.rowLabel(status: .waiting, reasonLabel: "", skipReason: "")
        if waitingLabel != "" {
            failures.append("40. a waiting row has no status label from this function, got \(waitingLabel)")
        }

        let inProgressLabel = ProgressBoard.rowLabel(status: .inProgress, reasonLabel: "50%", skipReason: "")
        if inProgressLabel != "" {
            failures.append("41. an in-progress row has no status label from this function, got \(inProgressLabel)")
        }

        let downloadedLabel = ProgressBoard.rowLabel(status: .downloaded, reasonLabel: "Downloaded", skipReason: "")
        if downloadedLabel != "" {
            failures.append("42. a downloaded row has no status label from this function, got \(downloadedLabel)")
        }

        let waitingWithReason = ProgressBoard.rowLabel(status: .waiting, reasonLabel: "No audio stream", skipReason: "")
        if waitingWithReason != "" {
            failures.append("43. a waiting row ignores a reason label, got \(waitingWithReason)")
        }

        let withFailed = ProgressBoard.summary(skipped: 2, failed: 1, left: 3)
        if withFailed != "2 skipped · 1 failed · 3 left" {
            failures.append("44. a summary with failures counts failed songs, got \(withFailed)")
        }

        let noFailed = ProgressBoard.summary(skipped: 4, failed: 0, left: 5)
        if noFailed != "4 skipped · 5 left" {
            failures.append("45. a summary with no failures does not mention failed, got \(noFailed)")
        }

        let lowercaseNoAudio = DownloadLineOutcome.classify("error: skipping track - failed to get content stream")
        if lowercaseNoAudio?.kind != .failed
            || lowercaseNoAudio?.label != "No audio stream"
            || lowercaseNoAudio?.quotedName != nil {
            failures.append("48. case 1 lowercase failed to get content stream expected failed, label \"No audio stream\", quotedName nil, got \(String(describing: lowercaseNoAudio))")
        }

        let sessionSkip = DownloadLineOutcome.classify("SKIPPING:  \"Some Song\" (TRACK ALREADY DOWNLOADED THIS SESSION)   ###")
        if sessionSkip?.kind != .skipped || sessionSkip?.label != "Already downloaded" {
            failures.append("49. case 2 ALREADY DOWNLOADED THIS SESSION expected skipped, label \"Already downloaded\", got \(String(describing: sessionSkip))")
        }
        if sessionSkip?.label == "Downloaded previously" {
            failures.append("49. case 2 ALREADY DOWNLOADED THIS SESSION label is \"Downloaded previously\"")
        }

        let trackUnavailable = DownloadLineOutcome.classify("SKIPPING:  \"Track Name\" (TRACK IS UNAVAILABLE)   ###")
        if trackUnavailable?.kind != .failed
            || trackUnavailable?.label != "Unavailable"
            || trackUnavailable?.quotedName != "Track Name" {
            failures.append("50. case 3 TRACK IS UNAVAILABLE expected failed, label \"Unavailable\", quotedName \"Track Name\", got \(String(describing: trackUnavailable))")
        }

        let lyricsMissing = DownloadLineOutcome.classify("SKIPPING:  LYRICS FOR \"Track Name\" (missing)   ###")
        if lyricsMissing != nil {
            failures.append("51. case 4 lyrics skip (missing) expected nil, got \(String(describing: lyricsMissing))")
        }

        let emptyLine = DownloadLineOutcome.classify("")
        if emptyLine != nil {
            failures.append("52. case 5 empty string expected nil, got \(String(describing: emptyLine))")
        }

        let zeroSkippedOneFailed = ProgressBoard.summary(skipped: 0, failed: 1, left: 16)
        if zeroSkippedOneFailed != "0 skipped · 1 failed · 16 left" {
            failures.append("53. case 6 summary(skipped: 0, failed: 1, left: 16) expected \"0 skipped · 1 failed · 16 left\", got \(zeroSkippedOneFailed)")
        }

        let oneSkippedNoneFailed = ProgressBoard.summary(skipped: 1, failed: 0, left: 16)
        if oneSkippedNoneFailed != "1 skipped · 16 left" {
            failures.append("54. case 7 summary(skipped: 1, failed: 0, left: 16) expected \"1 skipped · 16 left\", got \(oneSkippedNoneFailed)")
        }

        let failedColumnNotInProgress = ProgressBoard.column(for: .failed)
        if failedColumnNotInProgress != .failed {
            failures.append("55. case 8 column(for: .failed) expected failed, got \(failedColumnNotInProgress)")
        }
        if failedColumnNotInProgress == .inProgress {
            failures.append("55. case 8 column(for: .failed) is inProgress")
        }

        let reasonLabelWins = ProgressBoard.rowLabel(
            status: .skipped,
            reasonLabel: "Local file",
            skipReason: "alreadySaved"
        )
        if reasonLabelWins != "Local file" {
            failures.append("56. case 9 skipped row with reason label \"Local file\" and skipReason alreadySaved expected \"Local file\", got \(reasonLabelWins)")
        }

        let oneFailure = FinishLines.withFailures(failed: 1, succeeded: 18, pick: 0)
        if oneFailure != "Oz got 1 failure, but look at the good side 18 succeeded 😅👏🏾" {
            failures.append("57. one failed song: failure line expected the first failure message, got \(String(describing: oneFailure))")
        }

        let twoFailures = FinishLines.withFailures(failed: 2, succeeded: 4, pick: 0)
        if twoFailures != "Oz got 2 failures, but look at the good side 4 succeeded 😅👏🏾" {
            failures.append("58. two failed songs: failure line expected plural wording, got \(String(describing: twoFailures))")
        }

        let noFailures = FinishLines.withFailures(failed: 0, succeeded: 9, pick: 0)
        if noFailures != nil {
            failures.append("60. no failed songs: failure line expected nil, got \(String(describing: noFailures))")
        }

        let negativeFailures = FinishLines.withFailures(failed: -1, succeeded: 3, pick: 4)
        if negativeFailures != nil {
            failures.append("61. a negative count: failure line expected nil, got \(String(describing: negativeFailures))")
        }

        var allDoneLines: [String] = []
        var failureLines: [String] = []
        var alreadyLines: [String] = []
        var mixedLines: [String] = []
        var freshLines: [String] = []
        for pick in 0..<FinishLines.catalogSize {
            allDoneLines.append(FinishLines.allDone(pick: pick))
            if let line = FinishLines.withFailures(failed: 3, succeeded: 11, pick: pick) {
                failureLines.append(line)
            }
            alreadyLines.append(FinishLines.alreadyHere(pick: pick))
            mixedLines.append(FinishLines.mixed(newCount: 2, alreadyHere: 5, pick: pick))
            freshLines.append(FinishLines.fresh(newCount: 7, pick: pick))
        }
        if Set(allDoneLines).count != 20 {
            failures.append("63. all-done list expected 20 different lines, got \(Set(allDoneLines).count)")
        }
        if failureLines.count != 20 || Set(failureLines).count != 20 {
            failures.append("64. failure list expected 20 different lines, got \(Set(failureLines).count)")
        }
        if Set(alreadyLines).count != 20 || Set(mixedLines).count != 20 || Set(freshLines).count != 20 {
            failures.append("65. the other finish lists expected 20 different lines each")
        }
        let allDoneSet = Set(allDoneLines)
        if failureLines.contains(where: { allDoneSet.contains($0) }) {
            failures.append("66. a failure line was taken from the all-done list")
        }
        if alreadyLines.contains(where: { allDoneSet.contains($0) || failureLines.contains($0) }) {
            failures.append("67. an already-here line was taken from another list")
        }
        if mixedLines.contains(where: { allDoneSet.contains($0) || failureLines.contains($0) || alreadyLines.contains($0) }) {
            failures.append("68. a mixed line was taken from another list")
        }
        if freshLines.contains(where: {
            allDoneSet.contains($0) || failureLines.contains($0) || alreadyLines.contains($0) || mixedLines.contains($0)
        }) {
            failures.append("69. a new-songs line was taken from another list")
        }
        if failureLines.contains(where: { !$0.contains("3") || !$0.contains("11") }) {
            failures.append("70. a failure line dropped the failed or succeeded count")
        }
        if mixedLines.contains(where: { !$0.contains("2") || !$0.contains("5") }) {
            failures.append("71. a mixed line dropped a count")
        }
        if FinishLines.allDone(pick: 20) != FinishLines.allDone(pick: 0) {
            failures.append("72. pick 20 should stay on the all-done list")
        }
        if FinishLines.withFailures(failed: 1, succeeded: 18, pick: 1) == oneFailure {
            failures.append("73. two failure picks should not be the same line")
        }

        let failedNotes = FailedSongNotes.list([
            FailedSongInput(name: "Kept", reasonLabel: "Already here", failed: false),
            FailedSongInput(name: "Missing", reasonLabel: "No audio stream", failed: true),
            FailedSongInput(name: "Quiet", reasonLabel: "  ", failed: true),
        ])
        if failedNotes.count != 2 {
            failures.append("74. what-failed list expected only the failed songs, got \(failedNotes.count)")
        }
        if failedNotes.first?.name != "Missing" || failedNotes.first?.reason != "No audio stream" {
            failures.append("74. first failed song expected Missing / No audio stream, got \(String(describing: failedNotes.first))")
        }
        if failedNotes.last?.reason != "Failed" {
            failures.append("75. a failed song with no reason expected \"Failed\", got \(String(describing: failedNotes.last?.reason))")
        }
        if FailedSongNotes.list([FailedSongInput(name: "Kept", reasonLabel: "Already here", failed: false)]).isEmpty == false {
            failures.append("76. a run with no failed songs should not list anything")
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
