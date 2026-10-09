import Foundation

@main
enum TestSavedPlaylistCount {
    static func main() {
        var failures: [String] = []

        let longerList = SavedPlaylistCount.preferred(current: 92, learned: 105)
        if longerList != 105 {
            failures.append("1. learned 105 is longer than current 92: preferred expected 105, got \(longerList)")
        }
        let shorterList = SavedPlaylistCount.preferred(current: 105, learned: 92)
        if shorterList != 105 {
            failures.append("2. learned 92 is shorter than current 105: preferred expected 105, got \(shorterList)")
        }
        let learnedZero = SavedPlaylistCount.preferred(current: 105, learned: 0)
        if learnedZero != 105 {
            failures.append("3. learned 0 does not replace current 105: preferred expected 105, got \(learnedZero)")
        }
        let currentZero = SavedPlaylistCount.preferred(current: 0, learned: 4)
        if currentZero != 4 {
            failures.append("4. current 0 and learned 4: preferred expected 4, got \(currentZero)")
        }
        let equalCounts = SavedPlaylistCount.preferred(current: 105, learned: 105)
        if equalCounts != 105 {
            failures.append("5. learned 105 equals current 105: preferred expected 105, got \(equalCounts)")
        }
        let negativeLearned = SavedPlaylistCount.preferred(current: 10, learned: -1)
        if negativeLearned != 10 {
            failures.append("6. learned -1 is below current 10: preferred expected 10, got \(negativeLearned)")
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
