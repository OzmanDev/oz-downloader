import Foundation

enum FooterLinkPulse {
    static let duration: TimeInterval = 1.4

    /// 1 at rest. One and a quarter at the first quarter, normal at halfway, three quarters at the third quarter, normal again at the end.
    static func scale(elapsed: TimeInterval) -> Double {
        let amount = 0.25
        guard elapsed > 0, elapsed < duration else { return 1 }
        let quarter = duration / 4
        if elapsed <= quarter {
            return 1 + amount * (elapsed / quarter)
        }
        if elapsed <= quarter * 2 {
            return 1 + amount * ((quarter * 2 - elapsed) / quarter)
        }
        if elapsed <= quarter * 3 {
            return 1 - amount * ((elapsed - quarter * 2) / quarter)
        }
        return 1 - amount * ((duration - elapsed) / quarter)
    }
}
