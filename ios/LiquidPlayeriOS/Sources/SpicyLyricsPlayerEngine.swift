import SwiftUI

// MARK: - Natural Cubic Spline (matching AMLL-TTML-TOOL math.ts)

final class CubicSpline {
    private let a: [Double]
    private var b: [Double] = []
    private var c: [Double] = []
    private var d: [Double] = []
    private let xs: [Double]

    init(points: [(Double, Double)]) {
        self.xs = points.map { $0.0 }
        self.a = points.map { $0.1 }
        let n = points.count - 1
        guard n > 0 else { return }

        var h = [Double](repeating: 0, count: n)
        for i in 0..<n {
            h[i] = xs[i + 1] - xs[i]
        }

        var alpha = [Double](repeating: 0, count: n)
        for i in 1..<n {
            alpha[i] = (3.0 / h[i]) * (a[i + 1] - a[i]) - (3.0 / h[i - 1]) * (a[i] - a[i - 1])
        }

        var l = [Double](repeating: 0, count: n + 1)
        var mu = [Double](repeating: 0, count: n + 1)
        var z = [Double](repeating: 0, count: n + 1)
        l[0] = 1.0
        for i in 1..<n {
            l[i] = 2.0 * (xs[i + 1] - xs[i - 1]) - h[i - 1] * mu[i - 1]
            mu[i] = h[i] / l[i]
            z[i] = (alpha[i] - h[i - 1] * z[i - 1]) / l[i]
        }
        l[n] = 1.0
        c = [Double](repeating: 0, count: n + 1)
        b = [Double](repeating: 0, count: n)
        d = [Double](repeating: 0, count: n)

        for j in stride(from: n - 1, through: 0, by: -1) {
            c[j] = z[j] - mu[j] * c[j + 1]
            b[j] = (a[j + 1] - a[j]) / h[j] - (h[j] * (c[j + 1] + 2.0 * c[j])) / 3.0
            d[j] = (c[j + 1] - c[j]) / (3.0 * h[j])
        }
    }

    func at(_ x: Double) -> Double {
        guard xs.count > 1 else { return a.first ?? 0 }
        if x <= xs[0] { return a[0] }
        if x >= xs[xs.count - 1] { return a[a.count - 1] }

        var i = xs.count - 2
        for j in 0..<xs.count - 1 {
            if x < xs[j + 1] {
                i = j
                break
            }
        }
        let dx = x - xs[i]
        return a[i] + b[i] * dx + c[i] * dx * dx + d[i] * dx * dx * dx
    }
}

// MARK: - Spline Curves from Spicy Lyrics (AMLL-TTML-TOOL)

enum SpicySplines {
    static let scaleSpline = CubicSpline(points: [
        (0.0, 1.0),
        (0.45, 1.065),
        (1.0, 1.0)
    ])

    static let letterScaleSpline = CubicSpline(points: [
        (0.0, 0.95),
        (0.7, 1.175),
        (1.0, 1.0)
    ])

    static let ySpline = CubicSpline(points: [
        (0.0, 0.0),
        (0.45, -1.0 / 50.0),
        (1.0, 0.0)
    ])

    static let letterYSpline = CubicSpline(points: [
        (0.0, 0.01),
        (0.9, -1.0 / 56.0),
        (1.0, 0.0)
    ])

    static let glowSpline = CubicSpline(points: [
        (0.0, 0.0),
        (0.15, 1.0),
        (0.6, 1.0),
        (1.0, 0.0)
    ])

    static let dotScaleSpline = CubicSpline(points: [
        (0.0, 0.75),
        (0.35, 1.12),
        (0.7, 1.0),
        (1.0, 1.0)
    ])

    static let dotYSpline = CubicSpline(points: [
        (0.0, 0.0),
        (0.35, -1.0),
        (0.75, 0.0),
        (1.0, 0.0)
    ])

    static let dotGlowSpline = CubicSpline(points: [
        (0.0, 0.0),
        (0.35, 1.0),
        (0.7, 0.25),
        (1.0, 0.25)
    ])

    static let dotOpacitySpline = CubicSpline(points: [
        (0.0, 0.35),
        (0.35, 1.0),
        (0.6, 1.0),
        (1.0, 1.0)
    ])
}

// MARK: - Word & Syllable Token Grouping

// MARK: - Syllable Token View (Progressive Gradient Fill & Bounce Pop)

// MARK: - Color Words Lookup

