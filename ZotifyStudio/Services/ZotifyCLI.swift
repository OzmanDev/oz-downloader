import Foundation
import Darwin

struct CommandResult {
    let exitCode: Int32
    let output: String

    /// Lines printed as `OZ_JSON|{...}` by Python helpers (avoids nested-brace parse bugs).
    func ozJSON() -> [String: Any]? {
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("OZ_JSON|") else { continue }
            let payload = String(line.dropFirst("OZ_JSON|".count))
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            return obj
        }
        return nil
    }
}

enum ZotifyCLI {

    static func which(_ name: String) -> URL? {
        // Prefer tools bundled inside the .app so friends need no Terminal setup.
        if let runtime = AppPaths.bundledRuntimeDir {
            let bundled = runtime.appendingPathComponent("bin/\(name)")
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }

        let paths = [
            NSHomeDirectory() + "/bin/" + name,
            "/opt/anaconda3/bin/" + name,
            "/usr/local/bin/" + name,
            "/opt/homebrew/bin/" + name,
        ]
        for p in paths where FileManager.default.isExecutableFile(atPath: p) {
            // Prefer wrapper in ~/bin for `zotify` when it's the Studio wrapper; still OK for raw too.
            return URL(fileURLWithPath: p)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        } catch {}
        return nil
    }

