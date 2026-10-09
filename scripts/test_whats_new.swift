import Foundation

@main
enum TestWhatsNew {
    static func main() {
        var failures: [String] = []

        let freshInstall = WhatsNew.shouldPresent(lastSeenVersion: nil)
        if freshInstall != true {
            failures.append("1. nil last seen should present, got \(freshInstall)")
        }
        let alreadySeen = WhatsNew.shouldPresent(lastSeenVersion: "2.1.1")
        if alreadySeen != false {
            failures.append("2. last seen 2.1.1 should not present, got \(alreadySeen)")
        }
        let paddedSeen = WhatsNew.shouldPresent(lastSeenVersion: "  2.1.1\n")
        if paddedSeen != false {
            failures.append("3. last seen padded 2.1.1 should not present, got \(paddedSeen)")
        }
        let blankSeen = WhatsNew.shouldPresent(lastSeenVersion: " \n\t ")
        if blankSeen != true {
            failures.append("4. whitespace-only last seen should present, got \(blankSeen)")
        }
        let olderVersion = WhatsNew.shouldPresent(lastSeenVersion: "2.1.0")
        if olderVersion != true {
            failures.append("5. last seen 2.1.0 should present, got \(olderVersion)")
        }
        let emptySeen = WhatsNew.shouldPresent(lastSeenVersion: "")
        if emptySeen != true {
            failures.append("12. empty last seen should present, got \(emptySeen)")
        }
        let newerVersion = WhatsNew.shouldPresent(lastSeenVersion: "2.2.0")
        if newerVersion != true {
            failures.append("13. last seen 2.2.0 should present, got \(newerVersion)")
        }
        if WhatsNew.version != "2.1.1" {
            failures.append("6. version expected 2.1.1, got \(WhatsNew.version)")
        }
        if WhatsNew.title != "What's new in v2.1.1" {
            failures.append("7. title expected What's new in v2.1.1, got \(WhatsNew.title)")
        }
        let notes = [
            "Refetch names and tags on playlists you already saved.",
            "Progress shows each song as it waits, downloads, skips, or finishes.",
            "Convert writes cleaner titles, lyrics, and tags.",
            "The layout for Get Music and your playlists is clearer.",
        ]
        if WhatsNew.lines != notes {
            failures.append("8. lines expected the four 2.1.1 notes, got \(WhatsNew.lines)")
        }
        if WhatsNew.continueTitle != "Continue" {
            failures.append("9. continue title expected Continue, got \(WhatsNew.continueTitle)")
        }

        let suiteName = "com.oz.downloader.whats-new-tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let unseen = WhatsNewMemory.lastSeen(defaults: defaults)
        if unseen != nil {
            failures.append("10. fresh suite last seen expected nil, got \(unseen ?? "nil")")
        }
        WhatsNewMemory.markSeen(defaults: defaults)
        let remembered = WhatsNewMemory.lastSeen(defaults: defaults)
        if remembered != "2.1.1" {
            failures.append("11. continue should remember 2.1.1, got \(remembered ?? "nil")")
        }
        let afterContinue = WhatsNew.shouldPresent(lastSeenVersion: remembered)
        if afterContinue != false {
            failures.append("14. after markSeen should not present, got \(afterContinue)")
        }
        defaults.removePersistentDomain(forName: suiteName)

        if failures.isEmpty {
            return
        }
        for failure in failures {
            print(failure)
        }
        exit(1)
    }
}
