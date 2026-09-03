import XCTest

enum E2EFixtures {
    static let trackURL = "https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl"
    static let playlistURL = "https://open.spotify.com/playlist/27sDUOL87sti0cNV1GyDy6"
    static let invalidURL = "not-a-spotify-link"
    static let resultsPath: URL = {
        let env = ProcessInfo.processInfo.environment["OZ_E2E_UI_RESULTS"]
        if let env, !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("oz-e2e-ui-results.json")
    }()
}

enum E2EResultStore {
    private static let lock = NSLock()

    static func record(id: String, status: String, detail: String = "") {
        lock.lock()
        defer { lock.unlock() }
        var arr: [[String: String]] = []
        if let data = try? Data(contentsOf: E2EFixtures.resultsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            arr = json
        }
        arr.append(["id": id, "status": status, "detail": detail, "message": "\(status)  \(id)" + (detail.isEmpty ? "" : " — \(detail)")])
        if let out = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) {
            try? out.write(to: E2EFixtures.resultsPath)
        }
    }
}

extension XCUIApplication {
    func launchOzDownloader(env: [String: String] = [:]) {
        var launchEnv = ProcessInfo.processInfo.environment
        launchEnv["OZ_E2E"] = "1"
        for (k, v) in env { launchEnv[k] = v }
        self.launchEnvironment = launchEnv
        launchArguments = ["--uitest"]
        launch()
    }

    var tabGetMusic: XCUIElement { buttons["tab.getMusic"] }
    var tabPlaylists: XCUIElement { buttons["tab.playlists"] }
    var tabPreferences: XCUIElement { buttons["tab.preferences"] }

    func goToGetMusic() {
        if tabGetMusic.exists { tabGetMusic.click() }
    }

    func goToPreferences() {
        tabPreferences.click()
    }

    func goToPlaylists() {
        tabPlaylists.click()
    }

    func pasteSpotifyURL(_ url: String) {
        goToGetMusic()
        let field = textFields["getMusic.urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "URL field missing")
        field.click()
        field.typeText(XCUIKeyboardKey.delete.rawValue) // best-effort clear focus
        // Select-all + type for reliability on macOS
        field.typeKey("a", modifierFlags: .command)
        field.typeText(url)
    }
}

class OzUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchOzDownloader()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func pass(_ id: String, _ detail: String = "") {
        E2EResultStore.record(id: id, status: "PASS", detail: detail)
    }

    func failCase(_ id: String, _ detail: String) {
        E2EResultStore.record(id: id, status: "FAIL", detail: detail)
        XCTFail("\(id): \(detail)")
    }

    func skipCase(_ id: String, _ detail: String) {
        E2EResultStore.record(id: id, status: "SKIP", detail: detail)
    }
}