enum ColorWordsLookup {
    static let colorMap: [String: Color] = [
        "red": Color(red: 0.95, green: 0.22, blue: 0.22),
        "reds": Color(red: 0.95, green: 0.22, blue: 0.22),
        "redder": Color(red: 0.95, green: 0.22, blue: 0.22),
        "reddest": Color(red: 0.95, green: 0.22, blue: 0.22),
        "crimson": Color(red: 0.86, green: 0.08, blue: 0.24),
        "scarlet": Color(red: 1.0, green: 0.14, blue: 0.0),
        "ruby": Color(red: 0.88, green: 0.07, blue: 0.37),
        "rose": Color(red: 1.0, green: 0.30, blue: 0.50),
        "pink": Color(red: 1.0, green: 0.42, blue: 0.63),
        "pinks": Color(red: 1.0, green: 0.42, blue: 0.63),
        "pinker": Color(red: 1.0, green: 0.42, blue: 0.63),
        "pinkest": Color(red: 1.0, green: 0.42, blue: 0.63),
        "magenta": Color(red: 1.0, green: 0.0, blue: 1.0),
        "fuchsia": Color(red: 1.0, green: 0.0, blue: 1.0),
        "orange": Color(red: 1.0, green: 0.55, blue: 0.0),
        "oranges": Color(red: 1.0, green: 0.55, blue: 0.0),
        "amber": Color(red: 1.0, green: 0.75, blue: 0.0),
        "coral": Color(red: 1.0, green: 0.50, blue: 0.31),
        "peach": Color(red: 1.0, green: 0.80, blue: 0.64),
        "yellow": Color(red: 1.0, green: 0.88, blue: 0.10),
        "yellows": Color(red: 1.0, green: 0.88, blue: 0.10),
        "yellower": Color(red: 1.0, green: 0.88, blue: 0.10),
        "yellowest": Color(red: 1.0, green: 0.88, blue: 0.10),
        "gold": Color(red: 1.0, green: 0.84, blue: 0.0),
        "golden": Color(red: 1.0, green: 0.84, blue: 0.0),
        "green": Color(red: 0.20, green: 0.82, blue: 0.38),
        "greens": Color(red: 0.20, green: 0.82, blue: 0.38),
        "greener": Color(red: 0.20, green: 0.82, blue: 0.38),
        "greenest": Color(red: 0.20, green: 0.82, blue: 0.38),
        "lime": Color(red: 0.65, green: 0.95, blue: 0.20),
        "emerald": Color(red: 0.31, green: 0.78, blue: 0.47),
        "teal": Color(red: 0.0, green: 0.72, blue: 0.72),
        "cyan": Color(red: 0.0, green: 0.88, blue: 1.0),
        "aqua": Color(red: 0.0, green: 0.95, blue: 1.0),
        "turquoise": Color(red: 0.25, green: 0.88, blue: 0.82),
        "blue": Color(red: 0.20, green: 0.60, blue: 1.0),
        "blues": Color(red: 0.20, green: 0.60, blue: 1.0),
        "bluer": Color(red: 0.20, green: 0.60, blue: 1.0),
        "bluest": Color(red: 0.20, green: 0.60, blue: 1.0),
        "navy": Color(red: 0.15, green: 0.35, blue: 0.80),
        "sapphire": Color(red: 0.06, green: 0.38, blue: 0.85),
        "indigo": Color(red: 0.35, green: 0.25, blue: 0.90),
        "violet": Color(red: 0.65, green: 0.28, blue: 0.95),
        "violets": Color(red: 0.65, green: 0.28, blue: 0.95),
        "purple": Color(red: 0.68, green: 0.32, blue: 0.95),
        "purples": Color(red: 0.68, green: 0.32, blue: 0.95),
        "lavender": Color(red: 0.78, green: 0.65, blue: 0.98),
        "lilac": Color(red: 0.80, green: 0.58, blue: 0.90),
        "brown": Color(red: 0.65, green: 0.42, blue: 0.25),
        "browns": Color(red: 0.65, green: 0.42, blue: 0.25),
        "browner": Color(red: 0.65, green: 0.42, blue: 0.25),
        "brownest": Color(red: 0.65, green: 0.42, blue: 0.25),
        "maroon": Color(red: 0.60, green: 0.10, blue: 0.15),
        "burgundy": Color(red: 0.55, green: 0.05, blue: 0.20),
        "bronze": Color(red: 0.80, green: 0.50, blue: 0.20),
        "white": Color.white,
        "whiter": Color.white,
        "whitest": Color.white,
        "black": Color(white: 0.15),
        "blacker": Color(white: 0.15),
        "blackest": Color(white: 0.15),
        "gray": Color(white: 0.65),
        "grey": Color(white: 0.65),
        "grayer": Color(white: 0.65),
        "greyer": Color(white: 0.65),
        "grayest": Color(white: 0.65),
        "greyest": Color(white: 0.65),
        "silver": Color(red: 0.75, green: 0.78, blue: 0.85),
        "platinum": Color(red: 0.88, green: 0.90, blue: 0.95),
        "diamond": Color(red: 0.72, green: 0.93, blue: 1.0),
        "diamonds": Color(red: 0.72, green: 0.93, blue: 1.0)
    ]

    static func color(for rawText: String) -> Color? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // If the token explicitly starts or ends with a hyphen or dash, it's a syllable fragment
        if trimmed.hasPrefix("-") || trimmed.hasSuffix("-") ||
           trimmed.hasPrefix("–") || trimmed.hasSuffix("–") ||
           trimmed.hasPrefix("—") || trimmed.hasSuffix("—") {
            return nil
        }

        // Trim enclosing punctuation (quotes, parentheses, brackets, periods, commas, etc.)
        let punctuationToTrim = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-–—"))
        let cleaned = trimmed
            .trimmingCharacters(in: punctuationToTrim)
            .lowercased()

        if let direct = colorMap[cleaned] {
            return direct
        }

        // If syllables were joined with hyphens/dashes (e.g. "yel-low" -> "yellow"),
        // check if removing internal hyphens forms a complete color word.
        let withoutHyphens = cleaned
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "–", with: "")
            .replacingOccurrences(of: "—", with: "")
        if !withoutHyphens.isEmpty, let dehyphenated = colorMap[withoutHyphens] {
            return dehyphenated
        }

        return nil
    }
}

// MARK: - Syllable Token View (Progressive Gradient Fill & Bounce Pop)

struct SpicySyllableTokenView: View {
    let word: LyricWord
    let currentTimeMs: Int
    let isBackground: Bool
    let isLineActive: Bool
    let isLinePast: Bool
    var isGlowEnabled: Bool = true
    var isBounceEnabled: Bool = true
    var activeColor: Color = .white
    var isExactColorEnabled: Bool = true
    var isSpecialWordEffectsEnabled: Bool = true
    var groupText: String? = nil
    var matchedColorWord: Color? = nil
    var matchedSpecialEffect: WordSpecialEffect? = nil
    var tokenFont: Font? = nil
    var isGroupSplit: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var isSyllableSplit: Bool {
        isGroupSplit || word.isPartOfWord || (groupText != nil && groupText != cleanText)
    }

    var body: some View {
        if word.isLetterGroup && !word.letters.isEmpty {
            letterGroupView
        } else {
            singleSyllableView
        }
    }

    private var cleanText: String {
        word.text.trimmingCharacters(in: .whitespaces)
    }

    private var specialEffect: WordSpecialEffect? {
        guard isSpecialWordEffectsEnabled else { return nil }
        if let effect = matchedSpecialEffect {
            return effect
        }
        if let gt = groupText {
            return SpecialWordEffectsLookup.effect(for: gt)
        }
        if word.isPartOfWord {
            return nil
        }
        let trimmed = cleanText
        if trimmed.hasPrefix("-") || trimmed.hasSuffix("-") ||
           trimmed.hasPrefix("–") || trimmed.hasSuffix("–") ||
           trimmed.hasPrefix("—") || trimmed.hasSuffix("—") {
            return nil
        }
        return SpecialWordEffectsLookup.effect(for: trimmed)
    }

