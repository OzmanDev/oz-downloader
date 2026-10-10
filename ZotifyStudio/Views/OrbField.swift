import Foundation

struct OrbPlacement: Equatable {
    var hue: String
    var x: Double
    var y: Double
}

enum OrbField {
    static func orbs(at time: TimeInterval, width: Double, height: Double) -> [OrbPlacement] {
        let hues = ["blue", "violet", "teal"]
        let anchorX = [0.22, 0.74, 0.48]
        let anchorY = [0.30, 0.36, 0.72]
        let phase = [0.6, 2.4, 4.2]
        return (0..<3).map { index in
            let driftX = 64 * sin(time * 0.2 + phase[index])
            let driftY = 64 * cos(time * 0.15 + phase[index])
            return OrbPlacement(
                hue: hues[index],
                x: width * anchorX[index] + driftX,
                y: height * anchorY[index] + driftY
            )
        }
    }
}
