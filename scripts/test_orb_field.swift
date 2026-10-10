import Foundation

@main
enum TestOrbField {
    static func main() {
        var failures: [String] = []

        let field = OrbField.drifts(width: 1000, height: 700)
        if field.count != 3 {
            failures.append("1. expected 3 drifts, got \(field.count)")
        }
        let hues = field.map(\.hue)
        if hues != ["blue", "violet", "teal"] {
            failures.append("1. hues expected blue, violet, teal, got \(hues)")
        }

        for drift in field {
            let traveled = distance(drift.startX, drift.startY, drift.endX, drift.endY)
            if traveled <= 120 {
                failures.append("2. \(drift.hue) start-to-end distance should be greater than 120, got \(traveled)")
            }
            if drift.seconds <= 0 {
                failures.append("3. \(drift.hue) seconds should be greater than 0, got \(drift.seconds)")
            } else if traveled / drift.seconds >= 30 {
                failures.append("3. \(drift.hue) speed should be less than 30 points a second, got \(traveled / drift.seconds)")
            }
        }

        let pairs = [(0, 1), (0, 2), (1, 2)]
        for pair in pairs {
            let gap = distance(
                field[pair.0].startX, field[pair.0].startY,
                field[pair.1].startX, field[pair.1].startY
            )
            if gap <= 80 {
                failures.append("4. drifts \(pair.0) and \(pair.1) starts should be more than 80 apart, got \(gap)")
            }
        }

        for drift in field {
            let points = [
                (drift.startX, drift.startY, "start"),
                (drift.endX, drift.endY, "end"),
            ]
            for point in points {
                let onCanvas = point.0 >= -250 && point.0 <= 1000 + 250 && point.1 >= -250 && point.1 <= 700 + 250
                if !onCanvas {
                    failures.append("5. \(drift.hue) \(point.2) should stay within 250 points of a 1000 by 700 canvas, got x \(point.0) y \(point.1)")
                }
            }
        }

        let again = OrbField.drifts(width: 1000, height: 700)
        if field != again {
            failures.append("6. drifts(width:height:) twice should match, got \(field) and \(again)")
        }

        let startYs = field.map(\.startY)
        if startYs[0] == startYs[1] && startYs[1] == startYs[2] {
            failures.append("7. startY values should not all be equal, got \(startYs)")
        }
        let highestStartY = startYs.max() ?? 0
        let lowestStartY = startYs.min() ?? 0
        if highestStartY - lowestStartY <= 200 {
            failures.append("8. highest startY minus lowest startY should be greater than 200, got \(highestStartY - lowestStartY)")
        }
        let startXs = field.map(\.startX)
        let rightmostStartX = startXs.max() ?? 0
        let leftmostStartX = startXs.min() ?? 0
        if rightmostStartX - leftmostStartX <= 300 {
            failures.append("9. rightmost startX minus leftmost startX should be greater than 300, got \(rightmostStartX - leftmostStartX)")
        }

        let wider = OrbField.drifts(width: 1400, height: 700)
        if field == wider {
            failures.append("10. drifts on a 1000 by 700 canvas should differ from drifts on a 1400 by 700 canvas")
        }
        if wider[0].startX <= field[0].startX {
            failures.append("11. blue start should move right on a wider canvas, got \(field[0].startX) then \(wider[0].startX)")
        }

        for drift in field {
            if drift.seconds < 8 {
                failures.append("12. \(drift.hue) seconds should be at least 8, got \(drift.seconds)")
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

    static func distance(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let dx = x1 - x2
        let dy = y1 - y2
        return (dx * dx + dy * dy).squareRoot()
    }
}
