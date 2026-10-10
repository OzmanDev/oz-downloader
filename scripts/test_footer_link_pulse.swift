import Foundation

@main
enum TestFooterLinkPulse {
    static func main() {
        var failures: [String] = []

        if FooterLinkPulse.duration != 1.4 {
            failures.append("1. pulse lasts 1.4 seconds, got \(FooterLinkPulse.duration)")
        }
        if !near(FooterLinkPulse.scale(elapsed: 0), 1) {
            failures.append("2. at the start the links are normal size, got \(FooterLinkPulse.scale(elapsed: 0))")
        }
        if !near(FooterLinkPulse.scale(elapsed: 0.35), 1.25) {
            failures.append("3. at the first peak the links are one and a quarter size, got \(FooterLinkPulse.scale(elapsed: 0.35))")
        }
        if !near(FooterLinkPulse.scale(elapsed: 0.7), 1) {
            failures.append("4. halfway through the links are back to normal, got \(FooterLinkPulse.scale(elapsed: 0.7))")
        }
        if !near(FooterLinkPulse.scale(elapsed: 1.05), 0.75) {
            failures.append("5. at the small point the links are three quarters size, got \(FooterLinkPulse.scale(elapsed: 1.05))")
        }
        if !near(FooterLinkPulse.scale(elapsed: 1.4), 1) {
            failures.append("6. at the end the links are normal size, got \(FooterLinkPulse.scale(elapsed: 1.4))")
        }
        if !near(FooterLinkPulse.scale(elapsed: 3), 1) {
            failures.append("7. after the pulse the links stay normal size, got \(FooterLinkPulse.scale(elapsed: 3))")
        }
        if !near(FooterLinkPulse.scale(elapsed: -1), 1) {
            failures.append("8. before the pulse the links are normal size, got \(FooterLinkPulse.scale(elapsed: -1))")
        }

        if failures.isEmpty {
            return
        }
        for failure in failures {
            print(failure)
        }
        exit(1)
    }

    private static func near(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.001
    }
}
