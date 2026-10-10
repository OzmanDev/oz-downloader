import Foundation

enum FooterLinkPulse {
    static let duration: TimeInterval = 2

    /// 1 at rest. A bit larger at 0.5s, normal at 1s, a bit smaller at 1.5s, normal again at 2s.
    static func scale(elapsed: TimeInterval) -> Double {
        let amount = 0.1
        guard elapsed > 0, elapsed < duration else { return 1 }
        if elapsed <= 0.5 {
            return 1 + amount * (elapsed / 0.5)
        }
        if elapsed <= 1 {
            return 1 + amount * ((1 - elapsed) / 0.5)
        }
        if elapsed <= 1.5 {
            return 1 - amount * ((elapsed - 1) / 0.5)
        }
        return 1 - amount * ((duration - elapsed) / 0.5)
    }
}