    private var colorWord: Color? {
        guard isExactColorEnabled else { return nil }
        // 1. If pre-resolved at the word group level, use that color directly.
        if let mc = matchedColorWord {
            return mc
        }
        // 2. If groupText is provided, ONLY match if the full combined word is a color word.
        // Never allow a syllable fragment inside a group to match individually.
        if let gt = groupText {
            return ColorWordsLookup.color(for: gt)
        }
        // 3. Fallback when neither matchedColorWord nor groupText was provided:
        // Ensure this token is truly a standalone complete word, NOT part of a syllable split.
        if word.isPartOfWord {
            return nil
        }
        let trimmed = cleanText
        if trimmed.hasPrefix("-") || trimmed.hasSuffix("-") ||
           trimmed.hasPrefix("–") || trimmed.hasSuffix("–") ||
           trimmed.hasPrefix("—") || trimmed.hasSuffix("—") {
            return nil
        }
        return ColorWordsLookup.color(for: trimmed)
    }

    private var activeWordColor: Color {
        colorWord ?? activeColor
    }

    private var isDefaultColor: Bool {
        activeColor == .white || activeColor == .black
    }

    private var inactiveWordColor: Color {
        if colorScheme == .light {
            return Color.black.opacity(isBackground ? 0.28 : 0.38)
        } else {
            return Color.white.opacity(isBackground ? 0.30 : 0.40)
        }
    }

    private var pastWordColor: Color {
        if let cw = colorWord {
            return isBackground ? cw.opacity(0.80) : cw
        }
        if isDefaultColor {
            if colorScheme == .light {
                return isBackground ? Color.black.opacity(0.70) : Color.black.opacity(0.85)
            } else {
                return isBackground ? Color.white.opacity(0.90) : Color.white
            }
        } else {
            return isBackground ? activeColor.opacity(0.70) : activeColor.opacity(0.85)
        }
    }

    private var sungWordColor: Color {
        if let cw = colorWord {
            return isBackground ? cw.opacity(0.85) : cw
        }
        if isDefaultColor {
            if colorScheme == .light {
                return isBackground ? Color.black.opacity(0.80) : Color.black
            } else {
                return isBackground ? Color.white.opacity(0.90) : Color.white
            }
        } else {
            return isBackground ? activeColor.opacity(0.85) : activeColor
        }
    }

