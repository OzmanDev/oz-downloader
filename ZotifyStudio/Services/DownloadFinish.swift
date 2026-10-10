enum TrackRowState {
    case waiting
    case inProgress
    case finished
    case failed
}

enum DownloadQueue {
    /// The playlist that started the job stays first. A later download is appended, and the same link is not added twice.
    static func mergedStartURLs(started: [String], existing: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        func add(_ raw: String) {
            let key = normalize(raw)
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            result.append(raw)
        }
        for url in started { add(url) }
        for url in existing { add(url) }
        return result
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s.lowercased()
    }
}

struct ClassifiedSongLine: CustomStringConvertible {
    enum Kind {
        case skipped
        case failed
    }

    var kind: Kind
    var label: String
    var quotedName: String?
    var alreadySaved: Bool

    var description: String {
        "kind=\(kind) label=\(label) quotedName=\(quotedName ?? "nil") alreadySaved=\(alreadySaved)"
    }
}

enum DownloadLineOutcome {
    static func classify(_ line: String) -> ClassifiedSongLine? {
        let upper = line.uppercased()
        if upper.contains("FAILED TO GET CONTENT STREAM") {
            return ClassifiedSongLine(
                kind: .failed,
                label: "No audio stream",
                quotedName: nil,
                alreadySaved: false
            )
        }
        if upper.contains("IS UNAVAILABLE") {
            return ClassifiedSongLine(
                kind: .failed,
                label: "Unavailable",
                quotedName: firstQuoted(line),
                alreadySaved: false
            )
        }
        if upper.contains("IS A LOCAL FILE") {
            return ClassifiedSongLine(
                kind: .failed,
                label: "Local file",
                quotedName: firstQuoted(line),
                alreadySaved: false
            )
        }
        if upper.contains("FILE ALREADY EXISTS") {
            return ClassifiedSongLine(
                kind: .skipped,
                label: "Already here",
                quotedName: firstQuoted(line),
                alreadySaved: true
            )
        }
        if upper.contains("DOWNLOADED PREVIOUSLY") {
            return ClassifiedSongLine(
                kind: .skipped,
                label: "Downloaded previously",
                quotedName: firstQuoted(line),
                alreadySaved: true
            )
        }
        if upper.contains("ALREADY DOWNLOADED THIS SESSION") {
            return ClassifiedSongLine(
                kind: .skipped,
                label: "Already downloaded",
                quotedName: firstQuoted(line),
                alreadySaved: true
            )
        }
        if upper.contains("MATCHES REGEX FILTER") {
            return ClassifiedSongLine(
                kind: .skipped,
                label: "Filtered",
                quotedName: nil,
                alreadySaved: false
            )
        }
        return nil
    }

    private static func firstQuoted(_ line: String) -> String? {
        guard let open = line.firstIndex(of: "\""),
              let close = line[line.index(after: open)...].firstIndex(of: "\"") else { return nil }
        return String(line[line.index(after: open)..<close])
    }
}

enum SongBoardStatus {
    case waiting
    case inProgress
    case skipped
    case failed
    case downloaded
}

enum ProgressBoard {
    enum Column {
        case waiting
        case inProgress
        case skipped
        case failed
        case downloaded
    }

    static func summary(skipped: Int, failed: Int, left: Int) -> String {
        if failed > 0 {
            return "\(skipped) skipped · \(failed) failed · \(left) left"
        }
        return "\(skipped) skipped · \(left) left"
    }

    static func rowLabel(status: SongBoardStatus, reasonLabel: String, skipReason: String) -> String {
        switch status {
        case .waiting, .inProgress, .downloaded:
            return ""
        case .skipped, .failed:
            if !reasonLabel.isEmpty { return reasonLabel }
            if status == .skipped && skipReason == "alreadySaved" { return "Already here" }
            if skipReason == "duplicate" { return "Duplicate" }
            if skipReason == "cancelled" { return "Cancelled" }
            if status == .skipped { return "Skipped" }
            return "Failed"
        }
    }

    static func column(for status: SongBoardStatus) -> Column {
        switch status {
        case .failed:
            return .failed
        case .waiting:
            return .waiting
        case .skipped:
            return .skipped
        case .downloaded:
            return .downloaded
        case .inProgress:
            return .inProgress
        }
    }
}

enum FinishBanner {
    /// nil when nothing failed. Otherwise one line from the failure list.
    static func failureLine(count: Int, succeeded: Int = 0, pick: Int = 0) -> String? {
        FinishLines.withFailures(failed: count, succeeded: succeeded, pick: pick)
    }
}

enum FinishLines {
    static let catalogSize = 20

