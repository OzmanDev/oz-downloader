enum TrackRowState {
    case waiting
    case inProgress
    case finished
}

enum DownloadFinish {
    static func mayStopEarly(trackListReady: Bool, rows: [TrackRowState]) -> Bool {
        trackListReady && !rows.isEmpty && rows.allSatisfy { $0 == .finished }
    }

    static func mayMarkPlaylistDone(rows: [TrackRowState]) -> Bool {
        rows.isEmpty || rows.allSatisfy { $0 == .finished }
    }
}
