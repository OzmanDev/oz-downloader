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

enum DownloadFinish {
    static func mayStopEarly(trackListReady: Bool, rows: [TrackRowState]) -> Bool {
        trackListReady && !rows.isEmpty && rows.allSatisfy { $0 == .finished }
    }

    static func mayMarkPlaylistDone(rows: [TrackRowState]) -> Bool {
        rows.isEmpty || rows.allSatisfy { $0 == .finished }
    }
}