    static func slot(_ pick: Int) -> Int {
        let wrapped = pick % catalogSize
        return wrapped >= 0 ? wrapped : wrapped + catalogSize
    }

    static func randomPick() -> Int {
        Int.random(in: 0..<catalogSize)
    }

    static func allDone(pick: Int) -> String {
        switch slot(pick) {
        case 0: return "Oz got the job done as always 🎧✨"
        case 1: return "That's a wrap — the songs are in 🎵🔥"
        case 2: return "Playlist conquered. Headphones on 🎧🎉"
        case 3: return "Oz didn't miss. It's all here 💪🎶"
        case 4: return "Done and dusted. Go press play ▶️✨"
        case 5: return "The queue bowed out. You won 🏆🎵"
        case 6: return "Every track landed. Oz approves 👌🔥"
        case 7: return "Fresh files, zero drama 😎🎶"
        case 8: return "Whole playlist. Chef's kiss 👨‍🍳💋"
        case 9: return "Oz clocked out. The music didn't 🌙🎧"
        case 10: return "All saved. The speakers are jealous 🔊💚"
        case 11: return "Mission complete. Dance break authorized 💃🎉"
        case 12: return "Nothing left but vibes ✨🎶"
        case 13: return "Oz signed off. You can listen 📝🎧"
        case 14: return "Full playlist, full send 🚀🎵"
        case 15: return "The files showed up like they were invited 🎟️🔥"
        case 16: return "Clean finish. Oz is smiling 😁🎧"
        case 17: return "That's all of them. Legendary 👑🎶"
        case 18: return "Tagged, saved, and ready to blast 🏷️🔥"
        default: return "Close this and open the music 🚪🎵"
        }
    }

    /// nil when failed is below 1, so an all-done run never gets a failure line.
    static func withFailures(failed: Int, succeeded: Int, pick: Int) -> String? {
        guard failed >= 1 else { return nil }
        let f = "\(failed)"
        let s = "\(succeeded)"
        let fw = failed == 1 ? "failure" : "failures"
        switch slot(pick) {
        case 0: return "Oz got \(f) \(fw), but look at the good side \(s) succeeded 😅👏🏾"
        case 1: return "\(f) \(fw) crashed the party. \(s) succeeded anyway 🎉😅"
        case 2: return "Almost perfect. \(f) \(fw), and \(s) succeeded 💪🎶"
        case 3: return "Oz salvaged the night: \(s) succeeded, \(f) \(fw) 🔁😅"
        case 4: return "\(s) succeeded. The other \(f) \(fw) can try again 🎵🔄"
        case 5: return "Not a shutout. \(s) succeeded, \(f) \(fw) sat this one out 🪑😅"
        case 6: return "Oz counted \(s) succeeded and \(f) \(fw) 📊🔥"
        case 7: return "The good pile is \(s) succeeded. The oops pile is \(f) \(fw) 😅🎧"
        case 8: return "\(f) \(fw) slipped. \(s) succeeded and they're ready 🎶✨"
        case 9: return "Partial victory dance: \(s) succeeded, \(f) \(fw) 💃😅"
        case 10: return "Oz got most of it. \(s) succeeded, \(f) \(fw) 🏆😅"
        case 11: return "\(s) succeeded like champs. \(f) \(fw) need a rematch 🥊🎵"
        case 12: return "Look at \(s) succeeded before you frown at \(f) \(fw) 👀💚"
        case 13: return "The folder is richer by \(s) succeeded. \(f) \(fw) stayed home 📁😅"
        case 14: return "\(f) \(fw), \(s) succeeded. Oz calls that a win with footnotes 📝🔥"
        case 15: return "Headphones are happy about \(s) succeeded. \(f) \(fw) can wait 🎧😅"
        case 16: return "\(s) succeeded. Oz side-eyed the \(f) \(fw) 👀🎶"
        case 17: return "Good news first: \(s) succeeded. Then \(f) \(fw) 😅✨"
        case 18: return "\(f) \(fw) didn't make the album. \(s) succeeded 💿🔥"
        default: return "Oz wrapped it: \(s) succeeded, \(f) \(fw) 🎁😅"
        }
    }