    @ViewBuilder
    private var singleSyllableView: some View {
        let isWordSung = isLinePast || currentTimeMs >= word.endMs
        let isWordActive = isLineActive && word.startMs <= currentTimeMs && currentTimeMs < word.endMs
        let duration = max(word.endMs - word.startMs, 1)
        let progress = max(0.0, min(1.0, Double(currentTimeMs - word.startMs) / Double(duration)))
        let scale = (isBounceEnabled && isWordActive) ? SpicySplines.scaleSpline.at(progress) : 1.0
        let yLift = (isBounceEnabled && isWordActive) ? (SpicySplines.ySpline.at(progress) * 32.0) : 0.0
        let scaleX: CGFloat = isSyllableSplit ? 1.0 : scale
        let scaleY: CGFloat = scale

        if let effect = specialEffect {
            SpecialWordEffectTokenView(
                text: cleanText,
                effect: effect,
                currentTimeMs: currentTimeMs,
                isLineActive: isLineActive,
                isWordActive: isWordActive,
                isWordSung: isWordSung,
                progress: progress,
                inactiveColor: inactiveWordColor,
                font: tokenFont ?? .system(size: 28, weight: .heavy),
                isGlowEnabled: isGlowEnabled
            )
            .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
            .offset(y: yLift)
        } else if !isLineActive {
            Text(cleanText)
                .foregroundStyle(isWordSung ? pastWordColor : inactiveWordColor)
        } else {
            if isWordActive {
                let wordActiveColor = activeWordColor
                let p = -0.15 + 1.30 * progress
                let stop1 = max(0.0, min(1.0, p))
                let stop2 = min(1.0, max(stop1 + 0.05, p + 0.18))
                let glowProgress = SpicySplines.glowSpline.at(progress)
                let glowOpacity = isGlowEnabled ? (glowProgress * (colorScheme == .light ? 0.30 : 0.85)) : 0.0

                Text(cleanText)
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: wordActiveColor.opacity(isBackground ? 0.90 : 0.98), location: stop1),
                                .init(color: inactiveWordColor, location: stop2)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
                    .offset(y: yLift)
                    .shadow(color: isGlowEnabled ? wordActiveColor.opacity(glowOpacity) : Color.clear, radius: isGlowEnabled ? 10 : 0, x: 0, y: 0)
            } else if isWordSung {
                Text(cleanText)
                    .foregroundStyle(sungWordColor)
            } else {
                Text(cleanText)
                    .foregroundStyle(inactiveWordColor)
            }
        }
    }

    @ViewBuilder
    private var letterGroupView: some View {
        let isWordSung = isLinePast || currentTimeMs >= word.endMs
        let isWordActive = isLineActive && word.startMs <= currentTimeMs && currentTimeMs < word.endMs

        if let effect = specialEffect {
            let duration = max(word.endMs - word.startMs, 1)
            let progress = max(0.0, min(1.0, Double(currentTimeMs - word.startMs) / Double(duration)))
            let scale = (isBounceEnabled && isWordActive) ? SpicySplines.scaleSpline.at(progress) : 1.0
            let yLift = (isBounceEnabled && isWordActive) ? (SpicySplines.ySpline.at(progress) * 32.0) : 0.0
            let scaleX: CGFloat = isSyllableSplit ? 1.0 : scale
            let scaleY: CGFloat = scale

            SpecialWordEffectTokenView(
                text: cleanText,
                effect: effect,
                currentTimeMs: currentTimeMs,
                isLineActive: isLineActive,
                isWordActive: isWordActive,
                isWordSung: isWordSung,
                progress: progress,
                inactiveColor: inactiveWordColor,
                font: tokenFont ?? .system(size: 28, weight: .heavy),
                isGlowEnabled: isGlowEnabled
            )
            .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
            .offset(y: yLift)
        } else if !isLineActive {
            Text(cleanText)
                .foregroundStyle(isWordSung ? pastWordColor : inactiveWordColor)
        } else {
            let wordActiveColor = activeWordColor
            HStack(spacing: 0) {
                ForEach(word.letters) { letter in
                    let isLetterSung = currentTimeMs >= letter.endMs
                    let isLetterActive = letter.startMs <= currentTimeMs && currentTimeMs < letter.endMs

                    if isLetterActive {
                        let duration = max(letter.endMs - letter.startMs, 1)
                        let progress = max(0.0, min(1.0, Double(currentTimeMs - letter.startMs) / Double(duration)))
                        let scale = isBounceEnabled ? SpicySplines.letterScaleSpline.at(progress) : 1.0
                        let yLift = isBounceEnabled ? (SpicySplines.letterYSpline.at(progress) * 28.0) : 0.0
                        let p = -0.15 + 1.30 * progress
                        let stop1 = max(0.0, min(0.95, p))
                        let stop2 = min(1.0, max(stop1 + 0.05, p + 0.20))
                        let letterGlow = isGlowEnabled ? (SpicySplines.glowSpline.at(progress) * (colorScheme == .light ? 0.30 : 0.85)) : 0.0

                        Text(letter.char)
                            .foregroundStyle(
                                LinearGradient(
                                    stops: [
                                        .init(color: wordActiveColor.opacity(isBackground ? 0.90 : 0.98), location: stop1),
                                        .init(color: inactiveWordColor, location: stop2)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .scaleEffect(x: 1.0, y: scale, anchor: .bottom)
                            .offset(y: yLift)
                            .shadow(color: isGlowEnabled ? wordActiveColor.opacity(letterGlow) : Color.clear, radius: isGlowEnabled ? 8 : 0, x: 0, y: 0)
                    } else if isLetterSung {
                        Text(letter.char)
                            .foregroundStyle(sungWordColor)
                    } else {
                        Text(letter.char)
                            .foregroundStyle(inactiveWordColor)
                    }
                }
            }
        }
    }
}

// MARK: - Spicy Word Group View (Seamless Syllables & Whole-Word Wrap)

struct SpicyWordGroupView: View {
    let group: SpicyWordGroup
    let currentTimeMs: Int
    let isBackground: Bool
    let isLineActive: Bool
    let isLinePast: Bool
    let lineFont: Font
    var isGlowEnabled: Bool = true
    var isBounceEnabled: Bool = true
    var activeColor: Color = .white
    var isExactColorEnabled: Bool = true
    var isSpecialWordEffectsEnabled: Bool = true

    var body: some View {
        let fullGroupWord = group.words.map(\.text).joined()
        let groupColorWord: Color? = {
            guard isExactColorEnabled else { return nil }
            // If the group as a whole is incomplete (e.g. ends with isPartOfWord or boundary hyphens),
            // it is a syllable fragment across line/timing boundaries, not a complete word.
            if let last = group.words.last {
                if last.isPartOfWord { return nil }
                let lastTrimmed = last.text.trimmingCharacters(in: .whitespaces)
                if lastTrimmed.hasSuffix("-") || lastTrimmed.hasSuffix("–") || lastTrimmed.hasSuffix("—") {
                    return nil
                }
            }
            if let first = group.words.first {
                let firstTrimmed = first.text.trimmingCharacters(in: .whitespaces)
                if firstTrimmed.hasPrefix("-") || firstTrimmed.hasPrefix("–") || firstTrimmed.hasPrefix("—") {
                    return nil
                }
            }
            return ColorWordsLookup.color(for: fullGroupWord)
        }()

        let groupSpecialEffect: WordSpecialEffect? = {
            guard isSpecialWordEffectsEnabled else { return nil }
            if let last = group.words.last {
                if last.isPartOfWord { return nil }
                let lastTrimmed = last.text.trimmingCharacters(in: .whitespaces)
                if lastTrimmed.hasSuffix("-") || lastTrimmed.hasSuffix("–") || lastTrimmed.hasSuffix("—") {
                    return nil
                }
            }
            if let first = group.words.first {
                let firstTrimmed = first.text.trimmingCharacters(in: .whitespaces)
                if firstTrimmed.hasPrefix("-") || firstTrimmed.hasPrefix("–") || firstTrimmed.hasPrefix("—") {
                    return nil
                }
            }
            return SpecialWordEffectsLookup.effect(for: fullGroupWord)
        }()

        let isGroupSplit = group.words.count > 1

        HStack(spacing: 0) {
            ForEach(group.words) { word in
                SpicySyllableTokenView(
                    word: word,
                    currentTimeMs: currentTimeMs,
                    isBackground: isBackground,
                    isLineActive: isLineActive,
                    isLinePast: isLinePast,
                    isGlowEnabled: isGlowEnabled,
                    isBounceEnabled: isBounceEnabled,
                    activeColor: activeColor,
                    isExactColorEnabled: isExactColorEnabled,
                    isSpecialWordEffectsEnabled: isSpecialWordEffectsEnabled,
                    groupText: fullGroupWord,
                    matchedColorWord: groupColorWord,
                    matchedSpecialEffect: groupSpecialEffect,
                    tokenFont: lineFont,
                    isGroupSplit: isGroupSplit
                )
            }
            if group.hasTrailingSpace {
                Text(" ")
                    .font(lineFont)
            }
        }
    }
}

// MARK: - Spicy Countdown Dot Line (AMLL-TTML-TOOL dotLine)

struct SpicyDotLineView: View {
    let line: LyricLine
    let currentTimeMs: Int
    let isLineActive: Bool
    var isBounceEnabled: Bool = true
    var isGlowEnabled: Bool = true
    var activeColor: Color = .white
    var isPlaying: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        let isDefaultColor = (activeColor == .white || activeColor == .black)
        let effectiveActiveColor = isDefaultColor ? (isLight ? Color.black : Color.white) : activeColor

        let isVisible = isLineActive && (currentTimeMs >= line.startMs) && (currentTimeMs < line.endMs)

        // Smoothly divide the FULL instrumental duration across the 3 dots
        let total = Double(max(line.endMs - line.startMs, 1000))
        let base = total / 3.0
        let start = Double(line.startMs)
        let dotWindows: [(Double, Double)] = [
            (start, start + base),
            (start + base, start + 2.0 * base),
            (start + 2.0 * base, Double(line.endMs))
        ]

        HStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { index in
                let window = dotWindows[index]
                let dotStart = window.0
                let dotEnd = window.1
                let dur = max(dotEnd - dotStart, 1.0)
                let current = Double(currentTimeMs)
                let p = max(0.0, min(1.0, (current - dotStart) / dur))
                let isDotActive = isLineActive && current >= dotStart && current < dotEnd
                let isDotSung = isLineActive && current >= dotEnd

                // Up & down bounce arc: lifts up and lands back down smoothly over the active window
                let jumpProgress = min(1.0, p / 0.70)
                let jumpArc = sin(jumpProgress * .pi) // 0.0 -> 1.0 (peak) -> 0.0 (landed)

                let yOffset: CGFloat = {
                    guard isBounceEnabled && isDotActive else { return 0 }
                    return CGFloat(-jumpArc * 16.0)
                }()

                let scale: CGFloat = {
                    if isDotSung {
                        return 1.0
                    } else if isDotActive {
                        if isBounceEnabled {
                            return CGFloat(0.80 + 0.20 * jumpProgress + 0.16 * jumpArc)
                        } else {
                            return CGFloat(0.80 + 0.20 * jumpProgress)
                        }
                    } else {
                        return 0.80
                    }
                }()

                // Smoothly becomes bright over time: 0.32 -> 1.0
                let opacity: Double = {
                    if isDotSung {
                        return 1.0
                    } else if isDotActive {
                        return 0.32 + 0.68 * min(1.0, p / 0.75)
                    } else {
                        return 0.32
                    }
                }()

                let glowFactor: Double = {
                    guard isGlowEnabled else { return 0 }
                    if isDotActive {
                        return 0.20 + 0.80 * jumpArc
                    } else if isDotSung {
                        return 0.25
                    } else {
                        return 0.0
                    }
                }()

                let glowRadius: CGFloat = CGFloat(glowFactor * 12.0)
                let glowColor: Color = effectiveActiveColor.opacity(glowFactor * (isLight ? 0.45 : 0.75))

                Text("•")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(effectiveActiveColor)
                    .scaleEffect(scale)
                    .offset(y: yOffset)
                    .opacity(opacity)
                    .shadow(
                        color: glowColor,
                        radius: glowRadius,
                        x: 0,
                        y: 0
                    )
            }
        }
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, alignment: line.oppositeAligned ? .trailing : .leading)
        .padding(.leading, line.oppositeAligned ? 36 : 16)
        .padding(.trailing, line.oppositeAligned ? 16 : 36)
        .scaleEffect(isVisible ? 1.0 : 0.85)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(isPlaying ? .spring(response: 0.38, dampingFraction: 0.82) : nil, value: isVisible)
    }
}

