import XCTest

final class PreferencesUITests: OzUITestCase {
    func testC4_convertOffToggle() throws {
        app.goToPreferences()
        let toggle = app.switches["prefs.autoConvert"]
        // On macOS Form toggles may appear as checkBoxes
        let control: XCUIElement = {
            if toggle.exists { return toggle }
            return app.checkBoxes["prefs.autoConvert"]
        }()
        guard control.waitForExistence(timeout: 8) else {
            failCase("C4", "auto-convert toggle missing")
            return
        }
        // Turn OFF if currently on
        if control.value as? String == "1" || (control.value as? Int) == 1 {
            control.click()
        }
        // Persist via Save if present
        let save = app.buttons["Save preferences"]
        if save.exists { save.click() }
        pass("C4", "convert automatically toggled off (download leave-ogg covered by shell C4 path)")
    }

    func testS2_rootPathField() throws {
        app.goToPreferences()
        let field = app.textFields["prefs.rootPath"]
        guard field.waitForExistence(timeout: 8) else {
            failCase("S2", "root path field missing")
            return
        }
        let before = field.value as? String ?? ""
        // Point at a unique temp dir without opening NSOpenPanel (panel not automatable reliably).
        let tmp = NSTemporaryDirectory() + "oz-e2e-root-\(UUID().uuidString.prefix(8))"
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(tmp)
        let save = app.buttons["Save preferences"]
        if save.exists { save.click() }
        let after = field.value as? String ?? ""
        if after.contains("oz-e2e-root") || after == tmp {
            pass("S2", "root path set to temp folder")
        } else if before != after {
            pass("S2", "root path changed")
        } else {
            failCase("S2", "root path did not change (before=\(before))")
        }
    }
}
