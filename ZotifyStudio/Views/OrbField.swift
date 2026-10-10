import Foundation

struct OrbDrift: Equatable {
    var hue: String
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double
    var seconds: TimeInterval
}

enum OrbField {
    static let layoutCount = 12

    /// An even pick: the circles start on different edges and travel to one meeting point.
    /// The next pick leaves that meeting point for a new set of edges, so the return is not the same path.
    static func drifts(width: Double, height: Double, pick: Int) -> [OrbDrift] {
        let step = pick >= 0 ? pick : 0
        let merging = step % 2 == 0
        let layout = step / 2 % layoutCount
        let meeting = meetingPoint(layout: layout, width: width, height: height)
        let starts = merging
            ? anchors(layout: layout, width: width, height: height)
            : [meeting, meeting, meeting]
        let ends = merging
            ? [meeting, meeting, meeting]
            : anchors(layout: layout + 1, width: width, height: height)
        let hues = ["blue", "violet", "teal"]
        let distances = zip(starts, ends).map { distance($0.0, $0.1, $1.0, $1.1) }
        let seconds = pace(distances)
        return zip(hues, zip(starts, ends)).map { hue, leg in
            OrbDrift(
                hue: hue,
                startX: leg.0.0,
                startY: leg.0.1,
                endX: leg.1.0,
                endY: leg.1.1,
                seconds: seconds
            )
        }
    }

    static func drifts(width: Double, height: Double) -> [OrbDrift] {
        drifts(width: width, height: height, pick: 0)
    }

    /// A merge leg, so the first motion is toward a meeting point from a random set of edges.
    static func openingPick() -> Int {
        Int.random(in: 0..<layoutCount) * 2
    }

    private static let sides: [[String]] = [
        ["leading", "trailing", "bottom"],
        ["trailing", "top", "leading"],
        ["bottom", "leading", "trailing"],
        ["top", "bottom", "leading"],
        ["leading", "bottom", "top"],
        ["trailing", "bottom", "top"],
        ["bottom", "trailing", "leading"],
        ["top", "leading", "bottom"],
        ["leading", "top", "trailing"],
        ["trailing", "leading", "bottom"],
        ["bottom", "top", "trailing"],
        ["top", "trailing", "leading"],
    ]

    private static let along: [Double] = [0.22, 0.48, 0.78]

    private static func anchors(layout: Int, width: Double, height: Double) -> [(Double, Double)] {
        let index = layout % sides.count
        return sides[index].enumerated().map { hueIndex, side in
            let slot = along[(index + hueIndex) % along.count]
            switch side {
            case "leading":
                return (width * 0.08, height * slot)
            case "trailing":
                return (width * 0.92, height * slot)
            case "top":
                return (width * slot, height * 0.08)
            default:
                return (width * slot, height * 0.92)
            }
        }
    }

    private static func meetingPoint(layout: Int, width: Double, height: Double) -> (Double, Double) {
        let x = 0.44 + Double(layout % 3) * 0.06
        let y = 0.44 + Double((layout / 3) % 3) * 0.06
        return (width * x, height * y)
    }

    private static func pace(_ distances: [Double]) -> TimeInterval {
        let shortest = distances.min() ?? 280
        return min(4, max(shortest / 70, 0.8))
    }

    private static func distance(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let dx = x1 - x2
        let dy = y1 - y2
        return (dx * dx + dy * dy).squareRoot()
    }
}
