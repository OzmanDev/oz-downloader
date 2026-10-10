import Foundation

@main
enum TestFooterLinkPulse {
    static func main() {
        var failures: [String] = []

        if FooterLinkPulse.duration != 2 {
            failures.append("1. pulse lasts 2 seconds, got \(FooterLinkPulse.duration)")
        }
        if !near(FooterLinkPulse.scale(elapsed: 0), 1) {
            failures.append("2. at the start the links are normal size, got \(FooterLinkPulse.scale(elapsed: 0))")
        }
        if !near(FooterLinkPulse.scale(elapsed: 0.5), 1.1) {
            failures.append("3. halfway through the first second the links are a bit bigger, got \(FooterLinkPulse.scale(elapsed: 0.5))")
        }
        if !near(FooterLinkPulse.scale(elapsed: 1), 1) {
            failures.append("4. at one second the links are back to normal, got \(FooterLinkPulse.scale(elapsed: 1))")
        }
        if !near(FooterLinkPulse.scale(elapsed: 1.5), 0.9) {
            failures.append("5. halfway through the second second the links are a bit smaller, got \(FooterLinkPulse.scale(elapsed: 1.5))")
        }
        if !near(FooterLinkPulse.scale(elapsed: 2), 1) {
            failures.append("6. at two seconds the links are normal size, got \(FooterLinkPulse.scale(elapsed: 2))")
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
