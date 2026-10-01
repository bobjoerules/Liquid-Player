import SwiftUI
import Combine
import MediaPlayer
import AVFoundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    func toHex() -> String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        if let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let converted = uiColor.cgColor.converted(to: sRGBSpace, intent: .defaultIntent, options: nil),
           let components = converted.components {
            if components.count >= 3 {
                let r = Int(lround(Double(max(0, min(1, components[0])) * 255.0)))
                let g = Int(lround(Double(max(0, min(1, components[1])) * 255.0)))
                let b = Int(lround(Double(max(0, min(1, components[2])) * 255.0)))
                return String(format: "#%02X%02X%02X", r, g, b)
            } else if components.count >= 1 {
                let w = Int(lround(Double(max(0, min(1, components[0])) * 255.0)))
                return String(format: "#%02X%02X%02X", w, w, w)
            }
        }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            let ri = Int(lround(Double(max(0, min(1, r)) * 255.0)))
            let gi = Int(lround(Double(max(0, min(1, g)) * 255.0)))
            let bi = Int(lround(Double(max(0, min(1, b)) * 255.0)))
            return String(format: "#%02X%02X%02X", ri, gi, bi)
        }
        #elseif canImport(AppKit)
        let nsColor = NSColor(self)
        if let rgbColor = nsColor.usingColorSpace(.sRGB) {
            let r = Int(lround(Double(max(0, min(1, rgbColor.redComponent)) * 255.0)))
            let g = Int(lround(Double(max(0, min(1, rgbColor.greenComponent)) * 255.0)))
            let b = Int(lround(Double(max(0, min(1, rgbColor.blueComponent)) * 255.0)))
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        #endif
        return "#FFFFFF"
    }
}

struct LyricColorPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let hex: String
    var isRainbow: Bool { id == "rainbow" }
    var isArtwork: Bool { id == "artwork" }
    var color: Color { Color(hex: hex) }

    static let rainbowColors: [Color] = [
        Color(hex: "#FF4B72"), // Coral Red
        Color(hex: "#FF8024"), // Vivid Orange
        Color(hex: "#F5BA24"), // Amber Gold
        Color(hex: "#10B981"), // Emerald Green
        Color(hex: "#06B6D4"), // Cyan
        Color(hex: "#38BDF8"), // Sky Blue
        Color(hex: "#818CF8"), // Indigo Violet
        Color(hex: "#E879F9")  // Vivid Purple / Pink
    ]

    static func presets(for colorScheme: ColorScheme = .dark) -> [LyricColorPreset] {
        let isLight = colorScheme == .light
        return [
            LyricColorPreset(id: "rainbow", name: "Rainbow", hex: "rainbow"),
            LyricColorPreset(id: "artwork", name: "Album Art", hex: "artwork"),
            LyricColorPreset(
                id: "white",
                name: isLight ? "Black" : "White",
                hex: isLight ? "#000000" : "#FFFFFF"
            ),
            LyricColorPreset(id: "green", name: "Spotify Green", hex: "#1DB954"),
            LyricColorPreset(id: "cyan", name: "Cyan", hex: "#38BDF8"),
            LyricColorPreset(id: "purple", name: "Purple", hex: "#C084FC"),
            LyricColorPreset(id: "coral", name: "Coral", hex: "#FB7185"),
            LyricColorPreset(id: "gold", name: "Gold", hex: "#FBBF24"),
            LyricColorPreset(id: "orange", name: "Orange", hex: "#FB923C")
        ]
    }

    static var presets: [LyricColorPreset] {
        presets(for: .dark)
    }

    static func isMonochromePreset(_ hex: String) -> Bool {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return h == "#FFFFFF" || h == "#FFF" || h == "#000000" || h == "#000" || h == "WHITE" || h == "BLACK"
    }

    static func resolveAdaptiveHex(_ hex: String, for colorScheme: ColorScheme) -> String {
        if isMonochromePreset(hex) {
            return colorScheme == .light ? "#000000" : "#FFFFFF"
        }
        return hex
    }
}

enum PlayerBackgroundStyle: String, CaseIterable, Identifiable, Codable {
    case moving = "Blurred & Moving"
    case blurred = "Blurred Album Art"
    case gradient = "Subtle Gradient"
    case black = "Pure Black"

    var id: String { rawValue }

    func displayName(for colorScheme: ColorScheme) -> String {
        if self == .black {
            return colorScheme == .light ? "Pure White" : "Pure Black"
        }
        return rawValue
    }
}

enum LyricsFontDesign: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard"
    case rounded = "Rounded"
    case serif = "Serif"
    case monospaced = "Monospaced"

    var id: String { rawValue }

    var fontDesign: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

enum LyricsFontSize: String, CaseIterable, Identifiable, Codable {
    case small = "Compact"
    case medium = "Regular"
    case large = "Large"

    var id: String { rawValue }

    var leadSize: CGFloat {
        switch self {
        case .small: return 24
        case .medium: return 28
        case .large: return 34
        }
    }

    var backgroundSize: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 22
        case .large: return 26
        }
    }
}

#if canImport(UIKit)
enum ArtworkColorExtractor {
    struct ExtractedColors {
        let darkHex: String
        let lightHex: String
    }

    static func extractColors(from image: UIImage) -> ExtractedColors {
        guard let cgImage = image.cgImage else {
            return ExtractedColors(darkHex: "#38BDF8", lightHex: "#0284C7")
        }

        let sampleSize = 36
        let width = sampleSize
        let height = sampleSize
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return ExtractedColors(darkHex: "#38BDF8", lightHex: "#0284C7")
        }

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return ExtractedColors(darkHex: "#38BDF8", lightHex: "#0284C7")
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        struct ColorBucket {
            var totalR: Double = 0
            var totalG: Double = 0
            var totalB: Double = 0
            var totalSat: Double = 0
            var totalBright: Double = 0
            var count: Int = 0
        }

        // 16 hue bins (22.5 degrees each)
        var hueBins = [ColorBucket](repeating: ColorBucket(), count: 16)
        var allPixelsBucket = ColorBucket()

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let a = Double(rawData[offset + 3]) / 255.0
                if a < 0.5 { continue }

                let r = Double(rawData[offset]) / 255.0
                let g = Double(rawData[offset + 1]) / 255.0
                let b = Double(rawData[offset + 2]) / 255.0

                allPixelsBucket.totalR += r
                allPixelsBucket.totalG += g
                allPixelsBucket.totalB += b
                allPixelsBucket.count += 1

                let maxC = max(r, max(g, b))
                let minC = min(r, min(g, b))
                let delta = maxC - minC
                let brightness = maxC
                let saturation = maxC > 0.001 ? delta / maxC : 0.0

                // Exclude near-black, near-white, or unsaturated pixels from hue bins
                if brightness < 0.12 || (brightness > 0.92 && saturation < 0.15) || saturation < 0.15 {
                    continue
                }

