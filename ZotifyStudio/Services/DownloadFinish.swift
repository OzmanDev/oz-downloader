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

enum DownloadFinish {
    static func mayStopEarly(trackListReady: Bool, rows: [TrackRowState]) -> Bool {
        trackListReady && !rows.isEmpty && rows.allSatisfy { $0 == .finished }
    }

    static func mayMarkPlaylistDone(rows: [TrackRowState]) -> Bool {
        rows.isEmpty || rows.allSatisfy { $0 == .finished }
    }
}