// MARK: - Spicy Flow Layout (Word-Wrap preserving syllable clusters)

@available(iOS 16.0, macOS 13.0, *)
struct SpicyFlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var horizontalSpacing: CGFloat = 0
    var verticalSpacing: CGFloat = 4

    init(alignment: HorizontalAlignment = .leading, horizontalSpacing: CGFloat = 0, verticalSpacing: CGFloat = 4) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let defaultWidth: CGFloat = {
            #if canImport(UIKit)
            return UIScreen.main.bounds.width - 64
            #else
            return 340
            #endif
        }()
        let width = (proposal.width != nil && proposal.width! > 0 && proposal.width! != .infinity) ? proposal.width! : defaultWidth
        var currentPoint = CGPoint.zero
        var maxRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            guard size.width > 0 else { continue }
            if currentPoint.x + size.width > width && currentPoint.x > 0 {
                currentPoint.x = 0
                currentPoint.y += maxRowHeight + verticalSpacing
                maxRowHeight = 0
            }
            maxRowHeight = max(maxRowHeight, size.height)
            currentPoint.x += size.width + horizontalSpacing
            totalWidth = max(totalWidth, currentPoint.x)
            totalHeight = currentPoint.y + maxRowHeight
        }
        let resultWidth = (alignment == .trailing) ? width : min(width, totalWidth)
        return CGSize(width: resultWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var rows: [([LayoutSubview], [CGSize], CGFloat)] = []
        var currentRow: [LayoutSubview] = []
        var currentSizes: [CGSize] = []
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            guard size.width > 0 else { continue }
            if currentRowWidth + size.width > width && !currentRow.isEmpty {
                rows.append((currentRow, currentSizes, currentRowWidth))
                currentRow = []
                currentSizes = []
                currentRowWidth = 0
            }
            currentRow.append(subview)
            currentSizes.append(size)
            currentRowWidth += size.width + horizontalSpacing
        }
        if !currentRow.isEmpty {
            rows.append((currentRow, currentSizes, currentRowWidth))
        }

        var y = bounds.minY
        for (subviewsInRow, sizes, rowWidth) in rows {
            let actualRowWidth = rowWidth - (sizes.isEmpty ? 0 : horizontalSpacing)
            let xOffset: CGFloat
            switch alignment {
            case .trailing:
                xOffset = max(bounds.minX, bounds.maxX - actualRowWidth)
            case .center:
                xOffset = max(bounds.minX, bounds.minX + (bounds.width - actualRowWidth) / 2)
            default:
                xOffset = bounds.minX
            }

            var x = xOffset
            var rowMaxHeight: CGFloat = 0
            for (subview, size) in zip(subviewsInRow, sizes) {
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width + horizontalSpacing
                rowMaxHeight = max(rowMaxHeight, size.height)
            }
            y += rowMaxHeight + verticalSpacing
        }
    }
}

// MARK: - Spicy Lyric Line View

struct SpicyLyricLineView: View, Equatable {
    let line: LyricLine
    let currentTimeMs: Int
    let isLineActive: Bool
    let isLinePast: Bool
    let distance: Int
    let isRomanizationEnabled: Bool
    let isTranslationEnabled: Bool
    let isUserScrolling: Bool
    let fontDesign: Font.Design
    let fontSize: CGFloat
    let isGlowEnabled: Bool
    let isBounceEnabled: Bool
    let activeColor: Color
    var isExactColorEnabled: Bool = true
    var isSpecialWordEffectsEnabled: Bool = true
    var isSongUnsynced: Bool = false
    var isPlaying: Bool = true
    let onSeek: (Int) -> Void
    @Environment(\.colorScheme) private var colorScheme

    static func == (lhs: SpicyLyricLineView, rhs: SpicyLyricLineView) -> Bool {
        lhs.line == rhs.line &&
        lhs.isLineActive == rhs.isLineActive &&
        lhs.isLinePast == rhs.isLinePast &&
        lhs.distance == rhs.distance &&
        lhs.isRomanizationEnabled == rhs.isRomanizationEnabled &&
        lhs.isTranslationEnabled == rhs.isTranslationEnabled &&
        lhs.isUserScrolling == rhs.isUserScrolling &&
        lhs.fontDesign == rhs.fontDesign &&
        lhs.fontSize == rhs.fontSize &&
        lhs.isGlowEnabled == rhs.isGlowEnabled &&
        lhs.isBounceEnabled == rhs.isBounceEnabled &&
        lhs.activeColor == rhs.activeColor &&
        lhs.isExactColorEnabled == rhs.isExactColorEnabled &&
        lhs.isSpecialWordEffectsEnabled == rhs.isSpecialWordEffectsEnabled &&
        lhs.isSongUnsynced == rhs.isSongUnsynced &&
        lhs.isPlaying == rhs.isPlaying &&
        (!((lhs.isLineActive || lhs.line.isInterlude)) || lhs.currentTimeMs == rhs.currentTimeMs)
    }

