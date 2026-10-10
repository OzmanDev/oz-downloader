import Foundation

@main
enum TestOrbField {
    static func main() {
        var failures: [String] = []

        let field = OrbField.orbs(at: 0, width: 1000, height: 700)
        if field.count != 3 {
            failures.append("1. expected 3 orbs, got \(field.count)")
        }
        let hues = field.map(\.hue)
        if hues != ["blue", "violet", "teal"] {
            failures.append("1. hues expected blue, violet, teal, got \(hues)")
        }

        let atZero = OrbField.orbs(at: 0, width: 1000, height: 700)
        let atTwelve = OrbField.orbs(at: 12, width: 1000, height: 700)
        if atZero == atTwelve {
            failures.append("2. orbs at 0 and 12 on a 1000 by 700 canvas should differ, got \(atZero)")
        }

        let first = OrbField.orbs(at: 10, width: 1000, height: 700)
        let second = OrbField.orbs(at: 10, width: 1000, height: 700)
        if first != second {
            failures.append("3. orbs at 10 twice should match, got \(first) and \(second)")
        }

        let pairs = [(0, 1), (0, 2), (1, 2)]
        for pair in pairs {
            let gap = distance(atZero[pair.0], atZero[pair.1])
            if gap <= 80 {
                failures.append("4. orbs \(pair.0) and \(pair.1) at t=0 should be more than 80 apart, got \(gap)")
            }
        }

        let atOne = OrbField.orbs(at: 1, width: 1000, height: 700)
        for index in 0..<3 {
            let moved = distance(atZero[index], atOne[index])
            if moved >= 30 {
                failures.append("5. orb \(index) should move less than 30 points from t=0 to t=1, got \(moved)")
            }
        }

        for index in 0..<3 {
            let traveled = distance(atZero[index], atTwelve[index])
            if traveled <= 80 {
                failures.append("7. orb \(index) at t=12 should be more than 80 points from t=0 on a 1000 by 700 canvas, got \(traveled)")
            }
        }

        let atForty = OrbField.orbs(at: 40, width: 1000, height: 700)
        for sample in [atZero, atForty] {
            for orb in sample {
                let onCanvas = orb.x >= -250 && orb.x <= 1000 + 250 && orb.y >= -250 && orb.y <= 700 + 250
                if !onCanvas {
                    failures.append("6. \(orb.hue) center should stay within 250 points of a 1000 by 700 canvas, got x \(orb.x) y \(orb.y)")
                }
            }
        }

        if failures.isEmpty {
            return
        }
        for failure in failures {
            print(failure)
        }
        exit(1)
    }

    static func distance(_ a: OrbPlacement, _ b: OrbPlacement) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
