import SwiftUI

// MARK: - Special Word Effect Types

public enum WordSpecialEffect: String, CaseIterable, Equatable {
    case fire
    case christmas
    case night
    case sun
    case rainbow
    case heart
    case ocean
    case diamond

    public var displayName: String {
        switch self {
        case .fire: return "Fire (Flames)"
        case .christmas: return "Christmas & Cold (Snowfall)"
        case .night: return "Night (Sparkles)"
        case .sun: return "Sun & Summer (Glowing Yellow)"
        case .rainbow: return "Rainbow (Multi-color Letters)"
        case .heart: return "Heart (Pulsing Red)"
        case .ocean: return "Ocean (Aquatic Waves)"
        case .diamond: return "Diamond (Sparkling Crystal)"
        }
    }

    public var singleColor: Color? {
        switch self {
        case .christmas: return Color(red: 0.58, green: 0.88, blue: 0.98)
        case .night: return Color(red: 0.38, green: 0.58, blue: 1.0)
        case .sun: return Color(red: 1.0, green: 0.88, blue: 0.12)
        case .heart: return Color(red: 0.98, green: 0.18, blue: 0.36)
        case .diamond: return Color(red: 0.72, green: 0.93, blue: 1.0)
        default: return nil
        }
    }

    public var glowColor: Color {
        switch self {
        case .fire: return Color(red: 1.0, green: 0.45, blue: 0.0)
        case .christmas: return Color(red: 0.45, green: 0.85, blue: 1.0)
        case .night: return Color(red: 0.35, green: 0.55, blue: 1.0)
        case .sun: return Color(red: 1.0, green: 0.85, blue: 0.05)
        case .rainbow: return Color(red: 0.75, green: 0.30, blue: 0.95)
        case .heart: return Color(red: 0.98, green: 0.20, blue: 0.38)
        case .ocean: return Color(red: 0.10, green: 0.68, blue: 0.90)
        case .diamond: return Color(red: 0.60, green: 0.88, blue: 1.0)
        }
    }
}

// MARK: - Word Effects Lookup

public enum SpecialWordEffectsLookup {
    public static func effect(for rawText: String) -> WordSpecialEffect? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // Punctuation trimming (keep hyphens separate to avoid split-word distortion)
        let punctuationToTrim = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-–—"))
        let cleaned = trimmed
            .trimmingCharacters(in: punctuationToTrim)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "–", with: "")
            .replacingOccurrences(of: "—", with: "")

        switch cleaned {
        case "fire", "fires", "flame", "flames", "flaming", "blaze", "blazes", "blazing",
             "burning", "burn", "burns", "burned", "burnt", "fireplace", "fireplaces",
             "fireside", "campfire", "campfires", "bonfire", "bonfires", "firework", "fireworks",
             "spark", "sparks", "sparking":
            return .fire
        case "christmas", "xmas", "snow", "snows", "snowing", "snowy", "snowflake", "snowflakes",
             "snowman", "snowmen", "winter", "yuletide", "santa", "reindeer", "holiday", "holidays",
             "cold", "colds", "colder", "coldest", "freeze", "freezes", "freezing", "froze", "frozen",
             "chill", "chills", "chilly", "chillin", "chillin'", "frost", "frosty", "ice", "icy":
            return .christmas
        case "night", "nights", "midnight", "star", "stars", "starry", "starlight",
             "moon", "moonlight", "moons", "twilight", "goodnight", "goodnights", "tonight", "nighttime":
            return .night
        case "sun", "sunshine", "sunny", "sunlight", "sunrise", "sunset", "solar",
             "summer", "summers", "summertime":
            return .sun
        case "rainbow", "rainbows":
            return .rainbow
        case "heart", "hearts", "love", "loving", "loved", "lover", "lovers", "sweetheart",
             "kiss", "kisses", "kissing", "kissed", "smooch", "xoxo", "kissin", "kissin\'":
            return .heart
        case "ocean", "sea", "wave", "waves", "water", "waters", "tsunami", "rain", "rains", "raining", "rainy", "raindrop", "raindrops":
            return .ocean
        case "diamond", "diamonds":
            return .diamond
        default:
            return nil
        }
    }
}

// MARK: - Rainbow Colors Palette

public enum RainbowLetterColors {
    public static let palette: [Color] = [
        Color(red: 0.95, green: 0.25, blue: 0.25), // Red
        Color(red: 1.0, green: 0.55, blue: 0.15),  // Orange
        Color(red: 1.0, green: 0.85, blue: 0.12),  // Yellow
        Color(red: 0.22, green: 0.82, blue: 0.38), // Green
        Color(red: 0.05, green: 0.78, blue: 0.92), // Cyan
        Color(red: 0.25, green: 0.55, blue: 0.98), // Blue
        Color(red: 0.68, green: 0.35, blue: 0.95)  // Purple
    ]