    init(
        line: LyricLine,
        currentTimeMs: Int,
        isLineActive: Bool? = nil,
        isLinePast: Bool? = nil,
        distance: Int = 0,
        isRomanizationEnabled: Bool = false,
        isTranslationEnabled: Bool = false,
        isUserScrolling: Bool = false,
        fontDesign: Font.Design = .default,
        fontSize: CGFloat = 28,
        isGlowEnabled: Bool = true,
        isBounceEnabled: Bool = true,
        activeColor: Color = .white,
        isExactColorEnabled: Bool = true,
        isSpecialWordEffectsEnabled: Bool = true,
        isSongUnsynced: Bool = false,
        isPlaying: Bool = true,
        onSeek: @escaping (Int) -> Void = { _ in }
    ) {
        self.line = line
        self.currentTimeMs = currentTimeMs
        self.isLineActive = isLineActive ?? (line.startMs <= currentTimeMs && currentTimeMs <= line.endMs)
        self.isLinePast = isLinePast ?? (currentTimeMs > line.endMs)
        self.distance = distance
        self.isRomanizationEnabled = isRomanizationEnabled
        self.isTranslationEnabled = isTranslationEnabled
        self.isUserScrolling = isUserScrolling
        self.fontDesign = fontDesign
        self.fontSize = fontSize
        self.isGlowEnabled = isGlowEnabled
        self.isBounceEnabled = isBounceEnabled
        self.activeColor = activeColor
        self.isExactColorEnabled = isExactColorEnabled
        self.isSpecialWordEffectsEnabled = isSpecialWordEffectsEnabled
        self.isSongUnsynced = isSongUnsynced
        self.isPlaying = isPlaying
        self.onSeek = onSeek
    }

