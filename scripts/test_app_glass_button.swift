import SwiftUI

@main
enum TestAppGlassButton {
    static func main() {
        var failures: [String] = []

        let off = AppGlassButtonLook.opacity(isEnabled: false, isPressed: false)
        let on = AppGlassButtonLook.opacity(isEnabled: true, isPressed: false)
        if off >= on {
            failures.append("1. a disabled button should be dimmer than an enabled one, got \(off) and \(on)")
        }
        if off > 0.5 {
            failures.append("2. a disabled button should sit at half opacity or below, got \(off)")
        }

        if !AppGlassButtonLook.strokeIsAccent(isEnabled: false, prominent: true) {
            failures.append("3. a disabled button should use the same accent stroke")
        }
        if !AppGlassButtonLook.strokeIsAccent(isEnabled: true, prominent: true) {
            failures.append("4. an enabled prominent button should use the accent stroke")
        }
        if !AppGlassButtonLook.strokeIsAccent(isEnabled: true, prominent: false) {
            failures.append("5. an enabled plain button should use the same accent stroke")
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