                var hue: Double = 0
                if delta > 0.001 {
                    if maxC == r {
                        hue = (g - b) / delta
                    } else if maxC == g {
                        hue = 2.0 + (b - r) / delta
                    } else {
                        hue = 4.0 + (r - g) / delta
                    }
                    hue *= 60.0
                    if hue < 0 { hue += 360.0 }
                }

                let binIndex = min(15, max(0, Int((hue / 360.0) * 16.0)))
                hueBins[binIndex].totalR += r
                hueBins[binIndex].totalG += g
                hueBins[binIndex].totalB += b
                hueBins[binIndex].totalSat += saturation
                hueBins[binIndex].totalBright += brightness
                hueBins[binIndex].count += 1
            }
        }

        var bestBucket: ColorBucket?
        var highestScore: Double = -1.0

        for bucket in hueBins where bucket.count > 0 {
            let avgSat = bucket.totalSat / Double(bucket.count)
            let avgBright = bucket.totalBright / Double(bucket.count)
            let score = Double(bucket.count) * (avgSat * 1.5 + 0.3) * (avgBright > 0.3 ? 1.0 : 0.6)
            if score > highestScore {
                highestScore = score
                bestBucket = bucket
            }
        }

        let pickedR: Double
        let pickedG: Double
        let pickedB: Double

        if let best = bestBucket, best.count >= 4 {
            pickedR = best.totalR / Double(best.count)
            pickedG = best.totalG / Double(best.count)
            pickedB = best.totalB / Double(best.count)
        } else if allPixelsBucket.count > 0 {
            pickedR = allPixelsBucket.totalR / Double(allPixelsBucket.count)
            pickedG = allPixelsBucket.totalG / Double(allPixelsBucket.count)
            pickedB = allPixelsBucket.totalB / Double(allPixelsBucket.count)
        } else {
            return ExtractedColors(darkHex: "#38BDF8", lightHex: "#0284C7")
        }

        let maxC = max(pickedR, max(pickedG, pickedB))
        let minC = min(pickedR, min(pickedG, pickedB))
        let delta = maxC - minC
        var hue: Double = 0
        if delta > 0.001 {
            if maxC == pickedR {
                hue = (pickedG - pickedB) / delta
            } else if maxC == pickedG {
                hue = 2.0 + (pickedB - pickedR) / delta
            } else {
                hue = 4.0 + (pickedR - pickedG) / delta
            }
            hue *= 60.0
            if hue < 0 { hue += 360.0 }
        }
        let sat = maxC > 0.001 ? delta / maxC : 0.0
        let bright = maxC

        if sat < 0.12 {
            return ExtractedColors(darkHex: "#FFFFFF", lightHex: "#1C1C1E")
        }

        let darkSat = min(1.0, max(0.55, sat))
        let darkBright = max(0.78, min(1.0, bright * 1.35))
        let darkColor = UIColor(hue: CGFloat(hue / 360.0), saturation: CGFloat(darkSat), brightness: CGFloat(darkBright), alpha: 1.0)

        let lightSat = min(1.0, max(0.70, sat))
        let lightBright = min(0.48, max(0.25, bright * 0.70))
        let lightColor = UIColor(hue: CGFloat(hue / 360.0), saturation: CGFloat(lightSat), brightness: CGFloat(lightBright), alpha: 1.0)

        func uiColorToHex(_ color: UIColor) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
                let ri = Int(lround(Double(r * 255.0)))
                let gi = Int(lround(Double(g * 255.0)))
                let bi = Int(lround(Double(b * 255.0)))
                return String(format: "#%02X%02X%02X", ri, gi, bi)
            }
            return "#38BDF8"
        }

        return ExtractedColors(
            darkHex: uiColorToHex(darkColor),
            lightHex: uiColorToHex(lightColor)
        )
    }
}
#endif

