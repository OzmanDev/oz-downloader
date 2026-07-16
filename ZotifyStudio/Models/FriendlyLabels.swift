import Foundation

enum AudioFormatChoice: String, CaseIterable, Identifiable {
    case flac, mp3, m4a, wav, ogg, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flac: return "Best quality (FLAC)"
        case .mp3: return "Compatible (MP3)"
        case .m4a: return "Apple Music friendly (M4A)"
        case .wav: return "Uncompressed (WAV)"
        case .ogg: return "Keep as OGG"
        case .none: return "Don’t convert"
        }
    }
}

enum QualityChoice: String, CaseIterable, Identifiable {
    case auto
    case normal
    case high
    case very_high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .normal: return "Standard"
        case .high: return "High"
        case .very_high: return "Highest"
        }
    }
}
