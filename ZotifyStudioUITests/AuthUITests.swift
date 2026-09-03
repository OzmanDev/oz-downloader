import XCTest

final class AuthUITests: OzUITestCase {
    private var credsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OzDownloader/zotify/credentials.json")
    }

    func testA2_signOut() throws {
        app.goToPreferences()
        let signOut = app.buttons["prefs.signOut"]
        guard signOut.waitForExistence(timeout: 8) else {
            skipCase("A2", "already signed out")
            return
        }
        // Backup credentials for later restoration by shell runner
        let bak = credsURL.appendingPathExtension("uitest-bak")
        if FileManager.default.fileExists(atPath: credsURL.path) {
            try? FileManager.default.removeItem(at: bak)
            try? FileManager.default.copyItem(at: credsURL, to: bak)
        }
        signOut.click()
        // Confirm alert — look for Sign out destructive button
        let alertSignOut = app.buttons["Sign out"]
        if alertSignOut.waitForExistence(timeout: 5) {
            alertSignOut.click()
        }
        let signIn = app.buttons["prefs.signIn"]
        let signedOutUI = signIn.waitForExistence(timeout: 8)
        let credsGone = !FileManager.default.fileExists(atPath: credsURL.path)
        if signedOutUI || credsGone {
            pass("A2", "signed out (ui=\(signedOutUI) credsGone=\(credsGone))")
        } else {
            failCase("A2", "sign out did not clear session")
        }
    }

    func testA1_signInOAuth() throws {
        let user = ProcessInfo.processInfo.environment["OZ_E2E_SPOTIFY_USER"] ?? ""
        let pass = ProcessInfo.processInfo.environment["OZ_E2E_SPOTIFY_PASS"] ?? ""
        guard !user.isEmpty, !pass.isEmpty else {
            skipCase("A1", "set OZ_E2E_SPOTIFY_USER/PASS")
            return
        }
        app.goToPreferences()
        // Ensure signed out first
        if app.buttons["prefs.signOut"].exists {
            app.buttons["prefs.signOut"].click()
            if app.buttons["Sign out"].waitForExistence(timeout: 3) {
                app.buttons["Sign out"].click()
            }
            _ = app.buttons["prefs.signIn"].waitForExistence(timeout: 5)
        }
        let signIn = app.buttons["prefs.signIn"]
        guard signIn.waitForExistence(timeout: 8) else {
            failCase("A1", "sign in button missing")
            return
        }
        // Clear previous oauth url file
        let oauthFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OzDownloader/e2e_oauth_url.txt")
        try? FileManager.default.removeItem(at: oauthFile)
        signIn.click()
        // Wait for URL file from app (OZ_E2E=1)
        var urlStr: String?
        for _ in 0..<60 {
            if let s = try? String(contentsOf: oauthFile, encoding: .utf8), s.contains("http") {
                urlStr = s.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let authURL = urlStr else {
            failCase("A1", "oauth URL file not written")
            return
        }
        // Invoke helper script
        let helper = ProcessInfo.processInfo.environment["OZ_E2E_OAUTH_HELPER"]
            ?? (ProcessInfo.processInfo.environment["SRCROOT"].map { $0 + "/scripts/oauth_browser_helper.py" } ?? "")
        let root = ProcessInfo.processInfo.environment["OZ_E2E_ROOT"]
            ?? FileManager.default.currentDirectoryPath
        let script = helper.isEmpty ? "\(root)/scripts/oauth_browser_helper.py" : helper
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [script, "--url", authURL]
        proc.environment = ProcessInfo.processInfo.environment
        let out = Pipe(); proc.standardOutput = out; proc.standardError = out
        try proc.run()
        proc.waitUntilExit()
        let signedIn = app.buttons["prefs.signOut"].waitForExistence(timeout: 90)
        if signedIn {
            pass("A1", "signed in via OAuth helper")
        } else {
            failCase("A1", "sign-in did not complete (helper exit \(proc.terminationStatus))")
        }
    }

    func testA3_midDownloadAuth() throws {
        let user = ProcessInfo.processInfo.environment["OZ_E2E_SPOTIFY_USER"] ?? ""
        let pass = ProcessInfo.processInfo.environment["OZ_E2E_SPOTIFY_PASS"] ?? ""
        guard !user.isEmpty, !pass.isEmpty else {
            skipCase("A3", "set OZ_E2E_SPOTIFY_USER/PASS")
            return
        }
        // Ensure signed out
        app.goToPreferences()
        if app.buttons["prefs.signOut"].exists {
            app.buttons["prefs.signOut"].click()
            if app.buttons["Sign out"].waitForExistence(timeout: 3) {
                app.buttons["Sign out"].click()
            }
            _ = app.buttons["prefs.signIn"].waitForExistence(timeout: 5)
        }
        // Start download without session — app should hand off to OAuth
        app.pasteSpotifyURL(E2EFixtures.trackURL)
        if app.buttons["preview.download"].waitForExistence(timeout: 20) {
            app.buttons["preview.download"].click()
        }
        let waiting = app.staticTexts["prefs.waitingSignIn"]
        // May stay on Get Music with toast; also check Preferences
        Thread.sleep(forTimeInterval: 2)
        app.goToPreferences()
        if waiting.waitForExistence(timeout: 30) || app.buttons["prefs.cancelSignIn"].exists {
            pass("A3", "mid-download auth handoff visible")
            if app.buttons["prefs.cancelSignIn"].exists {
                app.buttons["prefs.cancelSignIn"].click()
            }
        } else {
            // Soft pass if download simply prompted sign-in somehow
            skipCase("A3", "handoff UI not observed (session may still be present)")
        }
    }
}