@MainActor
final class PlayerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var lines: [LyricLine] = []
    @Published var currentTimeMs: Int = 0
    @Published var durationMs: Int = 0
    @Published var isPlaying: Bool = false
    #if canImport(UIKit)
    @Published var artwork: UIImage? {
        didSet {
            updateArtworkColors(from: artwork)
        }
    }
    #endif
    @Published var artworkColorDarkHex: String = "#38BDF8"
    @Published var artworkColorLightHex: String = "#0284C7"
    @Published var nowPlayingTitle: String = "No Track Playing"
    @Published var nowPlayingArtist: String = "Liquid Player"
    @Published var lyricsStatus: String = "Connect with Spotify to begin live playback."
    @Published var isLoadingLyrics: Bool = false
    @Published var errorMessage: String?
    @Published var lyricOffsetMs: Int = UserDefaults.standard.object(forKey: "LiquidPlayeriOS.lyricOffsetMs") as? Int ?? 0 {
        didSet {
            UserDefaults.standard.set(lyricOffsetMs, forKey: "LiquidPlayeriOS.lyricOffsetMs")
        }
    }
    @Published var isShuffleEnabled: Bool = false
    @Published var isSpeaker: Bool = true
    @Published var authorMetadata: String = "Liquid Player"
    @Published var lyricsSource: String? = nil
    @Published var lyricsAttribution: SpicyUploadAttribution? = nil
    @Published var lyricsSongwriters: [String] = []
    @Published var currentTrackId: String?
    @Published var favoriteTrackIDs: Set<String> = []

    // Spotify & Search state
    @Published var spotifyService = SpotifyService()
    @Published var searchResults: [SpotifyTrackItem] = []
    @Published var isSearching: Bool = false
    @Published var recentTracks: [SpotifyTrackItem] = []
    @Published var playbackQueue: [SpotifyTrackItem] = []

    // Settings
    @Published var isRomanizationEnabled: Bool = UserDefaults.standard.object(forKey: "LiquidPlayeriOS.isRomanizationEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isRomanizationEnabled, forKey: "LiquidPlayeriOS.isRomanizationEnabled")
        }
    }
    @Published var isTranslationEnabled: Bool = UserDefaults.standard.object(forKey: "LiquidPlayeriOS.isTranslationEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isTranslationEnabled, forKey: "LiquidPlayeriOS.isTranslationEnabled")
        }
    }
    @Published var backgroundStyle: PlayerBackgroundStyle = {
        if let saved = UserDefaults.standard.string(forKey: "LiquidPlayeriOS.backgroundStyle"),
           let style = PlayerBackgroundStyle(rawValue: saved) {
            return style
        }
        return .moving
    }() {
        didSet {
            UserDefaults.standard.set(backgroundStyle.rawValue, forKey: "LiquidPlayeriOS.backgroundStyle")
        }
    }
    @Published var isLyricsGlowEnabled: Bool = UserDefaults.standard.object(forKey: "LiquidPlayeriOS.isLyricsGlowEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isLyricsGlowEnabled, forKey: "LiquidPlayeriOS.isLyricsGlowEnabled")
        }
    }
    @Published var isLyricsBounceEnabled: Bool = UserDefaults.standard.object(forKey: "LiquidPlayeriOS.isLyricsBounceEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isLyricsBounceEnabled, forKey: "LiquidPlayeriOS.isLyricsBounceEnabled")
        }
    }
    @Published var lyricsFontDesign: LyricsFontDesign = {
        if let saved = UserDefaults.standard.string(forKey: "LiquidPlayeriOS.lyricsFontDesign"),
           let design = LyricsFontDesign(rawValue: saved) {
            return design
        }
        return .standard
    }() {
        didSet {
            UserDefaults.standard.set(lyricsFontDesign.rawValue, forKey: "LiquidPlayeriOS.lyricsFontDesign")
        }
    }
    @Published var lyricsFontSize: LyricsFontSize = {
        if let saved = UserDefaults.standard.string(forKey: "LiquidPlayeriOS.lyricsFontSize"),
           let size = LyricsFontSize(rawValue: saved) {
            return size
        }
        return .medium
    }() {
        didSet {
            UserDefaults.standard.set(lyricsFontSize.rawValue, forKey: "LiquidPlayeriOS.lyricsFontSize")
        }
    }

    @Published var lyricsColorHex: String = UserDefaults.standard.string(forKey: "LiquidPlayeriOS.lyricsColorHex") ?? "#FFFFFF" {
        didSet {
            UserDefaults.standard.set(lyricsColorHex, forKey: "LiquidPlayeriOS.lyricsColorHex")
            if lyricsColorHex.lowercased() != "rainbow" && lyricsColorHex.lowercased() != "artwork" {
                if voiceColors["v1"] != lyricsColorHex {
                    voiceColors["v1"] = lyricsColorHex
                }
            }
        }
    }

    var isRainbowColorMode: Bool {
        lyricsColorHex.lowercased() == "rainbow"
    }

    var isArtworkColorMode: Bool {
        lyricsColorHex.lowercased() == "artwork"
    }

    func artworkHex(for colorScheme: ColorScheme = .dark) -> String {
        colorScheme == .light ? artworkColorLightHex : artworkColorDarkHex
    }

    func artworkColor(for colorScheme: ColorScheme = .dark) -> Color {
        Color(hex: artworkHex(for: colorScheme))
    }

    func isArtworkColorBright(for colorScheme: ColorScheme = .dark) -> Bool {
        let hex = artworkHex(for: colorScheme)
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let r, g, b: Double
        if cleanHex.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        } else {
            r = 1.0; g = 1.0; b = 1.0
        }
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        return lum > 0.55
    }

    func updateArtworkColors(from image: UIImage?) {
        #if canImport(UIKit)
        guard let image = image else {
            self.artworkColorDarkHex = "#38BDF8"
            self.artworkColorLightHex = "#0284C7"
            return
        }
        Task.detached(priority: .userInitiated) {
            let colors = ArtworkColorExtractor.extractColors(from: image)
            await MainActor.run {
                self.artworkColorDarkHex = colors.darkHex
                self.artworkColorLightHex = colors.lightHex
            }
        }
        #endif
    }

    @Published var isMultiVoiceColorsEnabled: Bool = UserDefaults.standard.object(forKey: "LiquidPlayeriOS.isMultiVoiceColorsEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isMultiVoiceColorsEnabled, forKey: "LiquidPlayeriOS.isMultiVoiceColorsEnabled")
        }
    }

    @Published var voiceColors: [String: String] = {
        var base = [
            "v1": "#FFFFFF",
            "v2": "#38BDF8",
            "v3": "#C084FC",
            "v4": "#FB923C"
        ]
        if let saved = UserDefaults.standard.dictionary(forKey: "LiquidPlayeriOS.voiceColors") as? [String: String] {
            base.merge(saved) { _, new in new }
        }
        if let savedLyricHex = UserDefaults.standard.string(forKey: "LiquidPlayeriOS.lyricsColorHex"),
           savedLyricHex.lowercased() != "rainbow",
           savedLyricHex.lowercased() != "artwork" {
            base["v1"] = savedLyricHex
        }
        return base
    }() {
        didSet {
            UserDefaults.standard.set(voiceColors, forKey: "LiquidPlayeriOS.voiceColors")
        }
    }

    func resolveAdaptiveHex(_ hex: String, for colorScheme: ColorScheme) -> String {
        LyricColorPreset.resolveAdaptiveHex(hex, for: colorScheme)
    }

    static func resolveAdaptiveHex(_ hex: String, for colorScheme: ColorScheme) -> String {
        LyricColorPreset.resolveAdaptiveHex(hex, for: colorScheme)
    }

    func effectiveLyricsColorHex(for colorScheme: ColorScheme = .dark) -> String {
        if isArtworkColorMode {
            return artworkHex(for: colorScheme)
        }
        return LyricColorPreset.resolveAdaptiveHex(lyricsColorHex, for: colorScheme)
    }

    func lyricsColor(for colorScheme: ColorScheme = .dark) -> Color {
        if isRainbowColorMode {
            return LyricColorPreset.rainbowColors.first ?? (colorScheme == .light ? .black : .white)
        }
        if isArtworkColorMode {
            return artworkColor(for: colorScheme)
        }
        let rawHex = voiceColors["v1"] ?? lyricsColorHex
        return Color(hex: LyricColorPreset.resolveAdaptiveHex(rawHex, for: colorScheme))
    }

    var lyricsColor: Color {
        lyricsColor(for: .dark)
    }

    func colorForLine(index: Int, agent: String? = nil, oppositeAligned: Bool = false, colorScheme: ColorScheme = .dark) -> Color {
        if isRainbowColorMode {
            let colors = LyricColorPreset.rainbowColors
            let safeIndex = max(0, index) % colors.count
            return colors[safeIndex]
        }
        return colorForVoice(agent, oppositeAligned: oppositeAligned, colorScheme: colorScheme)
    }

    func colorForVoice(_ agent: String?, oppositeAligned: Bool = false, colorScheme: ColorScheme = .dark) -> Color {
        let defaultColor: Color
        if isArtworkColorMode {
            defaultColor = artworkColor(for: colorScheme)
        } else {
            let rawV1Hex = voiceColors["v1"] ?? (isRainbowColorMode ? "#FFFFFF" : lyricsColorHex)
            let resolvedV1Hex = LyricColorPreset.resolveAdaptiveHex(rawV1Hex, for: colorScheme)
            defaultColor = Color(hex: resolvedV1Hex)
        }

        guard isMultiVoiceColorsEnabled else {
            return defaultColor
        }

        let effectiveAgent: String? = {
            if let a = agent?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !a.isEmpty {
                return a
            }
            if oppositeAligned {
                return "v2"
            }
            return nil
        }()

        guard let raw = effectiveAgent else {
            return defaultColor
        }

        let key: String
        if raw.hasPrefix("v") {
            key = raw
        } else if let num = Int(raw) {
            key = "v\(num)"
        } else {
            key = raw
        }

        if key == "v1" || key == "1" {
            return defaultColor
        }

        if let hex = voiceColors[key], !hex.isEmpty {
            return Color(hex: LyricColorPreset.resolveAdaptiveHex(hex, for: colorScheme))
        }

        switch key {
        case "v2":
            return Color(hex: "#38BDF8")
        case "v3":
            return Color(hex: "#C084FC")
        case "v4":
            return Color(hex: "#FB923C")
        case "v5":
            return Color(hex: "#4ADE80")
        default:
            let palette = ["#38BDF8", "#C084FC", "#FB923C", "#4ADE80", "#F472B6", "#FBBF24"]
            let idx = abs(key.hashValue) % palette.count
            return Color(hex: palette[idx])
        }
    }

    func setVoiceColor(_ hex: String, for voice: String) {
        let key = voice.lowercased()
        voiceColors[key] = hex
        if key == "v1" || key == "1" {
            lyricsColorHex = hex
        }
    }

    func resetVoiceColorsToDefaults() {
        lyricsColorHex = "#FFFFFF"
        voiceColors = [
            "v1": "#FFFFFF",
            "v2": "#38BDF8",
            "v3": "#C084FC",
            "v4": "#FB923C"
        ]
    }

    var selectedTrackID: String? {
        currentTrackId
    }

    private var cancellables = Set<AnyCancellable>()
    private var interpolationTimer: Timer?
    private var lastSyncTime: Date = Date()
    private var lastSyncProgressMs: Int = 0
    private var currentLyricsTrackId: String?
    private var lyricsCache: [String: ParsedLyrics] = [:]
    private var hasPrefetchedForCurrentTrackEnding: Bool = false
    private var isPrefetchingQueue: Bool = false
    private var seekLockoutUntil: Date = .distantPast
    private var seekTargetMs: Int = 0
    private var lastSystemMusicSyncTime: Date = .distantPast

    init() {
        if let savedFavorites = UserDefaults.standard.stringArray(forKey: "LiquidPlayeriOS.favoriteTrackIDs") {
            favoriteTrackIDs = Set(savedFavorites)
        }
        bindSpotifyService()
        startInterpolationTimer()
        setupNowPlayingRemoteCommands()
        #if os(iOS)
        setupSystemMusicObserver()
        #endif
    }

    deinit {
        interpolationTimer?.invalidate()
        #if os(iOS)
        MPMusicPlayerController.systemMusicPlayer.endGeneratingPlaybackNotifications()
        #endif
    }

    // MARK: - Spotify Binding & State Sync
    private func bindSpotifyService() {
        // Forward changes from spotifyService so observing SwiftUI views invalidate and re-render immediately
        spotifyService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        spotifyService.$isAuthenticated
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authenticated in
                guard let self = self else { return }
                self.objectWillChange.send()
                if authenticated {
                    Task { @MainActor in
                        await self.spotifyService.fetchPlaybackState()
                        _ = await self.spotifyService.fetchAvailableDevices()
                        if let track = self.spotifyService.currentTrack {
                            self.updateTrackInfo(track)
                        } else if let recent = await self.spotifyService.fetchRecentlyPlayedTrack() {
                            self.spotifyService.currentTrack = recent
                            self.spotifyService.isPlaying = false
                            self.spotifyService.progressMs = 0
                            if let dur = recent.duration_ms, dur > 0 {
                                self.spotifyService.durationMs = dur
                            }
                            self.updateTrackInfo(recent)
                        }
                    }
                } else {
                    self.currentTrackId = nil
                    self.nowPlayingTitle = ""
                    self.nowPlayingArtist = ""
                    self.authorMetadata = ""
                    self.artwork = nil
                    self.lines = []
                    self.isPlaying = false
                }
            }
            .store(in: &cancellables)

        spotifyService.$currentTrack
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self = self else { return }
                if let track = track {
                    self.updateTrackInfo(track)
                }
            }
            .store(in: &cancellables)

        spotifyService.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self = self else { return }
                self.isPlaying = playing
                if playing {
                    self.lastSyncTime = Date()
                    self.lastSyncProgressMs = self.currentTimeMs
                } else {
                    self.lastSyncProgressMs = self.currentTimeMs
                }
            }
            .store(in: &cancellables)

        spotifyService.$progressMs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self = self else { return }
                let now = Date()

                // If user recently seeked, ignore stale pre-seek updates from Spotify
                if now < self.seekLockoutUntil {
                    let elapsedSinceSeek = max(0, now.timeIntervalSince(self.seekLockoutUntil.addingTimeInterval(-1.6)))
                    let expectedProgress = self.seekTargetMs + Int(elapsedSinceSeek * 1000.0)
                    if abs(progress - expectedProgress) > 1200 {
                        // Stale pre-seek report from Spotify, ignore!
                        return
                    }
                    // Spotify has caught up with our seek!
                    self.seekLockoutUntil = .distantPast
                }

                if !self.isPlaying {
                    self.lastSyncProgressMs = progress
                    self.lastSyncTime = now
                    self.currentTimeMs = progress
                } else {
                    let elapsed = now.timeIntervalSince(self.lastSyncTime)
                    let currentInterpolated = self.lastSyncProgressMs + Int(elapsed * 1000.0)
                    let diff = progress - currentInterpolated

                    if abs(diff) > 1800 {
                        // Large discrepancy (user seeked or track jumped): hard sync immediately
                        self.lastSyncProgressMs = progress
                        self.lastSyncTime = now
                        self.currentTimeMs = progress
                    } else if abs(diff) > 20 {
                        // Proportional slew: smoothly close 70% of drift per poll.
                        // Eliminates 100-300ms drift in 1-2 polls (<2s) without jarring jumps.
                        let correction = Int(Double(diff) * 0.70)
                        self.lastSyncProgressMs = currentInterpolated + correction
                        self.lastSyncTime = now
                        self.currentTimeMs = max(self.currentTimeMs, self.lastSyncProgressMs)
                    } else {
                        // Tightly locked within 20ms: lock to Spotify progress and re-anchor reference time
                        self.lastSyncProgressMs = progress
                        self.lastSyncTime = now
                    }
                }
            }
            .store(in: &cancellables)

        spotifyService.$durationMs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self = self else { return }
                if duration > 0 {
                    self.durationMs = duration
                }
            }
            .store(in: &cancellables)

        spotifyService.$isShuffleEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shuffle in
                guard let self = self else { return }
                self.isShuffleEnabled = shuffle
            }
            .store(in: &cancellables)
    }

    private func updateTrackInfo(_ track: SpotifyTrackItem) {
        nowPlayingTitle = track.name
        nowPlayingArtist = track.artistNames
        authorMetadata = track.artistNames
        durationMs = track.duration_ms ?? 0
        currentTrackId = track.id

        if !recentTracks.contains(where: { $0.id == track.id }) {
            recentTracks.insert(track, at: 0)
            if recentTracks.count > 30 {
                recentTracks.removeLast()
            }
        }

        LibraryManager.shared.recordSongPlayed(from: track)

        #if canImport(UIKit)
        if let artworkUrl = track.album?.images?.first?.url, let url = URL(string: artworkUrl) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        self.artwork = image
                    }
                }
            }
        }
        #endif

        if let trackId = track.id, trackId != currentLyricsTrackId {
            currentLyricsTrackId = trackId
            hasPrefetchedForCurrentTrackEnding = false

            // If lyrics were prefetched ahead of time, apply instantly with zero loading spinner!
            if let cached = lyricsCache[trackId] {
                self.lines = cached.lines
                self.isLoadingLyrics = false
                self.lyricsStatus = cached.lines.isEmpty ? "" : (cached.source ?? (cached.hasWordSyncedLyrics ? "Synced with Spicy Lyrics" : "Line Synced with Spicy Lyrics"))
                self.lyricsSource = cached.source
                self.lyricsAttribution = cached.attribution
                self.lyricsSongwriters = cached.songwriters
                self.authorMetadata = nowPlayingArtist
                LibraryManager.shared.saveLyrics(for: trackId, parsed: cached, track: track)
            } else {
                self.lines = []
                Task {
                    await fetchLyricsForTrack(trackId: trackId, trackTitle: track.name)
                }
            }

            // Immediately prefetch upcoming tracks while this track plays
            Task(priority: .background) {
                await self.prefetchUpcomingLyrics()
            }
        }
    }

    func fetchLyricsForTrack(trackId: String, trackTitle: String) async {
        if let cached = lyricsCache[trackId] {
            self.lines = cached.lines
            self.isLoadingLyrics = false
            self.lyricsStatus = cached.lines.isEmpty ? "" : (cached.source ?? (cached.hasWordSyncedLyrics ? "Synced with Spicy Lyrics" : "Line Synced with Spicy Lyrics"))
            self.lyricsSource = cached.source
            self.lyricsAttribution = cached.attribution
            self.lyricsSongwriters = cached.songwriters
            self.authorMetadata = nowPlayingArtist
            LibraryManager.shared.saveLyrics(for: trackId, parsed: cached)
            return
        }

        // Check if we have valid (under 30 days) saved TTML in the library
        if let validTTML = LibraryManager.shared.getValidSavedTTML(for: trackId),
           let parsed = try? TTMLLyricsParser.parse(data: Data(validTTML.utf8)),
           !parsed.lines.isEmpty {
            self.lyricsCache[trackId] = parsed
            self.lines = parsed.lines
            self.isLoadingLyrics = false
            self.lyricsStatus = parsed.hasWordSyncedLyrics ? "Loaded from Saved TTML" : "Line Synced with Saved TTML"
            self.lyricsSource = parsed.source ?? "Spicy Lyrics (Saved)"
            self.lyricsAttribution = parsed.attribution
            self.lyricsSongwriters = parsed.songwriters
            self.authorMetadata = nowPlayingArtist
            return
        }

        isLoadingLyrics = true
        lyricsStatus = "Fetching synced lyrics..."
        errorMessage = nil

        do {
            let parsed = try await SpicyLyricsService.shared.fetchLyrics(for: trackId)
            if !parsed.lines.isEmpty {
                self.lyricsCache[trackId] = parsed
                self.lines = parsed.lines
                self.isLoadingLyrics = false
                self.lyricsStatus = parsed.hasWordSyncedLyrics ? "Synced with Spicy Lyrics" : "Line Synced with Spicy Lyrics"
                self.lyricsSource = parsed.source
                self.lyricsAttribution = parsed.attribution
                self.lyricsSongwriters = parsed.songwriters
                self.authorMetadata = nowPlayingArtist
                LibraryManager.shared.saveLyrics(for: trackId, parsed: parsed)
                return
            }
        } catch {
            // Spicy Lyrics request failed
        }

        self.isLoadingLyrics = false
        self.lyricsStatus = ""
        self.lines = []
        self.lyricsSource = nil
        self.lyricsAttribution = nil
        self.lyricsSongwriters = []
        self.authorMetadata = nowPlayingArtist
        LibraryManager.shared.markNoLyrics(for: trackId)
    }

    func playLibrarySong(_ song: LibrarySong) {
        Task {
            if let track = await spotifyService.fetchTrack(id: song.id) {
                await MainActor.run {
                    self.playSpotifyTrack(track)
                }
            } else {
                let uri = song.uri ?? "spotify:track:\(song.id)"
                await spotifyService.playTrack(uri: uri)
                await MainActor.run {
                    self.currentTrackId = song.id
                    self.nowPlayingTitle = song.name
                    self.nowPlayingArtist = song.artistNames
                }
                await fetchLyricsForTrack(trackId: song.id, trackTitle: song.name)
            }
        }
    }

    func shufflePlayLibrary() {
        let songs = LibraryManager.shared.songsPlayedInLast30Days
        guard !songs.isEmpty else { return }
        if let randomSong = songs.randomElement() {
            playLibrarySong(randomSong)
        }
    }

    // MARK: - High-Frequency Smooth Interpolation
    private func startInterpolationTimer() {
        interpolationTimer?.invalidate()
        let timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.handleInterpolationTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        interpolationTimer = timer
    }

    private func handleInterpolationTick() {
        let now = Date()

        #if os(iOS)
        if now.timeIntervalSince(lastSystemMusicSyncTime) >= 0.25 {
            lastSystemMusicSyncTime = now
            syncWithSystemMusicActivityIfMatching(now: now)
        }
        #endif

        guard isPlaying else { return }
        let elapsed = now.timeIntervalSince(lastSyncTime)
        let interpolated = lastSyncProgressMs + Int(elapsed * 1000.0)
        if now >= seekLockoutUntil {
            currentTimeMs = min(max(interpolated, currentTimeMs), durationMs)
        } else {
            currentTimeMs = min(interpolated, durationMs)
        }

        // When song enters its final 35 seconds, ensure upcoming track lyrics are pre-fetched
        if durationMs > 40_000,
           currentTimeMs > (durationMs - 35_000),
           !hasPrefetchedForCurrentTrackEnding {
            hasPrefetchedForCurrentTrackEnding = true
            Task(priority: .background) {
                await self.prefetchUpcomingLyrics()
            }
        }
    }

    // MARK: - System Music Activity Sync
    #if os(iOS)
    private func setupSystemMusicObserver() {
        let player = MPMusicPlayerController.systemMusicPlayer
        player.beginGeneratingPlaybackNotifications()

        NotificationCenter.default.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncWithSystemMusicActivityIfMatching()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncWithSystemMusicActivityIfMatching()
            }
            .store(in: &cancellables)
    }

    private func syncWithSystemMusicActivityIfMatching(now: Date = Date()) {
        guard now >= seekLockoutUntil else { return }

        let player = MPMusicPlayerController.systemMusicPlayer
        guard let item = player.nowPlayingItem, doesSystemMusicItemMatch(item: item) else {
            return
        }

        let systemTimeSec = player.currentPlaybackTime
        guard !systemTimeSec.isNaN, !systemTimeSec.isInfinite, systemTimeSec >= 0 else { return }
        let systemMs = Int(systemTimeSec * 1000.0)

        let isSystemPlaying = (player.playbackState == .playing)
        if isSystemPlaying != self.isPlaying {
            self.isPlaying = isSystemPlaying
        }

        let diff = systemMs - self.currentTimeMs
        if abs(diff) > 1500 {
            // Large discrepancy (e.g. system seeked or skipped): hard sync immediately
            self.lastSyncProgressMs = systemMs
            self.lastSyncTime = now
            self.currentTimeMs = systemMs
        } else if abs(diff) > 15 {
            // Smoothly slew towards exact system time to eliminate drift
            let correction = Int(Double(diff) * 0.65)
            self.lastSyncProgressMs = self.currentTimeMs + correction
            self.lastSyncTime = now
            self.currentTimeMs = max(self.currentTimeMs, self.lastSyncProgressMs)
        } else {
            self.lastSyncProgressMs = systemMs
            self.lastSyncTime = now
        }
    }

    private func doesSystemMusicItemMatch(item: MPMediaItem) -> Bool {
        guard let itemTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !itemTitle.isEmpty else {
            return false
        }
        let currentTitle = nowPlayingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTitle.isEmpty else { return false }

        let cleanSystem = cleanSongTitle(itemTitle)
        let cleanCurrent = cleanSongTitle(currentTitle)

        if cleanSystem == cleanCurrent || cleanSystem.contains(cleanCurrent) || cleanCurrent.contains(cleanSystem) {
            // If duration is available in both, verify duration is close (within 4 seconds)
            if item.playbackDuration > 0, durationMs > 0 {
                let durationDiffMs = abs(Int(item.playbackDuration * 1000.0) - durationMs)
                if durationDiffMs < 4000 {
                    return true
                }
            }

            // Also check artist if available
            if let itemArtist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !itemArtist.isEmpty,
               !nowPlayingArtist.isEmpty {
                let cleanItemArtist = cleanSongTitle(itemArtist)
                let cleanCurrentArtist = cleanSongTitle(nowPlayingArtist)
                if cleanItemArtist == cleanCurrentArtist || cleanItemArtist.contains(cleanCurrentArtist) || cleanCurrentArtist.contains(cleanItemArtist) {
                    return true
                }
            }

            return cleanSystem == cleanCurrent
        }
        return false
    }

    private func cleanSongTitle(_ title: String) -> String {
        var t = title.lowercased()
        // Strip out parenthetical / bracketed info like "(feat. ...)", "(Remastered 2021)", "[Live]"
        t = t.replacingOccurrences(of: #"\([^\)]*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        // Keep alphanumeric characters and spaces
        t = t.filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    // MARK: - Controls
    func togglePlayback() {
        togglePlayPause()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        Task {
            await spotifyService.play()
        }
    }

    func pause() {
        isPlaying = false
        lastSyncProgressMs = currentTimeMs
        Task {
            await spotifyService.pause()
        }
    }

    func playNextTrack() {
        nextTrack()
    }

    func nextTrack() {
        Task {
            await spotifyService.next()
        }
    }

    func playPreviousTrack() {
        previousTrack()
    }

    func previousTrack() {
        Task {
            await spotifyService.previous()
        }
    }

    func seek(to positionMs: Int) {
        let now = Date()
        seekLockoutUntil = now.addingTimeInterval(1.6)
        seekTargetMs = positionMs
        lastSyncProgressMs = positionMs
        lastSyncTime = now
        currentTimeMs = positionMs
        Task {
            await spotifyService.seek(to: positionMs)
        }
    }

    func toggleShuffle() {
        Task {
            await spotifyService.toggleShuffle()
        }
    }

    func adjustLyricOffset(by deltaMs: Int) {
        lyricOffsetMs = min(max(lyricOffsetMs + deltaMs, -5000), 5000)
    }

    func resetLyricOffset() {
        lyricOffsetMs = 0
    }

    func activeLineID() -> UUID? {
        activeLineID(for: currentTimeMs)
    }

    func activeLineID(for timeMs: Int) -> UUID? {
        let nonSongwriterLines = lines.filter { !$0.isSongwriter }
        guard !nonSongwriterLines.isEmpty else { return nil }

        let leadCandidates = nonSongwriterLines.filter { !$0.isBackground }

        // 1. Inside an active sung lead line or interlude (preferring the starting/active line)
        if let current = leadCandidates.filter({ $0.startMs <= timeMs && timeMs < $0.endMs }).last {
            return current.id
        }

        // 2. If no lead line is active, check if a background line is currently active
        let bgCandidates = nonSongwriterLines.filter { $0.isBackground }
        if let currentBg = bgCandidates.filter({ $0.startMs <= timeMs && timeMs < $0.endMs }).last {
            return currentBg.id
        }

        // 3. Exact boundary match on endMs fallback
        if let current = nonSongwriterLines.filter({ $0.startMs <= timeMs && timeMs <= $0.endMs }).last {
            return current.id
        }

        // 4. In between lines: stay on the line that was most recently active / playing
        // (never rewind backwards to an earlier lead line when a background vocal just finished!)
        if let mostRecent = nonSongwriterLines.filter({ $0.startMs <= timeMs }).max(by: {
            if $0.endMs != $1.endMs {
                return $0.endMs < $1.endMs
            }
            if $0.isBackground != $1.isBackground {
                return $0.isBackground && !$1.isBackground
            }
            return $0.startMs < $1.startMs
        }) {
            return mostRecent.id
        }

        // 5. Fallback at or before start of song: guarantee the very first line of the song
        return nonSongwriterLines.first?.id
    }

    func isTrackFavorite(_ trackId: String) -> Bool {
        favoriteTrackIDs.contains(trackId)
    }

    func isCurrentTrackFavorite() -> Bool {
        guard let id = currentTrackId else { return false }
        return isTrackFavorite(id)
    }

    func toggleFavoriteCurrentTrack() {
        guard let id = currentTrackId else { return }
        toggleFavorite(id)
    }

    func toggleFavorite(_ trackId: String) {
        if favoriteTrackIDs.contains(trackId) {
            favoriteTrackIDs.remove(trackId)
        } else {
            favoriteTrackIDs.insert(trackId)
        }
        UserDefaults.standard.set(Array(favoriteTrackIDs), forKey: "LiquidPlayeriOS.favoriteTrackIDs")
    }

    private var searchDebounceTask: Task<Void, Never>?

    func searchTracks(query: String, debounce: Bool = false) {
        searchDebounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchDebounceTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard !Task.isCancelled else { return }
            let results = await spotifyService.searchTracks(query: trimmed)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }

    func playSpotifyTrack(_ track: SpotifyTrackItem) {
        guard let uri = track.uri else { return }
        updateTrackInfo(track)
        Task {
            await spotifyService.playTrack(uri: uri)
        }
    }

    func loadDirectSpotifyTrack(idOrUrl: String) {
        var cleanId = idOrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanId.contains("/track/") {
            let parts = cleanId.components(separatedBy: "/track/")
            if let lastPart = parts.last {
                cleanId = lastPart.components(separatedBy: "?").first ?? lastPart
            }
        }

        guard cleanId.count == 22 else {
            errorMessage = "Please enter a valid 22-character Spotify track ID or track URL."
            return
        }

        Task {
            if let track = await spotifyService.fetchTrack(id: cleanId) {
                await MainActor.run {
                    self.playSpotifyTrack(track)
                }
            } else {
                await MainActor.run {
                    self.currentTrackId = cleanId
                    self.nowPlayingTitle = "Spotify Track (\(cleanId.prefix(6))...)"
                }
                await fetchLyricsForTrack(trackId: cleanId, trackTitle: cleanId)
            }
        }
    }

    // MARK: - Remote Commands
    private func setupNowPlayingRemoteCommands() {
        // Use mixWithOthers and do not activate exclusive audio session,
        // ensuring opening the app never interrupts or pauses background music (Spotify, Apple Music, etc.)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTrack()
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousTrack()
            return .success
        }
    }

    // MARK: - Queue & Shuffle Helpers
    func removeTrackFromQueue(at offsets: IndexSet) {
        playbackQueue.remove(atOffsets: offsets)
    }

    func moveTrackInQueue(from source: IndexSet, to destination: Int) {
        playbackQueue.move(fromOffsets: source, toOffset: destination)
    }

    func clearQueue() {
        playbackQueue.removeAll()
    }

    func shufflePlay(tracks: [SpotifyTrackItem]? = nil) async {
        let pool = tracks ?? (!searchResults.isEmpty ? searchResults : recentTracks)
        guard let randomTrack = pool.randomElement() else { return }
        playSpotifyTrack(randomTrack)
    }

    // MARK: - Background Lyrics Prefetch Engine
    func prefetchUpcomingLyrics() async {
        guard !isPrefetchingQueue else { return }
        isPrefetchingQueue = true
        defer { isPrefetchingQueue = false }

        var trackIdsToPrefetch: [String] = []

        // 1. Tracks in manual / local playbackQueue
        for track in playbackQueue {
            if let id = track.id, lyricsCache[id] == nil, !trackIdsToPrefetch.contains(id) {
                trackIdsToPrefetch.append(id)
            }
        }

        // 2. Fetch live queue from Spotify
        if spotifyService.isAuthenticated {
            let upcoming = await spotifyService.fetchQueue()
            for track in upcoming {
                if let id = track.id, lyricsCache[id] == nil, !trackIdsToPrefetch.contains(id) {
                    trackIdsToPrefetch.append(id)
                }
            }
            if playbackQueue.isEmpty && !upcoming.isEmpty {
                self.playbackQueue = upcoming
            }
        }

        // 3. Sequential fallback from recentTracks or searchResults
        if let currentId = currentTrackId {
            if let idx = recentTracks.firstIndex(where: { $0.id == currentId }), idx + 1 < recentTracks.count {
                if let nextId = recentTracks[idx + 1].id, lyricsCache[nextId] == nil, !trackIdsToPrefetch.contains(nextId) {
                    trackIdsToPrefetch.append(nextId)
                }
            }
            if let idx = searchResults.firstIndex(where: { $0.id == currentId }), idx + 1 < searchResults.count {
                if let nextId = searchResults[idx + 1].id, lyricsCache[nextId] == nil, !trackIdsToPrefetch.contains(nextId) {
                    trackIdsToPrefetch.append(nextId)
                }
            }
        }

        // Prefetch lyrics for top 3 upcoming tracks in background
        for trackId in trackIdsToPrefetch.prefix(3) {
            guard lyricsCache[trackId] == nil else { continue }
            do {
                let parsed = try await SpicyLyricsService.shared.fetchLyrics(for: trackId)
                self.lyricsCache[trackId] = parsed
            } catch {
                // Silently ignore prefetch errors
            }
        }
    }
}