    public static func color(for index: Int) -> Color {
        palette[index % palette.count]
    }

    private static var cache: [String: AttributedString] = [:]
    private static let lock = NSLock()

    public static func attributed(for text: String) -> AttributedString {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[text] {
            return cached
        }
        var attributed = AttributedString(text)
        var charIndex = 0
        for index in attributed.characters.indices {
            let c = color(for: charIndex)
            attributed[index...index].foregroundColor = c
            charIndex += 1
        }
        cache[text] = attributed
        return attributed
    }
}

// MARK: - High-Performance Particle Views (Synchronized to Playback Time)

struct FireFlamesParticleView: View {
    let currentTimeMs: Int

    var body: some View {
        let time = Double(currentTimeMs) / 1000.0
        Canvas { context, size in
            let w = size.width
            let h = size.height

            let sparks: [(xRatio: Double, speed: Double, seed: Double)] = [
                (0.25, 1.4, 0.0),
                (0.55, 1.8, 1.4),
                (0.80, 1.5, 2.8)
            ]

            for spark in sparks {
                let cycle = (time * spark.speed + spark.seed).truncatingRemainder(dividingBy: 1.0)
                let y = h - (cycle * (h + 16.0))
                let xJitter = sin(time * 3.5 + spark.seed * 5.0) * 2.5
                let x = (w * spark.xRatio) + xJitter
                let sparkSize = max(2.0, 4.0 * (1.0 - cycle))
                let opacity = max(0.0, min(1.0, sin(cycle * .pi)))

                let color: Color = cycle < 0.4
                    ? Color(red: 1.0, green: 0.90, blue: 0.3, opacity: opacity * 0.9)
                    : Color(red: 1.0, green: 0.42, blue: 0.05, opacity: opacity * 0.85)

                let rect = CGRect(x: x - sparkSize / 2, y: y - sparkSize / 2, width: sparkSize, height: sparkSize * 1.3)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}

struct ChristmasSnowflakesParticleView: View {
    let currentTimeMs: Int

    var body: some View {
        let time = Double(currentTimeMs) / 1000.0
        Canvas { context, size in
            let w = size.width
            let h = size.height

            let flakes: [(xRatio: Double, speed: Double, seed: Double, radius: Double)] = [
                (0.20, 0.50, 0.2, 2.8),
                (0.52, 0.60, 1.8, 3.2),
                (0.82, 0.45, 3.4, 2.4)
            ]

            for flake in flakes {
                let cycle = (time * flake.speed + flake.seed).truncatingRemainder(dividingBy: 1.0)
                let y = -8.0 + cycle * (h + 16.0)
                let sway = sin(time * 2.0 + flake.seed * 4.0) * 3.5
                let x = (w * flake.xRatio) + sway
                let opacity = max(0.0, min(1.0, sin(cycle * .pi)))

                let rect = CGRect(x: x - flake.radius / 2, y: y - flake.radius / 2, width: flake.radius, height: flake.radius)
                context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.88, green: 0.96, blue: 1.0, opacity: opacity * 0.85)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct NightSparklesParticleView: View {
    let currentTimeMs: Int

    var body: some View {
        let time = Double(currentTimeMs) / 1000.0
        Canvas { context, size in
            let w = size.width
            let h = size.height

            let sparkles: [(xRatio: Double, yRatio: Double, speed: Double, seed: Double)] = [
                (0.20, 0.20, 1.2, 0.0),
                (0.50, 0.75, 1.5, 1.7),
                (0.80, 0.25, 1.1, 3.2)
            ]

            for sp in sparkles {
                let cycle = (time * sp.speed + sp.seed).truncatingRemainder(dividingBy: 1.0)
                let opacity = max(0.0, sin(cycle * .pi))
                let scale = max(0.1, sin(cycle * .pi)) * 4.0
                let x = w * sp.xRatio
                let y = h * sp.yRatio

                var starPath = Path()
                starPath.move(to: CGPoint(x: x, y: y - scale))
                starPath.addLine(to: CGPoint(x: x, y: y + scale))
                starPath.move(to: CGPoint(x: x - scale, y: y))
                starPath.addLine(to: CGPoint(x: x + scale, y: y))

                context.stroke(starPath, with: .color(Color(red: 0.85, green: 0.92, blue: 1.0, opacity: opacity * 0.95)), lineWidth: 1.2)
            }
        }
        .allowsHitTesting(false)
    }
}

struct DiamondSparklesParticleView: View {
    let currentTimeMs: Int

    var body: some View {
        let time = Double(currentTimeMs) / 1000.0
        Canvas { context, size in
            let w = size.width
            let h = size.height

            let glints: [(xRatio: Double, yRatio: Double, speed: Double, seed: Double)] = [
                (0.18, 0.25, 1.3, 0.0),
                (0.48, 0.80, 1.6, 1.5),
                (0.82, 0.20, 1.2, 2.8),
                (0.70, 0.70, 1.4, 4.1)
            ]

            for gl in glints {
                let cycle = (time * gl.speed + gl.seed).truncatingRemainder(dividingBy: 1.0)
                let opacity = max(0.0, sin(cycle * .pi))
                let scale = max(0.1, sin(cycle * .pi)) * 4.5
                let x = w * gl.xRatio
                let y = h * gl.yRatio

                var starPath = Path()
                starPath.move(to: CGPoint(x: x, y: y - scale))
                starPath.addLine(to: CGPoint(x: x, y: y + scale))
                starPath.move(to: CGPoint(x: x - scale, y: y))
                starPath.addLine(to: CGPoint(x: x + scale, y: y))

                // Sparkling brilliant diamond glint color
                context.stroke(
                    starPath,
                    with: .color(Color(red: 0.82, green: 0.96, blue: 1.0, opacity: opacity * 0.95)),
                    lineWidth: 1.3
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Special Word Effect Token View

public struct SpecialWordEffectTokenView: View {
    public let text: String
    public let effect: WordSpecialEffect
    public let currentTimeMs: Int
    public let isLineActive: Bool
    public let isWordActive: Bool
    public let isWordSung: Bool
    public let progress: Double
    public let inactiveColor: Color
    public let font: Font
    public let isGlowEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(
        text: String,
        effect: WordSpecialEffect,
        currentTimeMs: Int = 0,
        isLineActive: Bool,
        isWordActive: Bool,
        isWordSung: Bool,
        progress: Double = 0.0,
        inactiveColor: Color,
        font: Font,
        isGlowEnabled: Bool = true
    ) {
        self.text = text
        self.effect = effect
        self.currentTimeMs = currentTimeMs
        self.isLineActive = isLineActive
        self.isWordActive = isWordActive
        self.isWordSung = isWordSung
        self.progress = progress
        self.inactiveColor = inactiveColor
        self.font = font
        self.isGlowEnabled = isGlowEnabled
    }

    private var inactiveBaseText: some View {
        Text(text)
            .font(font)
            .foregroundStyle(inactiveColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    public var body: some View {
        if let singleColor = effect.singleColor {
            // HIGH-PERFORMANCE ZERO-MASK PIPELINE FOR SINGLE-COLOR EFFECTS (Christmas, Night, Sun, Heart)
            singleColorWordBody(singleColor: singleColor)
        } else {
            // MULTI-COLOR / GRADIENT EFFECTS (Fire, Rainbow, Ocean)
            multiColorWordBody
        }
    }

    // MARK: - Single-Color Pipeline (Ultra-fast, Zero Masking, Zero Clipping)

    @ViewBuilder
    private func singleColorWordBody(singleColor: Color) -> some View {
        let glowColor = effect.glowColor

        if !isLineActive {
            if isWordSung {
                // Past lines: retains theme color with soft ambient glow
                Text(text)
                    .font(font)
                    .foregroundStyle(singleColor.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .shadow(
                        color: isGlowEnabled ? glowColor.opacity(0.25) : Color.clear,
                        radius: isGlowEnabled ? 5 : 0,
                        x: 0, y: 0
                    )
            } else {
                inactiveBaseText
            }
        } else if !isWordActive && !isWordSung {
            // Un-sung word on active line
            inactiveBaseText
        } else if isWordSung {
            // Sung word on active line: stays fully lit with full glow and gentle particles until line ends
            Text(text)
                .font(font)
                .foregroundStyle(singleColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .shadow(
                    color: isGlowEnabled ? glowColor.opacity(0.80) : Color.clear,
                    radius: isGlowEnabled ? 9 : 0,
                    x: 0, y: 0
                )
                .overlay {
                    if isGlowEnabled {
                        activeParticleOverlay
                    }
                }
        } else {
            // Active singing word: smooth progressive karaoke wipe wave matching the native Metal shader pipeline!
            let p = -0.15 + 1.30 * progress
            let stop1 = max(0.0, min(1.0, p))
            let stop2 = min(1.0, max(stop1 + 0.05, p + 0.18))
            let glowFactor = SpicySplines.glowSpline.at(progress)
            let glowOpacity = isGlowEnabled ? (glowFactor * 0.85) : 0.0

            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: singleColor, location: stop1),
                            .init(color: inactiveColor, location: stop2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(
                    color: isGlowEnabled ? glowColor.opacity(glowOpacity) : Color.clear,
                    radius: isGlowEnabled ? 9 : 0,
                    x: 0, y: 0
                )
                .overlay {
                    if isGlowEnabled {
                        activeParticleOverlay
                    }
                }
        }
    }

    // MARK: - Multi-Color / Gradient Pipeline (Fire, Rainbow, Ocean)

    @ViewBuilder
    private var multiColorWordBody: some View {
        let glowColor = effect.glowColor

        if !isLineActive {
            if isWordSung {
                styledWordFill
                    .opacity(0.85)
                    .shadow(
                        color: isGlowEnabled ? glowColor.opacity(0.25) : Color.clear,
                        radius: isGlowEnabled ? 5 : 0,
                        x: 0, y: 0
                    )
            } else {
                inactiveBaseText
            }
        } else if !isWordActive && !isWordSung {
            inactiveBaseText
        } else if isWordSung {
            styledWordFill
                .shadow(
                    color: isGlowEnabled ? glowColor.opacity(0.80) : Color.clear,
                    radius: isGlowEnabled ? 9 : 0,
                    x: 0, y: 0
                )
                .overlay {
                    if isGlowEnabled {
                        activeParticleOverlay
                    }
                }
        } else {
            let p = -0.15 + 1.30 * progress
            let stop1 = max(0.0, min(1.0, p))
            let stop2 = min(1.0, max(stop1 + 0.05, p + 0.18))
            let glowFactor = SpicySplines.glowSpline.at(progress)
            let glowOpacity = isGlowEnabled ? (glowFactor * 0.85) : 0.0

            ZStack {
                inactiveBaseText

                styledWordFill
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: stop1),
                                .init(color: .clear, location: stop2)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .shadow(
                color: isGlowEnabled ? glowColor.opacity(glowOpacity) : Color.clear,
                radius: isGlowEnabled ? 9 : 0,
                x: 0, y: 0
            )
            .overlay {
                if isGlowEnabled {
                    activeParticleOverlay
                }
            }
        }
    }

    // MARK: - Active Particle Overlay (Synchronized & Unclipped)

    @ViewBuilder
    private var activeParticleOverlay: some View {
        switch effect {
        case .fire:
            FireFlamesParticleView(currentTimeMs: currentTimeMs)
                .padding(.vertical, -10)
                .padding(.horizontal, 0)
                .allowsHitTesting(false)
        case .christmas:
            ChristmasSnowflakesParticleView(currentTimeMs: currentTimeMs)
                .padding(.vertical, -10)
                .padding(.horizontal, 0)
                .allowsHitTesting(false)
        case .night:
            NightSparklesParticleView(currentTimeMs: currentTimeMs)
                .padding(.vertical, -8)
                .padding(.horizontal, 0)
                .allowsHitTesting(false)
        case .diamond:
            DiamondSparklesParticleView(currentTimeMs: currentTimeMs)
                .padding(.vertical, -8)
                .padding(.horizontal, 0)
                .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }

    // MARK: - Styled Word Fills

    @ViewBuilder
    private var styledWordFill: some View {
        switch effect {
        case .rainbow:
            rainbowFill
        case .fire:
            fireFill
        case .ocean:
            oceanFill
        case .christmas:
            if let color = effect.singleColor {
                Text(text).font(font).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(color)
            }
        case .night:
            if let color = effect.singleColor {
                Text(text).font(font).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(color)
            }
        case .sun:
            if let color = effect.singleColor {
                Text(text).font(font).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(color)
            }
        case .heart:
            if let color = effect.singleColor {
                Text(text).font(font).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(color)
            }
        case .diamond:
            if let color = effect.singleColor {
                Text(text).font(font).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(color)
            }
        }
    }

    private var rainbowFill: some View {
        Text(RainbowLetterColors.attributed(for: text))
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var fireFill: some View {
        let flameColors = [
            Color(red: 1.0, green: 0.15, blue: 0.0),
            Color(red: 1.0, green: 0.55, blue: 0.0),
            Color(red: 1.0, green: 0.90, blue: 0.15)
        ]

        return Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                LinearGradient(colors: flameColors, startPoint: .bottom, endPoint: .top)
            )
    }

    private var oceanFill: some View {
        let seaColors = [
            Color(red: 0.05, green: 0.72, blue: 0.88),
            Color(red: 0.20, green: 0.50, blue: 0.98)
        ]

        return Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                LinearGradient(colors: seaColors, startPoint: .leading, endPoint: .trailing)
            )
    }
}
