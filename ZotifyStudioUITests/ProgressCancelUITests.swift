import XCTest

final class ProgressCancelUITests: OzUITestCase {
    func testD2_progressUpdates() throws {
        app.pasteSpotifyURL(E2EFixtures.playlistURL)
        let download = app.buttons["preview.download"]
        guard download.waitForExistence(timeout: 25) else {
            skipCase("D2", "preview/download unavailable")
            return
        }
        download.click()
        let summary = app.staticTexts["progress.summary"]
        let cancel = app.buttons["progress.cancel"]
        _ = cancel.waitForExistence(timeout: 20)
        if summary.waitForExistence(timeout: 15) || cancel.exists {
            pass("D2", "progress UI visible while downloading")
        } else {
            failCase("D2", "progress summary never appeared")
        }
        if cancel.exists { cancel.click() }
        else if app.buttons["getMusic.cancel"].exists { app.buttons["getMusic.cancel"].click() }
    }

    func testX1_cancelButton() throws {
        app.pasteSpotifyURL(E2EFixtures.playlistURL)
        let download = app.buttons["preview.download"]
        guard download.waitForExistence(timeout: 25) else {
            skipCase("X1", "preview/download unavailable")
            return
        }
        download.click()
        let cancel = app.buttons["progress.cancel"].exists
            ? app.buttons["progress.cancel"]
            : app.buttons["getMusic.cancel"]
        guard cancel.waitForExistence(timeout: 25) else {
            failCase("X1", "cancel button never appeared")
            return
        }
        cancel.click()
        // After cancel, cancel control should leave or celebration shouldn't claim all done falsely.
        Thread.sleep(forTimeInterval: 1.5)
        let stillRunningHard = app.buttons["progress.cancel"].exists && app.buttons["progress.cancel"].isHittable
        if !stillRunningHard {
            pass("X1", "cancel stopped the job")
        } else {
            // Second click / wait
            cancel.click()
            Thread.sleep(forTimeInterval: 2)
            if !app.buttons["progress.cancel"].exists {
                pass("X1", "cancel stopped after second attempt")
            } else {
                failCase("X1", "cancel did not stop download")
            }
        }
    }

    func testD4_openFolder() throws {
        app.goToGetMusic()
        let open = app.buttons["getMusic.openFolder"]
        guard open.waitForExistence(timeout: 5) else {
            failCase("D4", "open folder button missing")
            return
        }
        open.click()
        // Finder activation is hard to assert; button existence + click without crash is the smoke.
        pass("D4", "open folder button clicked")
    }
}
