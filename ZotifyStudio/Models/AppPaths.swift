import Foundation

enum AppPaths {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("OzDownloader", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var settingsURL: URL { supportDir.appendingPathComponent("settings.json") }
    static var playlistsURL: URL { supportDir.appendingPathComponent("playlists.json") }
    static var guiPrefsURL: URL { supportDir.appendingPathComponent("prefs.json") }
    static var accountURL: URL { supportDir.appendingPathComponent("account.json") }
    static var avatarURL: URL { supportDir.appendingPathComponent("avatar.jpg") }
    static var spotifyPlaylistsURL: URL { supportDir.appendingPathComponent("spotify_playlists.json") }
    static var playlistCoversDir: URL {
        let dir = supportDir.appendingPathComponent("playlist-covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var playlistCoverIndexURL: URL { playlistCoversDir.appendingPathComponent("index.json") }

    /// App-owned Zotify runtime (config + credentials). Never the terminal’s
    /// `~/Library/Application Support/Zotify/`.
    static var zotifySupportDir: URL {
        let dir = supportDir.appendingPathComponent("zotify", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var zotifyConfigURL: URL { zotifySupportDir.appendingPathComponent("config.json") }
    static var zotifyCredentialsURL: URL { zotifySupportDir.appendingPathComponent("credentials.json") }

    /// Separate download library from the terminal `zotify` folder.
    static var defaultMusicRoot: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Oz Downloader", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Legacy shared folder used by terminal zotify — app must not write here.
    static var terminalZotifyMusicRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Zotify Music", isDirectory: true)
    }

    static var terminalZotifySupportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Zotify", isDirectory: true)
    }

    /// Quote a path for embedding in a Python single-quoted string.
    static func pythonPathLiteral(_ url: URL) -> String {
        let escaped = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    /// Self-contained Python/zotify/ffmpeg shipped inside the .app (Contents/Resources/runtime).
    static var bundledRuntimeDir: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let dir = res.appendingPathComponent("runtime", isDirectory: true)
        let py = dir.appendingPathComponent("bin/python3")
        guard FileManager.default.isExecutableFile(atPath: py.path) else { return nil }
        return dir
    }

    static var bundledPythonURL: URL? {
        bundledRuntimeDir?.appendingPathComponent("bin/python3")
    }

    static var bundledZotifyURL: URL? {
        guard let dir = bundledRuntimeDir else { return nil }
        let url = dir.appendingPathComponent("bin/zotify")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var bundledPostprocessURL: URL? {
        guard let dir = bundledRuntimeDir else { return nil }
        let url = dir.appendingPathComponent("bin/zotify-postprocess")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var bundledFFmpegURL: URL? {
        guard let dir = bundledRuntimeDir else { return nil }
        let url = dir.appendingPathComponent("bin/ffmpeg")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}
