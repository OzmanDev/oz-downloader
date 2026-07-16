import Foundation

struct AppSettings: Codable, Equatable {
    var rootPath: String
    var downloadFormat: String
    var downloadQuality: String
    var bulkWaitTime: String
    var downloadRateLimiter: String
    var retryAttempts: String
    var skipExisting: Bool
    var skipPreviouslyDownloaded: Bool
    var apiClientId: String
    var convertFormat: String
    var autoPostprocess: Bool
    var defaultGenre: String

    /// Empty / neutral defaults — no user session or playlists.
    static let empty = AppSettings(
        rootPath: AppPaths.defaultMusicRoot.path,
        downloadFormat: "ogg",
        downloadQuality: "very_high",
        bulkWaitTime: "1",
        downloadRateLimiter: "0",
        retryAttempts: "3",
        skipExisting: true,
        skipPreviouslyDownloaded: false,
        apiClientId: "",
        convertFormat: "flac",
        autoPostprocess: true,
        defaultGenre: ""
    )
}

struct SavedPlaylist: Codable, Identifiable, Equatable, Hashable {
    var id: String { alias }
    var alias: String
    var name: String
    var url: String
    var trackCount: Int
    var imageURL: String

    init(alias: String, name: String, url: String, trackCount: Int = 0, imageURL: String = "") {
        self.alias = alias
        self.name = name
        self.url = url
        self.trackCount = trackCount
        self.imageURL = imageURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alias = try c.decode(String.self, forKey: .alias)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
    }

    var tracksLabel: String {
        if trackCount <= 0 { return "" }
        return trackCount == 1 ? "1 song" : "\(trackCount) songs"
    }
}

struct FetchedPlaylist: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var url: String
    var owner: String? = nil
    /// True when this playlist is owned by the signed-in Spotify user.
    var isOwned: Bool = false
    /// Spotify / Made For You editorial lists (id usually starts with 37i9).
    var isSpotify: Bool = false
    var trackCount: Int = 0
    var imageURL: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, url, owner, isOwned, isSpotify, trackCount, imageURL
    }

    init(
        id: String,
        name: String,
        url: String,
        owner: String? = nil,
        isOwned: Bool = false,
        isSpotify: Bool = false,
        trackCount: Int = 0,
        imageURL: String = ""
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.owner = owner
        self.isOwned = isOwned
        self.isSpotify = isSpotify
        self.trackCount = trackCount
        self.imageURL = imageURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        isOwned = try c.decodeIfPresent(Bool.self, forKey: .isOwned) ?? false
        isSpotify = try c.decodeIfPresent(Bool.self, forKey: .isSpotify)
            ?? id.hasPrefix("37i9")
        trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
    }

    var tracksLabel: String {
        if trackCount <= 0 { return "" }
        return trackCount == 1 ? "1 song" : "\(trackCount) songs"
    }
}

enum PlaylistFilter: String, CaseIterable, Identifiable {
    case all
    case byMe
    case followed
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .byMe: return "By me"
        case .followed: return "Followed"
        case .spotify: return "Spotify"
        }
    }
}

struct SpotifyAccountInfo: Codable, Equatable {
    var userId: String
    var displayName: String
    var imageURL: String

    static let empty = SpotifyAccountInfo(userId: "", displayName: "", imageURL: "")

    init(userId: String, displayName: String, imageURL: String = "") {
        self.userId = userId
        self.displayName = displayName
        self.imageURL = imageURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
    }
}
