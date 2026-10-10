import Foundation

enum WhatsNew {
    static let version = "2.3.0"
    static let title = "What's new in v2.3.0"
    static let lines = [
        "Refetch names and tags on playlists you already saved.",
        "Progress shows each song as it waits, downloads, skips, or finishes.",
        "Convert writes cleaner titles, lyrics, and tags.",
        "The layout for Get Music and your playlists is clearer.",
        "Each playlist saves a small debug log. It keeps only the minimum needed to investigate, leaves private data out, and is never shared unless you choose to send it.",
    ]
    static let continueTitle = "Continue"

    static func shouldPresent(lastSeenVersion: String?) -> Bool {
        let seen = lastSeenVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        if seen == version { return false }
        return true
    }
}

enum WhatsNewMemory {
    private static let key = "whatsNew.lastSeenVersion"

    static func lastSeen(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key)
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(WhatsNew.version, forKey: key)
    }
}
