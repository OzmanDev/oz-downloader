import SwiftUI
import AppKit
import CryptoKit

/// Spotify-style square playlist cover with memory + disk cache.
struct PlaylistArtworkView: View {
    let imageURL: String
    /// Used to resolve a cover via Spotify oEmbed when `imageURL` is empty.
    var spotifyURL: String = ""
    var size: CGFloat = 48

    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if !loadFailed {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .task(id: imageURL + "|" + spotifyURL) {
            await load()
        }
    }

    private func load() async {
        loadFailed = false
        if let cached = await PlaylistImageCache.shared.image(for: imageURL) {
            image = cached
            return
        }
        if imageURL.isEmpty, let cached = await PlaylistImageCache.shared.image(for: spotifyURL) {
            image = cached
            return
        }

        var resolved = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolved.isEmpty {
            resolved = await PlaylistImageCache.shared.oEmbedThumbnail(for: spotifyURL) ?? ""
        }
        guard let url = URL(string: resolved), !resolved.isEmpty else {
            loadFailed = true
            return
        }

        if let cached = await PlaylistImageCache.shared.image(for: resolved) {
            image = cached
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let nsImage = NSImage(data: data) else {
                loadFailed = true
                return
            }
            await PlaylistImageCache.shared.store(nsImage, data: data, for: resolved)
            if !spotifyURL.isEmpty {
                await PlaylistImageCache.shared.store(nsImage, data: data, for: spotifyURL)
            }
            if !imageURL.isEmpty, imageURL != resolved {
                await PlaylistImageCache.shared.store(nsImage, data: data, for: imageURL)
            }
            image = nsImage
        } catch {
            loadFailed = true
        }
    }
}

@MainActor
final class PlaylistImageCache {
    static let shared = PlaylistImageCache()

    private let memory = NSCache<NSString, NSImage>()
    private var oEmbedInflight: [String: Task<String?, Never>] = [:]
    private var oEmbedMap: [String: String] = [:]
    private let ioQueue = DispatchQueue(label: "com.oz.downloader.playlist-covers", qos: .utility)

    private init() {
        memory.countLimit = 300
        oEmbedMap = Self.loadIndex()
        try? FileManager.default.createDirectory(
            at: AppPaths.playlistCoversDir,
            withIntermediateDirectories: true
        )
    }

    func image(for key: String) async -> NSImage? {
        let k = Self.normalize(key)
        guard !k.isEmpty else { return nil }
        if let mem = memory.object(forKey: k as NSString) {
            return mem
        }
        let fileURL = diskURL(for: k)
        return await withCheckedContinuation { cont in
            ioQueue.async {
                guard let data = try? Data(contentsOf: fileURL),
                      let image = NSImage(data: data) else {
                    cont.resume(returning: nil)
                    return
                }
                DispatchQueue.main.async {
                    self.memory.setObject(image, forKey: k as NSString)
                    cont.resume(returning: image)
                }
            }
        }
    }

    func store(_ image: NSImage, data: Data? = nil, for key: String) async {
        let k = Self.normalize(key)
        guard !k.isEmpty else { return }
        memory.setObject(image, forKey: k as NSString)

        let payload: Data?
        if let data, !data.isEmpty {
            payload = data
        } else {
            payload = image.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
            }
        }
        guard let bytes = payload else { return }
        let fileURL = diskURL(for: k)
        ioQueue.async {
            try? bytes.write(to: fileURL, options: [.atomic])
        }
    }

    func oEmbedThumbnail(for spotifyURL: String) async -> String? {
        let raw = Self.normalize(spotifyURL)
        guard !raw.isEmpty else { return nil }

        if let mapped = oEmbedMap[raw], !mapped.isEmpty {
            return mapped
        }
        // Already have an image keyed by the Spotify playlist URL.
        if await image(for: raw) != nil {
            return raw
        }
        if let inflight = oEmbedInflight[raw] {
            return await inflight.value
        }

        let task = Task<String?, Never> {
            guard var comps = URLComponents(string: "https://open.spotify.com/oembed") else { return nil }
            comps.queryItems = [URLQueryItem(name: "url", value: raw)]
            guard let url = comps.url else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let thumb = obj["thumbnail_url"] as? String,
                      !thumb.isEmpty else { return nil }
                return thumb
            } catch {
                return nil
            }
        }
        oEmbedInflight[raw] = task
        let result = await task.value
        oEmbedInflight[raw] = nil
        if let result {
            oEmbedMap[raw] = result
            persistIndex()
        }
        return result
    }

    private func diskURL(for key: String) -> URL {
        let digest = Self.hash(key)
        return AppPaths.playlistCoversDir.appendingPathComponent("\(digest).jpg")
    }

    private func persistIndex() {
        let snapshot = oEmbedMap
        let url = AppPaths.playlistCoverIndexURL
        ioQueue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted]) else {
                return
            }
            try? data.write(to: url, options: [.atomic])
        }
    }

    private static func loadIndex() -> [String: String] {
        guard let data = try? Data(contentsOf: AppPaths.playlistCoverIndexURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj
    }

    private static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hash(_ key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