    var body: some View {
        Group {
            if line.isInterlude {
                let isCurrent = isLineActive && (currentTimeMs >= line.startMs && currentTimeMs < line.endMs)
                SpicyDotLineView(
                    line: line,
                    currentTimeMs: currentTimeMs,
                    isLineActive: isCurrent,
                    isBounceEnabled: isBounceEnabled,
                    isGlowEnabled: isGlowEnabled,
                    activeColor: activeColor,
                    isPlaying: isPlaying
                )
                .frame(height: isCurrent ? 52 : 0)
                .offset(y: -1)
                .opacity(isCurrent ? 1.0 : 0.0)
                .frame(maxWidth: .infinity, alignment: line.oppositeAligned ? .trailing : .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSeek(max(0, line.startMs + 5))
                }
                .animation(isPlaying ? .spring(response: 0.48, dampingFraction: 0.82) : nil, value: isCurrent)
            } else {
                VStack(alignment: line.oppositeAligned ? .trailing : .leading, spacing: 6) {
                    if line.isSongwriter {
                        Text(line.displayText.isEmpty ? " " : line.displayText)
                            .font(.system(size: isMacPlatform ? 22 : 18, weight: .medium, design: fontDesign))
                            .foregroundStyle(colorScheme == .light ? Color.black.opacity(0.68) : Color.white.opacity(0.68))
                            .multilineTextAlignment(line.oppositeAligned ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: line.oppositeAligned ? .trailing : .leading)
                    } else if !line.isWordSynced || line.words.isEmpty {
                        // Clean whole-line display for line-synced & unsynced songs
                        let isDefaultColor = (activeColor == .white || activeColor == .black)
                        let inactiveColor = colorScheme == .light ? Color.black.opacity(line.isBackground ? 0.28 : 0.38) : Color.white.opacity(line.isBackground ? 0.30 : 0.40)
                        let pastLeadColor = isDefaultColor ? (colorScheme == .light ? Color.black.opacity(0.85) : Color.white.opacity(0.85)) : activeColor.opacity(0.75)
                        let pastBgColor = isDefaultColor ? (colorScheme == .light ? Color.black.opacity(0.70) : Color.white.opacity(0.75)) : activeColor.opacity(0.65)
                        let pastColor = line.isBackground ? pastBgColor : pastLeadColor
                        let activeLineColor = !line.isBackground ? activeColor : activeColor.opacity(0.90)

                        let effectiveTextColor: Color = {
                            if isSongUnsynced || line.isStatic {
                                return activeLineColor
                            }
                            return isLineActive ? activeLineColor : (isLinePast ? pastColor : inactiveColor)
                        }()

                        let hasColorWords = (isExactColorEnabled && lineHasColorWords(line.displayText)) ||
                                            (isSpecialWordEffectsEnabled && lineHasSpecialEffectWords(line.displayText))
                        let shouldLineGlow = isGlowEnabled && isLineActive && !isSongUnsynced && !line.isStatic

                        if hasColorWords {
                            lineSyncedColorWordsView(
                                text: line.displayText,
                                baseColor: effectiveTextColor,
                                isHighlightState: isLineActive || isSongUnsynced || line.isStatic,
                                shouldGlow: shouldLineGlow
                            )
                        } else {
                            Text(line.displayText.isEmpty ? " " : line.displayText)
                                .font(lineFont)
                                .tracking(-0.5)
                                .multilineTextAlignment(line.oppositeAligned ? .trailing : .leading)
                                .foregroundStyle(effectiveTextColor)
                                .shadow(color: shouldLineGlow ? activeColor.opacity(colorScheme == .light ? 0.25 : 0.40) : Color.clear, radius: shouldLineGlow ? 10 : 0, x: 0, y: 0)
                                .frame(maxWidth: .infinity, alignment: line.oppositeAligned ? .trailing : .leading)
                        }
                    } else {
                        // Word groups with preserve-word line wrap and syllable-level progressive physics
                        SpicyFlowLayout(alignment: line.oppositeAligned ? .trailing : .leading) {
                            ForEach(line.wordGroups) { group in
                                SpicyWordGroupView(
                                    group: group,
                                    currentTimeMs: currentTimeMs,
                                    isBackground: line.isBackground,
                                    isLineActive: isLineActive,
                                    isLinePast: isLinePast,
                                    lineFont: lineFont,
                                    isGlowEnabled: isGlowEnabled,
                                    isBounceEnabled: isBounceEnabled,
                                    activeColor: activeColor,
                                    isExactColorEnabled: isExactColorEnabled,
                                    isSpecialWordEffectsEnabled: isSpecialWordEffectsEnabled
                                )
                            }
                        }
                        .font(lineFont)
                        .tracking(-0.5)
                        .frame(maxWidth: .infinity, alignment: line.oppositeAligned ? .trailing : .leading)
                    }

                    if isRomanizationEnabled, let roman = line.romanization {
                        Text(roman)
                            .font(.system(size: isMacPlatform ? (line.isBackground ? 20 : 25) : (line.isBackground ? 16 : 20), weight: .medium, design: fontDesign))
                            .foregroundStyle(colorScheme == .light ? Color.black.opacity(isLineActive ? 0.72 : 0.45) : Color.white.opacity(isLineActive ? 0.72 : 0.45))
                            .multilineTextAlignment(line.oppositeAligned ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: line.oppositeAligned ? .trailing : .leading)
                    }

                    if isTranslationEnabled, let translation = line.translation {
                        Text(translation)
                            .font(.system(size: isMacPlatform ? (line.isBackground ? 19 : 23) : (line.isBackground ? 15 : 18), weight: .medium, design: fontDesign))
                            .foregroundStyle(colorScheme == .light ? Color.black.opacity(isLineActive ? 0.72 : 0.45) : Color.white.opacity(isLineActive ? 0.72 : 0.45))
                            .multilineTextAlignment(line.oppositeAligned ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: line.oppositeAligned ? .trailing : .leading)
                    }
                }
                .opacity(lineOpacity)
                .scaleEffect(isBounceEnabled ? (isLineActive ? 1.0 : 0.96) : 1.0, anchor: line.oppositeAligned ? .trailing : .leading)
                .animation(isPlaying ? .spring(response: 0.48, dampingFraction: 1.0) : nil, value: isLineActive)
                .modifier(OptionalBlurModifier(radius: lineBlur))
                .padding(.top, line.isBackground ? -4 : (isMacPlatform ? 14 : 10))
                .padding(.bottom, line.isBackground ? 10 : (isMacPlatform ? 16 : 12))
                .frame(maxWidth: .infinity, alignment: line.oppositeAligned ? .trailing : .leading)
                .padding(.leading, line.oppositeAligned ? 36 : 16)
                .padding(.trailing, line.oppositeAligned ? 16 : 36)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !line.isSongwriter && !line.isStatic && !isSongUnsynced {
                        onSeek(max(0, line.startMs + 5))
                    }
                }
            }
        }
    }

    private var lineFont: Font {
        if line.isBackground {
            return .system(size: max(isMacPlatform ? 20 : 16, fontSize - (isMacPlatform ? 8 : 6)), weight: .bold, design: fontDesign)
        }
        return .system(size: fontSize, weight: .heavy, design: fontDesign)
    }

    private var lineOpacity: Double {
        if isSongUnsynced || line.isStatic { return 0.95 }
        if isLineActive { return 1.0 }
        if isUserScrolling { return 0.85 }
        return isLinePast ? 0.55 : 0.48
    }

    private var lineBlur: CGFloat {
        0.0 // Always 0 so text is never blurred in the middle or while scrolling
    }

    private func lineHasColorWords(_ text: String) -> Bool {
        text.split(separator: " ").contains {
            ColorWordsLookup.color(for: String($0)) != nil
        }
    }

    private func lineHasSpecialEffectWords(_ text: String) -> Bool {
        text.split(separator: " ").contains {
            SpecialWordEffectsLookup.effect(for: String($0)) != nil
        }
    }

    @ViewBuilder
    private func lineSyncedColorWordsView(
        text: String,
        baseColor: Color,
        isHighlightState: Bool,
        shouldGlow: Bool
    ) -> some View {
        let tokens = text.split(separator: " ").map(String.init)
        let glowOpacity = colorScheme == .light ? 0.25 : 0.40

        SpicyFlowLayout(alignment: line.oppositeAligned ? .trailing : .leading) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                let matchedEffect = isSpecialWordEffectsEnabled ? SpecialWordEffectsLookup.effect(for: token) : nil
                let matchedColor = isExactColorEnabled ? ColorWordsLookup.color(for: token) : nil
                let isLast = index == tokens.count - 1

                HStack(spacing: 0) {
                    if let effect = matchedEffect {
                        SpecialWordEffectTokenView(
                            text: token,
                            effect: effect,
                            currentTimeMs: currentTimeMs,
                            isLineActive: isLineActive,
                            isWordActive: isHighlightState,
                            isWordSung: isLinePast,
                            progress: isHighlightState ? 1.0 : 0.0,
                            inactiveColor: baseColor,
                            font: lineFont,
                            isGlowEnabled: shouldGlow
                        )
                    } else {
                        let wordColor: Color = {
                            if let cw = matchedColor {
                                if isHighlightState {
                                    return cw
                                } else if isLinePast {
                                    return line.isBackground ? cw.opacity(0.80) : cw
                                } else {
                                    return baseColor
                                }
                            }
                            return baseColor
                        }()

                        let wordGlowColor: Color = matchedColor ?? activeColor

                        Text(token)
                            .font(lineFont)
                            .tracking(-0.5)
                            .foregroundStyle(wordColor)
                            .shadow(
                                color: shouldGlow ? wordGlowColor.opacity(glowOpacity) : Color.clear,
                                radius: shouldGlow ? 10 : 0,
                                x: 0,
                                y: 0
                            )
                    }

                    if !isLast {
                        Text(" ")
                            .font(lineFont)
                            .tracking(-0.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: line.oppositeAligned ? .trailing : .leading)
    }
}

private struct OptionalBlurModifier: ViewModifier {
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if radius > 0.1 {
            content.blur(radius: radius)
        } else {
            content
        }
    }
}

// MARK: - Spicy Lyrics Attribution Footer

struct SpicyLyricsAttributionFooterView: View {
    let source: String?
    let attribution: SpicyUploadAttribution?
    let songwriters: [String]
    var onManageConnection: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        let baseColor = isLight ? Color.black : Color.white

        VStack(spacing: 18) {
            // Subtle glowing divider
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: baseColor.opacity(0.0), location: 0),
                            .init(color: baseColor.opacity(isLight ? 0.12 : 0.18), location: 0.5),
                            .init(color: baseColor.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 4)

