import Foundation

enum APIConfig {
    private static let spicyKeyKey = "LiquidPlayer.spicyLyricsApiKey"
    private static let spotifyClientIdKey = "LiquidPlayer.spotifyClientId"
    private static let spotifyClientSecretKey = "LiquidPlayer.spotifyClientSecret"
    private static let spotifyRedirectUriKey = "LiquidPlayer.spotifyRedirectUri"
    // Spicy Lyrics Catalog link for Liquid Player (users get their own client key without using application slots)
    static let spicyLyricsCatalogUrl = "https://developers.spicylyrics.org/catalog/liquid-player"

    // Default keys (sensitive secrets and user client keys kept empty by default)
    static let defaultSpicyLyricsApiKey = ""
    static let defaultSpotifyClientId = "22c28b6eda464ae89cd44842e6e9e070"
    static let defaultSpotifyClientSecret = ""
    static let defaultSpotifyRedirectUri = "liquidplayer://callback"

    static var spicyLyricsApiKey: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: spicyKeyKey), !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return saved.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let envKey = ProcessInfo.processInfo.environment["SPICY_LYRICS_API_KEY"], !envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let plistKey = Bundle.main.object(forInfoDictionaryKey: "SpicyLyricsApiKey") as? String, !plistKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return plistKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return defaultSpicyLyricsApiKey
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: spicyKeyKey)
        }
    }

    static var isSpicyLyricsConnected: Bool {
        !spicyLyricsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var spotifyClientId: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: spotifyClientIdKey), !saved.isEmpty {
                return saved
            }
            if let envKey = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"], !envKey.isEmpty {
                return envKey
            }
            if let plistKey = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientId") as? String, !plistKey.isEmpty {
                return plistKey
            }
            return defaultSpotifyClientId
        }
        set {
            UserDefaults.standard.set(newValue, forKey: spotifyClientIdKey)
        }
    }

    static var spotifyClientSecret: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: spotifyClientSecretKey), !saved.isEmpty {
                return saved
            }
            if let envKey = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_SECRET"], !envKey.isEmpty {
                return envKey
            }
            if let plistKey = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientSecret") as? String, !plistKey.isEmpty {
                return plistKey
            }
            return defaultSpotifyClientSecret
        }
        set {
            UserDefaults.standard.set(newValue, forKey: spotifyClientSecretKey)
        }
    }

    static var spotifyRedirectUri: String {
        get {
            UserDefaults.standard.string(forKey: spotifyRedirectUriKey) ?? defaultSpotifyRedirectUri
        }
        set {
            UserDefaults.standard.set(newValue, forKey: spotifyRedirectUriKey)
        }
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: spicyKeyKey)
        UserDefaults.standard.removeObject(forKey: spotifyClientIdKey)
        UserDefaults.standard.removeObject(forKey: spotifyClientSecretKey)
        UserDefaults.standard.removeObject(forKey: spotifyRedirectUriKey)
    }
}
