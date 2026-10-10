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
    static func drifts(width: Double, height: Double) -> [OrbDrift] {
        [
            OrbDrift(
                hue: "blue",
                startX: width * 0.22,
                startY: height * 0.28,
                endX: width * 0.22 + 280,
                endY: height * 0.28,
                seconds: 3.5
            ),
            OrbDrift(
                hue: "violet",
                startX: width * 0.78,
                startY: height * 0.32,
                endX: width * 0.78 - 280,
                endY: height * 0.32,
                seconds: 3.5
            ),
            OrbDrift(
                hue: "teal",
                startX: width * 0.48,
                startY: height * 0.72,
                endX: width * 0.48,
                endY: height * 0.72 - 280,
                seconds: 3.5
            ),
        ]
    }
}