// MARK: - Library Manager
@MainActor
final class LibraryManager: ObservableObject {
    static let shared = LibraryManager()

    /// File-based storage key — no longer using UserDefaults for the library index.
    private let legacyStorageKeyV3 = "LiquidPlayeriOS.librarySongs.v3"
    private let legacyStorageKeyV2 = "LiquidPlayeriOS.librarySongs.v2"
    private let ttmlDirectoryName = "SavedTTML"

    @Published private(set) var songs: [LibrarySong] = []
    @Published var updatingTrackIds: Set<String> = []
    @Published var isBatchUpdating = false

    private init() {
        loadSongs()
        ensureTTMLDirectoryExists()
    }

    // All songs played in the last 30 days, sorted by most recently played first
    var songsPlayedInLast30Days: [LibrarySong] {
        songs.filter { $0.isPlayedInLast30Days }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    // Songs in the last 30 days that have valid (non-expired) saved TTML
    var songsWithValidTTML: [LibrarySong] {
        songsPlayedInLast30Days.filter { $0.hasTTML && !$0.isTTMLExpired }
    }

    // Songs in the last 30 days whose TTML is missing or older than 30 days (needs update)
    var songsNeedingTTMLUpdate: [LibrarySong] {
        songsPlayedInLast30Days.filter { $0.needsUpdate }
    }

    // MARK: - Record Playback
    func recordSongPlayed(
        trackId: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkUrl: String? = nil,
        durationMs: Int = 0,
        uri: String? = nil
    ) {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }

        let now = Date()

        if let index = songs.firstIndex(where: { $0.id == cleanId }) {
            var existing = songs[index]
            existing.lastPlayedAt = now
            existing.name = title
            existing.artistNames = artist
            if let album = album { existing.albumName = album }
            if let artworkUrl = artworkUrl { existing.artworkUrl = artworkUrl }
            if durationMs > 0 { existing.durationMs = durationMs }
            if let uri = uri { existing.uri = uri }

            // Move to front
            songs.remove(at: index)
            songs.insert(existing, at: 0)
        } else {
            // Check if on-disk TTML file exists from previous sessions
            let (fileContent, fileSavedAt) = loadTTMLFromDisk(for: cleanId)

            let newSong = LibrarySong(
                id: cleanId,
                name: title,
                artistNames: artist,
                albumName: album,
                artworkUrl: artworkUrl,
                durationMs: durationMs,
                uri: uri,
                lastPlayedAt: now,
                ttmlContent: fileContent,
                ttmlSavedAt: fileSavedAt,
                lyricsSource: nil,
                hasNoLyrics: nil,
                lastCheckedForLyricsAt: fileSavedAt
            )
            songs.insert(newSong, at: 0)
        }

        saveSongs()
    }