    static func alreadyHere(pick: Int) -> String {
        switch slot(pick) {
        case 0: return "Oz checked. These were already here 😎🎵"
        case 1: return "Nothing new to fetch. Already here 📚✨"
        case 2: return "Already here, every last one. Oz is impressed 🏆🎶"
        case 3: return "The folder called first. Already here 📁🔥"
        case 4: return "Zero downloads. Already here, and that's a flex 💪🎧"
        case 5: return "Oz didn't re-download. Already here ✋🎵"
        case 6: return "You beat the queue. Already here 🏁✨"
        case 7: return "Already here. The hard drive salutes you 🫡🎶"
        case 8: return "No fresh files. Already here, party as planned 🎉🎧"
        case 9: return "Oz peeked and nodded. Already here 👀✅"
        case 10: return "Saved you the wait. Already here ⏱️🔥"
        case 11: return "Already here. Go listen to what you own 🎧💚"
        case 12: return "The playlist was a rerun. Already here 🔁😂"
        case 13: return "Oz found duplicates of joy. Already here 😄🎵"
        case 14: return "Nothing to fetch. Already here 🚫📥"
        case 15: return "Your past self did the work. Already here 🕰️✨"
        case 16: return "Already here. Oz refuses to download twice 🙅🎶"
        case 17: return "Library check complete. Already here 📋🔥"
        case 18: return "Already here. That's efficiency, baby ⚡🎧"
        default: return "Oz looked, shrugged, smiled. Already here 🤷😁"
        }
    }

    static func mixed(newCount: Int, alreadyHere: Int, pick: Int) -> String {
        let n = "\(newCount)"
        let a = "\(alreadyHere)"
        switch slot(pick) {
        case 0: return "Oz brought \(n) new. \(a) already here 🎵✨"
        case 1: return "\(n) new just landed. \(a) already here 🛬🔥"
        case 2: return "Fresh batch: \(n) new, and \(a) already here 😎🎶"
        case 3: return "Oz added \(n) new. \(a) already here ➕🎧"
        case 4: return "\(n) new for the collection. \(a) already here 📚✨"
        case 5: return "A little sparkle (\(n) new) and \(a) already here 🎉🎵"
        case 6: return "\(n) new files clocked in. \(a) already here ⏰🔥"
        case 7: return "Oz mixed it: \(n) new, \(a) already here 🎛️🎶"
        case 8: return "\(n) new to press play on. \(a) already here ▶️💚"
        case 9: return "The folder grew by \(n) new. \(a) already here 📁✨"
        case 10: return "\(n) new, \(a) already here. Balanced, like a playlist ⚖️🔥"
        case 11: return "Oz delivered \(n) new and recognized \(a) already here 👀🎵"
        case 12: return "\(n) new arrivals. \(a) already here, unbothered 😎🎧"
        case 13: return "\(n) new songs joined. \(a) already here 🎤✨"
        case 14: return "Count it: \(n) new, \(a) already here 🔢🔥"
        case 15: return "\(n) new to brag about. \(a) already here 🗣️🎶"
        case 16: return "Oz saved \(n) new. \(a) already here didn't need saving 💾😅"
        case 17: return "\(n) new in the bag. \(a) already here 👜✨"
        case 18: return "The fun part is \(n) new. \(a) already here 🎉🎧"
        default: return "\(n) new, \(a) already here. Oz calls that a solid haul 🧺🔥"
        }
    }

    static func fresh(newCount: Int, pick: Int) -> String {
        let n = "\(newCount)"
        switch slot(pick) {
        case 0: return "Oz brought \(n) new 🎵🔥"
        case 1: return "\(n) new, hot out of the queue 🔥🎧"
        case 2: return "Fresh drop: \(n) new ✨🎶"
        case 3: return "\(n) new just moved in 🏠🎉"
        case 4: return "Oz counted \(n) new and grinned 😁🎵"
        case 5: return "\(n) new for the speakers 🔊💚"
        case 6: return "That's \(n) new. Press play ▶️✨"
        case 7: return "\(n) new files, zero leftovers 😎🎶"
        case 8: return "The folder got \(n) new 📁🔥"
        case 9: return "Oz delivered \(n) new, as promised 📦🎧"
        case 10: return "\(n) new and ready to blast 🚀🎵"
        case 11: return "Brand-new energy: \(n) new ⚡✨"
        case 12: return "\(n) new joined the library 📚🔥"
        case 13: return "All \(n) new. No reruns 🙅🎶"
        case 14: return "Oz stacked \(n) new 📚🎧"
        case 15: return "\(n) new waiting in Downloads ⏳✨"
        case 16: return "Clean haul: \(n) new 🧹🔥"
        case 17: return "\(n) new, tagged and tidy 🏷️🎵"
        case 18: return "The queue turned into \(n) new 🎉🎧"
        default: return "\(n) new. Oz is done showing off 👑✨"
        }
    }
}

enum DownloadFinish {
    static func mayStopEarly(trackListReady: Bool, rows: [TrackRowState]) -> Bool {
        trackListReady && !rows.isEmpty && rows.allSatisfy { $0 == .finished }
    }

    static func mayMarkPlaylistDone(rows: [TrackRowState]) -> Bool {
        rows.isEmpty || rows.allSatisfy { $0 == .finished }
    }
}
