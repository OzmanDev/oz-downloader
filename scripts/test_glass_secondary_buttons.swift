import Foundation

/// Labeled Mac buttons that were still on the system style use the
/// non-prominent glass button. Alert actions stay on the system style.
@main
enum TestGlassSecondaryButtons {
    static func main() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let download = read("ZotifyStudio/Views/DownloadView.swift", root: root)
        let settings = read("ZotifyStudio/Views/SettingsView.swift", root: root)
        let playlists = read("ZotifyStudio/Views/PlaylistsView.swift", root: root)

        var failures: [String] = []

        func expectGlass(_ source: String, around marker: String, name: String) {
            guard let chain = buttonChain(in: source, endingAt: marker) else {
                failures.append("\(name) button was not found")
                return
            }
            if !chain.contains(".appGlassButton(prominent: false)") {
                failures.append("\(name) should use the non-prominent glass button")
            }
            if chain.contains(".appGlassButton(prominent: true)") {
                failures.append("\(name) should stay non-prominent")
            }
        }

        expectGlass(download, around: "\"getMusic.cancel\"", name: "1. Get Music Cancel")
        expectGlass(download, around: "\"getMusic.openFolder\"", name: "2. Get Music Open default download folder")
        expectGlass(download, around: "\"progress.cancel\"", name: "3. Progress Cancel")
        expectGlass(settings, around: "\"prefs.chooseFolder\"", name: "4. Choose…")
        expectGlass(settings, around: "\"prefs.openFolder\"", name: "5. Preferences Open default download folder")
        expectGlass(settings, around: "\"prefs.signOut\"", name: "6. Sign out…")
        expectGlass(settings, around: "\"prefs.reopenAuth\"", name: "7. Preferences Open page again")
        expectGlass(settings, around: "\"prefs.cancelSignIn\"", name: "8. Preferences Cancel")

        if let developer = buttonChain(in: settings, startingAt: "Button(\"Open Spotify developer site\")") {
            if !developer.contains(".appGlassButton(prominent: false)") {
                failures.append("9. Open Spotify developer site should use the non-prominent glass button")
            }
        } else {
            failures.append("9. Open Spotify developer site button was not found")
        }

        let login = playlists.split(separator: "private var loginRequiredPanel").dropFirst().first.map(String.init) ?? ""
        let loginPanel = login.split(separator: "private var savedSide").first.map(String.init) ?? login
        if buttonCount(loginPanel, label: "Open page again") != 1 || !loginPanel.contains("Button(\"Open page again\")") {
            failures.append("10. login-required Open page again was not found")
        } else if let chain = buttonChain(in: loginPanel, startingAt: "Button(\"Open page again\")"),
                  !chain.contains(".appGlassButton(prominent: false)") {
            failures.append("10. login-required Open page again should use the non-prominent glass button")
        }
        if let chain = buttonChain(in: loginPanel, startingAt: "Button(\"Cancel\")"),
           !chain.contains(".appGlassButton(prominent: false)") {
            failures.append("11. login-required Cancel should use the non-prominent glass button")
        }

        if let chain = buttonChain(in: playlists, startingAt: "Button(\"Cancel\") { showAddSheet = false }"),
           !chain.contains(".appGlassButton(prominent: false)") {
            failures.append("12. add-sheet Cancel should use the non-prominent glass button")
        }

        if let alertRange = settings.range(of: ".alert(\"Sign out of Spotify?\"") {
            let after = settings[alertRange.lowerBound...]
            let alert = after.split(separator: "message:", maxSplits: 1).first.map(String.init) ?? String(after)
            if alert.contains("appGlassButton") {
                failures.append("13. the sign-out alert buttons should stay on the system style")
            }
        } else {
            failures.append("13. sign-out alert was not found")
        }

        if failures.isEmpty {
            return
        }
        for failure in failures {
            print(failure)
        }
        exit(1)
    }

    static func read(_ relative: String, root: URL) -> String {
        let url = root.appendingPathComponent(relative)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// The button declaration that owns `marker`, including its modifiers.
    static func buttonChain(in source: String, endingAt marker: String) -> String? {
        guard let markerRange = source.range(of: marker) else { return nil }
        let head = source[..<markerRange.upperBound]
        guard let buttonStart = lastButtonDeclaration(in: head) else { return nil }
        let tail = source[buttonStart...]
        return chain(from: tail)
    }

    static func buttonChain(in source: String, startingAt marker: String) -> String? {
        guard let start = source.range(of: marker) else { return nil }
        return chain(from: source[start.lowerBound...])
    }

    static func chain(from tail: Substring) -> String {
        var lines: [String] = []
        var startedModifiers = false
        var depth = 0
        var sawBrace = false
        for line in tail.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            lines.append(text)
            depth += text.filter { $0 == "{" }.count
            depth -= text.filter { $0 == "}" }.count
            if text.contains("{") { sawBrace = true }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if sawBrace && depth == 0 {
                startedModifiers = true
                continue
            }
            if startedModifiers {
                if trimmed.hasPrefix(".") { continue }
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The last `Button(` or `Button {` that is not the `Button` inside `appGlassButton`.
    static func lastButtonDeclaration(in head: Substring) -> String.Index? {
        var best: String.Index?
        for pattern in ["Button(", "Button {"] {
            var search = head.startIndex..<head.endIndex
            while let found = head.range(of: pattern, range: search) {
                let before = found.lowerBound > head.startIndex
                    ? head[head.index(before: found.lowerBound)]
                    : " "
                if !before.isLetter, best == nil || found.lowerBound > best! {
                    best = found.lowerBound
                }
                search = found.upperBound..<head.endIndex
            }
        }
        return best
    }

    static func buttonCount(_ source: String, label: String) -> Int {
        source.components(separatedBy: "Button(\"\(label)\")").count - 1
    }
}