    func recordSongPlayed(from track: SpotifyTrackItem) {
        guard let id = track.id else { return }
        recordSongPlayed(
            trackId: id,
            title: track.name,
            artist: track.artistNames,
            album: track.album?.name,
            artworkUrl: track.album?.images?.first?.url,
            durationMs: track.duration_ms ?? 0,
            uri: track.uri
        )
    }

    // MARK: - Save TTML
    func saveTTML(for trackId: String, ttml: String, source: String?) {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }

        let now = Date()
        writeTTMLToDisk(for: cleanId, content: ttml)

        if let index = songs.firstIndex(where: { $0.id == cleanId }) {
            songs[index].ttmlContent = ttml
            songs[index].ttmlSavedAt = now
            songs[index].lyricsSource = source
            songs[index].hasNoLyrics = false
            songs[index].lastCheckedForLyricsAt = now
        }
        saveSongs()
    }

    func markNoLyrics(for trackId: String) {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }

        let now = Date()
        if let index = songs.firstIndex(where: { $0.id == cleanId }) {
            songs[index].hasNoLyrics = true
            songs[index].lastCheckedForLyricsAt = now
            saveSongs()
        }
    }

    func saveLyrics(for trackId: String, parsed: ParsedLyrics, track: SpotifyTrackItem? = nil) {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }

        let title = track?.name ?? songs.first(where: { $0.id == cleanId })?.name
        let artist = track?.artistNames ?? songs.first(where: { $0.id == cleanId })?.artistNames

        let ttml = TTMLExporter.export(parsed: parsed, title: title, artist: artist)
        saveTTML(for: cleanId, ttml: ttml, source: parsed.source)
    }

    // MARK: - Retrieve Saved TTML
    /// Returns valid saved TTML if it is saved and LESS than 30 days old.
    /// Returns nil if not found or if expired (older than 30 days), triggering a fresh update.
    func getValidSavedTTML(for trackId: String) -> String? {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return nil }

        if let song = songs.first(where: { $0.id == cleanId }) {
            // If indexed, check expiration
            guard song.hasTTML, !song.isTTMLExpired else {
                return nil
            }

            // In-memory content is available (freshly written this session)
            if let content = song.ttmlContent, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
        }

        // Fallback: load directly from the on-disk .ttml file if valid (< 30 days old)
        let (diskContent, modDate) = loadTTMLFromDisk(for: cleanId)
        if let content = diskContent, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let date = modDate {
                if Date().timeIntervalSince(date) < 30 * 24 * 3600 {
                    return content
                }
            } else {
                return content
            }
        }
        return nil
    }

    // MARK: - Refresh / Update TTML
    func updateTTML(for trackId: String) async -> Bool {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return false }

        updatingTrackIds.insert(cleanId)
        defer { updatingTrackIds.remove(cleanId) }

        do {
            let parsed = try await SpicyLyricsService.shared.fetchLyrics(for: cleanId)
            if parsed.lines.isEmpty {
                markNoLyrics(for: cleanId)
                return true
            }
            let song = songs.first(where: { $0.id == cleanId })
            let ttml = TTMLExporter.export(parsed: parsed, title: song?.name, artist: song?.artistNames)
            saveTTML(for: cleanId, ttml: ttml, source: parsed.source)
            return true
        } catch {
            markNoLyrics(for: cleanId)
            return false
        }
    }

    // Update all songs played in the last 30 days whose saved TTML is older than 30 days
    func updateAllExpired() async {
        let expired = songsNeedingTTMLUpdate
        guard !expired.isEmpty else { return }

        isBatchUpdating = true
        defer { isBatchUpdating = false }

        for song in expired {
            _ = await updateTTML(for: song.id)
            // Polite delay between requests
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    func deleteSong(id: String) {
        songs.removeAll { $0.id == id }
        deleteTTMLFromDisk(for: id)
        saveSongs()
    }

    // MARK: - Persistence (file-based — NOT UserDefaults)

    /// URL for the library index JSON file, stored in Documents/.
    private var libraryIndexURL: URL {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return docs.appendingPathComponent("liquidplayer_library.json")
    }

    private func saveSongs() {
        // Strip ttmlContent before writing — TTML already lives in SavedTTML/*.ttml files.
        // Keeping full TTML in the index was causing the 5+ MB UserDefaults overflow.
        let slim = songs.map { song -> LibrarySong in
            var s = song
            s.ttmlContent = nil
            return s
        }
        if let encoded = try? JSONEncoder().encode(slim) {
            try? encoded.write(to: libraryIndexURL, options: .atomic)
        }
    }

    private func loadSongs() {
        // 1. Try file-based storage (new primary path)
        if let data = try? Data(contentsOf: libraryIndexURL),
           let decoded = try? JSONDecoder().decode([LibrarySong].self, from: data) {
            self.songs = decoded
            return
        }

        // 2. Migrate from UserDefaults v3 (old path that caused the overflow)
        if let data = UserDefaults.standard.data(forKey: legacyStorageKeyV3),
           let decoded = try? JSONDecoder().decode([LibrarySong].self, from: data) {
            self.songs = decoded.map { song in
                var s = song
                s.ttmlContent = nil   // don't carry TTML forward into new file-based store
                return s
            }
            saveSongs()
            // Clean up both old UserDefaults keys to reclaim the 5+ MB
            UserDefaults.standard.removeObject(forKey: legacyStorageKeyV3)
            UserDefaults.standard.removeObject(forKey: legacyStorageKeyV2)
            UserDefaults.standard.synchronize()
            return
        }

        // 3. Migrate from UserDefaults v2 (even older path)
        if let oldData = UserDefaults.standard.data(forKey: legacyStorageKeyV2),
           let oldDecoded = try? JSONDecoder().decode([LibrarySong].self, from: oldData) {
            self.songs = oldDecoded.map { song in
                var s = song
                s.ttmlContent = nil
                s.ttmlSavedAt = nil
                return s
            }
            saveSongs()
            try? FileManager.default.removeItem(at: ttmlDirectoryURL)
            ensureTTMLDirectoryExists()
            UserDefaults.standard.removeObject(forKey: legacyStorageKeyV2)
            UserDefaults.standard.synchronize()
        }
    }

    // MARK: - On-Disk TTML Files
    private var ttmlDirectoryURL: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent(ttmlDirectoryName, isDirectory: true)
    }

    private func ensureTTMLDirectoryExists() {
        let dir = ttmlDirectoryURL
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func ttmlFileURL(for trackId: String) -> URL {
        ttmlDirectoryURL.appendingPathComponent("\(trackId).ttml")
    }

    private func writeTTMLToDisk(for trackId: String, content: String) {
        ensureTTMLDirectoryExists()
        let fileUrl = ttmlFileURL(for: trackId)
        try? content.write(to: fileUrl, atomically: true, encoding: .utf8)
    }

    private func loadTTMLFromDisk(for trackId: String) -> (String?, Date?) {
        let fileUrl = ttmlFileURL(for: trackId)
        guard FileManager.default.fileExists(atPath: fileUrl.path),
              let content = try? String(contentsOf: fileUrl, encoding: .utf8) else {
            return (nil, nil)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileUrl.path)
        let modDate = attributes?[.modificationDate] as? Date
        return (content, modDate)
    }

    private func deleteTTMLFromDisk(for trackId: String) {
        let fileUrl = ttmlFileURL(for: trackId)
        try? FileManager.default.removeItem(at: fileUrl)
    }
}