    static var zotifyURL: URL? { which("zotify") }
    static var postprocessURL: URL? { which("zotify-postprocess") }
    /// Python that has mutagen (Anaconda) — used to run postprocess reliably from the app.
    static var anacondaPythonURL: URL? {
        let candidates = [
            "/opt/anaconda3/bin/python3",
            "/opt/anaconda3/bin/python",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// Prefer a Python that can `import zotify` (needed for Spotify sign-in / metadata).
    static var pythonWithZotifyURL: URL? {
        if let bundled = AppPaths.bundledPythonURL {
            let proc = Process()
            proc.executableURL = bundled
            proc.arguments = ["-c", "import zotify"]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 { return bundled }
            } catch {}
        }

        var candidates: [String] = []
        if let anaconda = anacondaPythonURL?.path { candidates.append(anaconda) }
        candidates += [
            NSHomeDirectory() + "/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        if let whichPy = which("python3")?.path { candidates.insert(whichPy, at: 0) }
        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            // Skip the bare name lookup that resolved to our wrapper script path without zotify.
            if path.hasSuffix("/bin/python3"), path.contains("/Oz Downloader.app/") {
                continue
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["-c", "import zotify"]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    return URL(fileURLWithPath: path)
                }
            } catch {}
        }
        return nil
    }
    /// Prefer the real package binary to avoid interactive wrapper prompts
    /// (and to avoid the terminal wrapper that shares CLI playlists/config).
    static var realZotifyURL: URL? {
        if let bundled = AppPaths.bundledZotifyURL { return bundled }
        let candidates = [
            "/opt/anaconda3/bin/zotify",
            NSHomeDirectory() + "/.local/bin/zotify",
            "/usr/local/bin/zotify",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return which("zotify")
    }

    /// Flags that pin every CLI run to Oz Downloader’s private config/session/library.
    static func isolatedFlags(rootPath: String) -> [String] {
        [
            "-c", AppPaths.zotifyConfigURL.path,
            "--creds", AppPaths.zotifyCredentialsURL.path,
            "-rp", rootPath,
        ]
    }

    /// Remove `zotify_*.log` files Zotify creates under the download root.
    static func scrubLogFiles(in rootPath: String) {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files {
            let name = file.lastPathComponent
            if name.hasPrefix("zotify_"), name.hasSuffix(".log") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Scrub zotify logs for every known music root (CLI `-rp` + app config).
    static func scrubLogFiles(arguments: [String] = []) {
        var roots = Set<String>()
        if let i = arguments.firstIndex(of: "-rp"), i + 1 < arguments.count {
            roots.insert(arguments[i + 1])
        }
        if let data = try? Data(contentsOf: AppPaths.zotifyConfigURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let root = obj["ROOT_PATH"] as? String, !root.isEmpty {
            roots.insert(root)
        }
        for root in roots {
            scrubLogFiles(in: root)
        }
    }

    @discardableResult
    static func run(
        executable: URL,
        arguments: [String],
        onLine: ((String) -> Void)? = nil,
        isCancelled: (() -> Bool)? = nil,
        /// Kill the process if no stdout/stderr and no external heartbeat for this long.
        stallTimeout: TimeInterval = 90,
        /// Optional external heartbeat (e.g. new files on disk). Return true when progress happened.
        stallHeartbeat: (() -> Bool)? = nil
    ) throws -> CommandResult {
        defer { scrubLogFiles(arguments: arguments) }

        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["TQDM_MININTERVAL"] = "0.1"
        // GUI apps get a minimal PATH — make sure Homebrew ffmpeg / Anaconda tools resolve.
        // Bundled runtime first so the notarized DMG works without Terminal setup.
        // Anaconda before Homebrew so `python3` scripts keep mutagen/zotify deps.
        var pathExtras = [
            NSHomeDirectory() + "/bin",
            "/opt/anaconda3/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            NSHomeDirectory() + "/.local/bin",
        ]
        if let runtimeBin = AppPaths.bundledRuntimeDir?.appendingPathComponent("bin").path {
            pathExtras.insert(runtimeBin, at: 0)
        }
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (pathExtras + [existingPath]).joined(separator: ":")
        proc.environment = env

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        var collected = ""
        let lock = NSLock()
        var outCarry = ""
        var errCarry = ""
        let carryLock = NSLock()
        let beatLock = NSLock()
        var lastBeat = Date()
        var stalledOut = false

        func bumpBeat() {
            beatLock.lock()
            lastBeat = Date()
            beatLock.unlock()
        }

        func emitLines(from chunk: String, carry: inout String) {
            carry += chunk
            // tqdm rewrites the same line with \r — treat CR/LF as delimiters.
            while let idx = carry.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                let line = String(carry[..<idx])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let next = carry.index(after: idx)
                carry = String(carry[next...])
                // Swallow the extra LF in CRLF.
                if carry.first == "\n" {
                    carry.removeFirst()
                }
                if !line.isEmpty {
                    bumpBeat()
                    DispatchQueue.main.async { onLine?(line) }
                }
            }
        }

        func flushCarry(_ carry: inout String) {
            let leftover = carry.trimmingCharacters(in: .whitespacesAndNewlines)
            carry = ""
            if !leftover.isEmpty {
                bumpBeat()
                DispatchQueue.main.async { onLine?(leftover) }
            }
        }

        /// tqdm sometimes sits in the buffer without a trailing CR yet — emit once we see a rate.
        func emitPartialProgressIfNeeded(_ carry: inout String) {
            let trimmed = carry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 12,
                  trimmed.contains("%"),
                  trimmed.range(of: #"[0-9.]+\s*[KMG]?i?[Bb]/s"#, options: [.regularExpression, .caseInsensitive]) != nil
            else { return }
            bumpBeat()
            DispatchQueue.main.async { onLine?(trimmed) }
            // Keep carry so a later \r still completes the line cleanly.
        }

        func attach(_ pipe: Pipe, isErr: Bool) {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    return
                }
                bumpBeat()
                if let text = String(data: data, encoding: .utf8) {
                    lock.lock()
                    collected += text
                    lock.unlock()
                    carryLock.lock()
                    if isErr {
                        emitLines(from: text, carry: &errCarry)
                        emitPartialProgressIfNeeded(&errCarry)
                    } else {
                        emitLines(from: text, carry: &outCarry)
                        emitPartialProgressIfNeeded(&outCarry)
                    }
                    carryLock.unlock()
                }
            }
        }

        attach(out, isErr: false)
        attach(err, isErr: true)

        try proc.run()

        while proc.isRunning {
            if isCancelled?() == true {
                // Spotify/librespot often ignores SIGTERM — escalate like stallTimeout.
                proc.terminate()
                Thread.sleep(forTimeInterval: 0.35)
                if proc.isRunning {
                    proc.interrupt()
                    kill(proc.processIdentifier, SIGKILL)
                }
                // Kill child helpers (ffmpeg etc.) that may outlive the wrapper.
                let pid = proc.processIdentifier
                if pid > 0 {
                    let pkill = Process()
                    pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                    pkill.arguments = ["-KILL", "-P", String(pid)]
                    pkill.standardOutput = Pipe()
                    pkill.standardError = Pipe()
                    try? pkill.run()
                    pkill.waitUntilExit()
                }
                break
            }
            if stallHeartbeat?() == true {
                bumpBeat()
            }
            beatLock.lock()
            let idle = Date().timeIntervalSince(lastBeat)
            beatLock.unlock()
            if stallTimeout > 0, idle >= stallTimeout {
                stalledOut = true
                proc.terminate()
                // Hard-kill if still alive after a moment (Spotify sockets often ignore SIGTERM).
                Thread.sleep(forTimeInterval: 0.8)
                if proc.isRunning {
                    proc.interrupt()
                    kill(proc.processIdentifier, SIGKILL)
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil

        // Drain remaining
        let restOut = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let restErr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        lock.lock()
        collected += restOut + restErr
        if stalledOut {
            collected += "\n[Oz Downloader] Spotify download stalled (no progress for \(Int(stallTimeout))s) — killed.\n"
        }
        lock.unlock()
        carryLock.lock()
        if !restOut.isEmpty { emitLines(from: restOut, carry: &outCarry) }
        if !restErr.isEmpty { emitLines(from: restErr, carry: &errCarry) }
        flushCarry(&outCarry)
        flushCarry(&errCarry)
        carryLock.unlock()

        return CommandResult(exitCode: stalledOut ? 124 : proc.terminationStatus, output: collected)
    }
}