            // Spicy Lyrics Sync (Maker & Uploader) section — prioritized above all other metadata
            if let attr = attribution, (attr.maker != nil || attr.uploader != nil) {
                let maker = attr.maker
                let uploader = attr.uploader
                let isSamePerson: Bool = {
                    guard let m = maker, let u = uploader else { return false }
                    if let mid = m.id, !mid.isEmpty, let uid = u.id, !uid.isEmpty, mid == uid { return true }
                    if let mun = m.username, !mun.isEmpty, let uun = u.username, !uun.isEmpty, mun.caseInsensitiveCompare(uun) == .orderedSame { return true }
                    return false
                }()

                VStack(spacing: 10) {
                    Text(maker != nil ? "SPICY LYRICS SYNC" : "SPICY LYRICS CREDITS")
                        .font(.system(size: isMacPlatform ? 13 : 11, weight: .bold, design: .rounded))
                        .foregroundStyle(baseColor.opacity(isLight ? 0.50 : 0.45))
                        .tracking(1.2)

                    HStack(spacing: 12) {
                        if isSamePerson, let user = maker ?? uploader {
                            userBadge(role: "Synced & Uploaded by", user: user, baseColor: baseColor, isLight: isLight)
                        } else {
                            if let maker = maker {
                                userBadge(role: "Synced by", user: maker, baseColor: baseColor, isLight: isLight)
                            }
                            if let uploader = uploader {
                                userBadge(role: "Uploaded by", user: uploader, baseColor: baseColor, isLight: isLight)
                            }
                        }
                    }
                }
            }

            // Songwriters section
            if !songwriters.isEmpty {
                VStack(spacing: 4) {
                    Text("WRITTEN BY")
                        .font(.system(size: isMacPlatform ? 13 : 11, weight: .bold, design: .rounded))
                        .foregroundStyle(baseColor.opacity(isLight ? 0.50 : 0.45))
                        .tracking(1.2)

                    Text(songwriters.joined(separator: ", "))
                        .font(.system(size: isMacPlatform ? 17 : 14, weight: .medium, design: .rounded))
                        .foregroundStyle(baseColor.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            // Provider badge
            if isSpicyLyricsCommunity, let onManageConnection = onManageConnection {
                Button {
                    onManageConnection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: isMacPlatform ? 14 : 12))
                            .foregroundStyle(Color.orange.opacity(0.9))

                        Text(providerLabel)
                            .font(.system(size: isMacPlatform ? 14 : 12, weight: .medium, design: .rounded))
                            .foregroundStyle(baseColor.opacity(0.55))

                        Image(systemName: "chevron.right")
                            .font(.system(size: isMacPlatform ? 11 : 9, weight: .semibold))
                            .foregroundStyle(baseColor.opacity(0.40))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(baseColor.opacity(isLight ? 0.05 : 0.08))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else if isSpicyLyricsCommunity {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: isMacPlatform ? 14 : 12))
                        .foregroundStyle(Color.orange.opacity(0.9))

                    Text(providerLabel)
                        .font(.system(size: isMacPlatform ? 14 : 12, weight: .medium, design: .rounded))
                        .foregroundStyle(baseColor.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(baseColor.opacity(isLight ? 0.05 : 0.08))
                )
                .padding(.top, 2)
            } else {
                Text(providerLabel)
                    .font(.system(size: isMacPlatform ? 14 : 12, weight: .medium, design: .rounded))
                    .foregroundStyle(baseColor.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(baseColor.opacity(isLight ? 0.05 : 0.08))
                    )
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var isSpicyLyricsCommunity: Bool {
        if let src = source?.lowercased() {
            if src.contains("lrclib") || src.contains("bini") {
                return false
            }
            if src.contains("apple") || src.contains("spotify") {
                return false
            }
            if src.contains("community") {
                return true
            }
        }
        if let attr = attribution, (attr.maker != nil || attr.uploader != nil) {
            return true
        }
        return false
    }

    private var providerLabel: String {
        if isSpicyLyricsCommunity {
            return "Lyrics provided by Spicy Lyrics Community"
        }
        guard let src = source?.lowercased() else {
            return "Lyrics provided by Spicy Lyrics"
        }
        if src.contains("lrclib") {
            return "Lyrics provided by LRCLIB"
        } else if src.contains("apple") || src.contains("bini") {
            return "Lyrics provided by Apple Music"
        } else if src.contains("spotify") {
            return "Lyrics provided by Spotify"
        } else {
            return "Lyrics provided by Spicy Lyrics"
        }
    }

    @ViewBuilder
    private func userBadge(role: String, user: SpicyAttributionUser, baseColor: Color, isLight: Bool) -> some View {
        let avatarUrl = resolveAvatarUrl(id: user.id, avatar: user.avatar)
        let profileUrl = user.url.flatMap { URL(string: $0) }

        Button {
            if let profileUrl = profileUrl {
                openURL(profileUrl)
            }
        } label: {
            HStack(spacing: 8) {
                if let avatarUrl = avatarUrl {
                    AsyncImage(url: avatarUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(baseColor.opacity(0.6))
                        case .empty:
                            ProgressView()
                                .tint(baseColor)
                                .scaleEffect(0.6)
                        @unknown default:
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(baseColor.opacity(0.6))
                        }
                    }
                    .frame(width: isMacPlatform ? 34 : 28, height: isMacPlatform ? 34 : 28)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(baseColor.opacity(0.2), lineWidth: 1))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: isMacPlatform ? 34 : 28, height: isMacPlatform ? 34 : 28)
                        .foregroundStyle(baseColor.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(role)
                        .font(.system(size: isMacPlatform ? 12 : 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(baseColor.opacity(0.5))

                    let displayName = (user.username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? user.username! : ((user.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? user.id! : "Contributor")
                    HStack(spacing: 3) {
                        Text(displayName)
                            .font(.system(size: isMacPlatform ? 15 : 13, weight: .bold, design: .rounded))
                            .foregroundStyle(baseColor)

                        if profileUrl != nil {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(baseColor.opacity(0.5))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(baseColor.opacity(isLight ? 0.05 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(baseColor.opacity(isLight ? 0.08 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func resolveAvatarUrl(id: String?, avatar: String?) -> URL? {
        guard let avatar = avatar, !avatar.isEmpty else { return nil }
        if avatar.hasPrefix("http://") || avatar.hasPrefix("https://") {
            return URL(string: avatar)
        }
        if let id = id, !id.isEmpty {
            return URL(string: "https://cdn.discordapp.com/avatars/\(id)/\(avatar).png?size=128")
        }
        return nil
    }
}

