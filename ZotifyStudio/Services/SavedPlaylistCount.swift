import Foundation

enum SavedPlaylistCount {
    static func preferred(current: Int, learned: Int) -> Int {
        if learned > current { return learned }
        return current
    }
}
