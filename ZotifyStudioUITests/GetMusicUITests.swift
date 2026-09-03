import XCTest

final class GetMusicUITests: OzUITestCase {
    func testG1_playlistPreview() throws {
        app.pasteSpotifyURL(E2EFixtures.playlistURL)
        let title = app.staticTexts["preview.title"]
        let ok = title.waitForExistence(timeout: 25)
        if ok {
            pass("G1", "preview title visible: \(title.label)")
        } else {
            // Fallback: any Preview headline or tracks label
            let tracks = app.staticTexts["preview.tracks"]
            if tracks.waitForExistence(timeout: 5) {
                pass("G1", "preview tracks visible")
            } else {
                failCase("G1", "playlist preview did not appear")
            }
        }
    }

    func testG2_downloadButton() throws {
        app.pasteSpotifyURL(E2EFixtures.playlistURL)
        let download = app.buttons["preview.download"]
        guard download.waitForExistence(timeout: 25) else {
            failCase("G2", "download button missing")
            return
        }
        download.click()
        let progress = app.staticTexts["progress.card"]
        let cancel = app.buttons["progress.cancel"]
        let summary = app.staticTexts["progress.summary"]
        let appeared = cancel.waitForExistence(timeout: 20)
            || progress.waitForExistence(timeout: 2)
            || summary.waitForExistence(timeout: 2)
            || app.buttons["getMusic.cancel"].waitForExistence(timeout: 5)
        if appeared {
            pass("G2", "progress/cancel appeared after download")
            if app.buttons["progress.cancel"].exists {
                app.buttons["progress.cancel"].click()
            } else if app.buttons["getMusic.cancel"].exists {
                app.buttons["getMusic.cancel"].click()
            }
        } else {
            failCase("G2", "no progress UI after tapping download")
        }
    }

    func testG3_trackURL() throws {
        app.pasteSpotifyURL(E2EFixtures.trackURL)
        let download = app.buttons["preview.download"]
        if download.waitForExistence(timeout: 25) {
            pass("G3", "track preview + download ready")
        } else if app.staticTexts["preview.title"].waitForExistence(timeout: 5) {
            pass("G3", "track preview title visible")
        } else {
            failCase("G3", "track preview failed")
        }
    }

    func testG4_invalidURL() throws {
        app.pasteSpotifyURL(E2EFixtures.invalidURL)
        // Allow debounce
        Thread.sleep(forTimeInterval: 2.5)
        let err = app.staticTexts["preview.error"]
        let hasError = err.waitForExistence(timeout: 8)
        let noDownload = !app.buttons["preview.download"].exists
        if hasError || noDownload {
            pass("G4", hasError ? "error shown" : "no download for invalid URL")
        } else {
            failCase("G4", "invalid URL did not show error")
        }
    }
}
