import Foundation
#if canImport(UIKit)
import UIKit
#endif

public var isMacPlatform: Bool {
    #if targetEnvironment(macCatalyst)
    return true
    #elseif canImport(UIKit)
    return UIDevice.current.userInterfaceIdiom == .mac || ProcessInfo.processInfo.isiOSAppOnMac
    #else
    return false
    #endif
}

public func timecode(_ ms: Int) -> String {
    let totalSeconds = max(ms / 1000, 0)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

struct LyricLetter: Identifiable, Hashable {
    let id: UUID
    let char: String
    let startMs: Int
    let endMs: Int

    init(id: UUID = UUID(), char: String, startMs: Int, endMs: Int) {
        self.id = id
        self.char = char
        self.startMs = startMs
        self.endMs = endMs
    }
}

struct LyricWord: Identifiable, Hashable {
    let id: UUID
    let text: String
    let startMs: Int
    let endMs: Int
    let isPartOfWord: Bool
    let isLetterGroup: Bool
    let letters: [LyricLetter]

    init(
        id: UUID = UUID(),
        text: String,
        startMs: Int,
        endMs: Int,
        isPartOfWord: Bool = false,
        isLetterGroup: Bool = false,
        letters: [LyricLetter] = []
    ) {
        self.id = id
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.isPartOfWord = isPartOfWord
        self.isLetterGroup = isLetterGroup
        self.letters = letters
    }

    var duration: Int {
        max(endMs - startMs, 1)
    }
}

struct SpicyWordGroup: Identifiable, Hashable {
    let id: String
    let words: [LyricWord]
    let hasTrailingSpace: Bool

    init(words: [LyricWord], hasTrailingSpace: Bool) {
        self.words = words
        self.hasTrailingSpace = hasTrailingSpace
        self.id = words.first.map { "\($0.id.uuidString)_\($0.startMs)" } ?? UUID().uuidString
    }
}

func groupSpicyWords(_ words: [LyricWord]) -> [SpicyWordGroup] {
    var groups: [SpicyWordGroup] = []
    var current: [LyricWord] = []

    for (index, word) in words.enumerated() {
        current.append(word)

        let isLast = index == words.count - 1

        // If word.isPartOfWord is true, this syllable continues into the next syllable
        // of the same word (e.g. "be" in "becoming" or "be-" in "be-coming").
        // Keep all syllables of the word together in the current group so no spaces appear mid-word.
        let trimmedText = word.text.trimmingCharacters(in: .whitespaces)
        let hasTrailingHyphen = trimmedText.hasSuffix("-") || trimmedText.hasSuffix("–") || trimmedText.hasSuffix("—")
        let nextHasLeadingHyphen: Bool = {
            guard index + 1 < words.count else { return false }
            let nextTrimmed = words[index + 1].text.trimmingCharacters(in: .whitespaces)
            return nextTrimmed.hasPrefix("-") || nextTrimmed.hasPrefix("–") || nextTrimmed.hasPrefix("—")
        }()

        let isContinuing = word.isPartOfWord || hasTrailingHyphen || nextHasLeadingHyphen
        let shouldEndGroup = isLast || !isContinuing

        if shouldEndGroup {
            let hasTrailingSpace = !isLast
            groups.append(SpicyWordGroup(words: current, hasTrailingSpace: hasTrailingSpace))
            current = []
        }
    }

    if !current.isEmpty {
        groups.append(SpicyWordGroup(words: current, hasTrailingSpace: false))
    }
    return groups
}

struct LyricLine: Identifiable, Hashable {
    let id: UUID
    let words: [LyricWord]
    let wordGroups: [SpicyWordGroup]
    let startMs: Int
    let lineEndMs: Int?
    let isWordSynced: Bool
    let agent: String?
    let isBackground: Bool
    let oppositeAligned: Bool
    let isSongwriter: Bool
    let isInterlude: Bool
    let interludeEndMs: Int
    let translation: String?
    let romanization: String?
    let rawText: String?
    let isStatic: Bool

    init(
        id: UUID = UUID(),
        words: [LyricWord] = [],
        startMs: Int,
        lineEndMs: Int? = nil,
        isWordSynced: Bool = false,
        agent: String? = nil,
        isBackground: Bool = false,
        oppositeAligned: Bool = false,
        isSongwriter: Bool = false,
        isInterlude: Bool = false,
        interludeEndMs: Int = -1,
        translation: String? = nil,
        romanization: String? = nil,
        rawText: String? = nil,
        isStatic: Bool = false
    ) {
        self.id = id
        self.words = words
        self.wordGroups = groupSpicyWords(words)
        self.startMs = startMs
        self.lineEndMs = lineEndMs
        self.isWordSynced = isWordSynced
        self.agent = agent
        self.isBackground = isBackground
        self.oppositeAligned = oppositeAligned
        self.isSongwriter = isSongwriter
        self.isInterlude = isInterlude
        self.interludeEndMs = interludeEndMs
        self.translation = translation
        self.romanization = romanization
        self.rawText = rawText
        self.isStatic = isStatic
    }

    var endMs: Int {
        if isInterlude, interludeEndMs > 0 {
            return interludeEndMs
        }
        if let lineEndMs = lineEndMs, lineEndMs > 0 {
            return lineEndMs
        }
        return words.last?.endMs ?? startMs
    }

    var duration: Int {
        max(endMs - startMs, 1)
    }

    var displayText: String {
        if isInterlude {
            return "• • •"
        }

        if let rawText = rawText, !rawText.isEmpty {
            return rawText
        }

        if words.isEmpty {
            return isSongwriter ? "Written by" : ""
        }

        var result = ""
        for group in wordGroups {
            let groupText = group.words.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined()
            guard !groupText.isEmpty else { continue }
            if !result.isEmpty && !result.hasSuffix(" ") && !result.hasSuffix("-") && !result.hasSuffix("–") && !result.hasSuffix("—") {
                result += " "
            }
            result += groupText
        }
        return result
    }
}

// MARK: - Lyrics Censor Engine
enum LyricsCensorEngine {
    private static let nWordRegex: NSRegularExpression = {
        // Matches forms of the n-word: nigga, niggas, niggaz, niggah, niggahs, nigger, niggers,
        // n*gga, n***a, n****r, etc.
        let pattern = #"(?i)\b(n+[i1!*]+g+[a4e3*]+[rshz]*|n+\*{2,}[aerhzs]*)\b"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    static func containsNWord(_ text: String) -> Bool {
        if text.isEmpty { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return nWordRegex.firstMatch(in: text, options: [], range: range) != nil
    }

    static func bleepText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return nWordRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "****")
    }

    static func censorLine(_ line: LyricLine) -> LyricLine {
        if line.isInterlude {
            return line
        }

        let censoredRaw = line.rawText.map { bleepText($0) }
        let censoredTrans = line.translation.map { bleepText($0) }
        let censoredRom = line.romanization.map { bleepText($0) }

        if line.words.isEmpty {
            return LyricLine(
                id: line.id,
                words: [],
                startMs: line.startMs,
                lineEndMs: line.lineEndMs,
                isWordSynced: line.isWordSynced,
                agent: line.agent,
                isBackground: line.isBackground,
                oppositeAligned: line.oppositeAligned,
                isSongwriter: line.isSongwriter,
                isInterlude: line.isInterlude,
                interludeEndMs: line.interludeEndMs,
                translation: censoredTrans,
                romanization: censoredRom,
                rawText: censoredRaw,
                isStatic: line.isStatic
            )
        }

        var newWords: [LyricWord] = []
        for group in line.wordGroups {
            let combined = group.words.map(\.text).joined()
            let cleanedCombined = combined
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "–", with: "")
                .replacingOccurrences(of: "—", with: "")

            let isGroupNWord = containsNWord(cleanedCombined)

            if isGroupNWord {
                let count = group.words.count
                if count == 1, let word = group.words.first {
                    let bleeped = bleepText(word.text)
                    let newLetters = makeCensoredLetters(word: word, starCount: 4)
                    newWords.append(LyricWord(
                        id: word.id,
                        text: bleeped,
                        startMs: word.startMs,
                        endMs: word.endMs,
                        isPartOfWord: word.isPartOfWord,
                        isLetterGroup: word.isLetterGroup,
                        letters: newLetters
                    ))
                } else if count == 2 {
                    // Split across 2 syllables: "**" + "**" = "****"
                    let w0 = group.words[0]
                    let w1 = group.words[1]
                    let w0Hyphen = w0.text.contains("-") ? "-" : ""
                    let w1Punct = extractTrailingPunctuation(from: w1.text)

                    newWords.append(LyricWord(
                        id: w0.id,
                        text: "**" + w0Hyphen,
                        startMs: w0.startMs,
                        endMs: w0.endMs,
                        isPartOfWord: w0.isPartOfWord,
                        isLetterGroup: w0.isLetterGroup,
                        letters: makeCensoredLetters(word: w0, starCount: 2)
                    ))
                    newWords.append(LyricWord(
                        id: w1.id,
                        text: "**" + w1Punct,
                        startMs: w1.startMs,
                        endMs: w1.endMs,
                        isPartOfWord: w1.isPartOfWord,
                        isLetterGroup: w1.isLetterGroup,
                        letters: makeCensoredLetters(word: w1, starCount: 2)
                    ))
                } else {
                    // 3 or more syllables: distribute 4 stars across syllables
                    for (idx, w) in group.words.enumerated() {
                        let stars = (idx == count - 1 && count == 3) ? "**" : "*"
                        let starCount = (idx == count - 1 && count == 3) ? 2 : 1
                        let hyphen = w.text.contains("-") ? "-" : ""
                        let punct = (idx == count - 1) ? extractTrailingPunctuation(from: w.text) : ""
                        newWords.append(LyricWord(
                            id: w.id,
                            text: stars + hyphen + punct,
                            startMs: w.startMs,
                            endMs: w.endMs,
                            isPartOfWord: w.isPartOfWord,
                            isLetterGroup: w.isLetterGroup,
                            letters: makeCensoredLetters(word: w, starCount: starCount)
                        ))
                    }
                }
            } else {
                for word in group.words {
                    if containsNWord(word.text) {
                        let bleeped = bleepText(word.text)
                        newWords.append(LyricWord(
                            id: word.id,
                            text: bleeped,
                            startMs: word.startMs,
                            endMs: word.endMs,
                            isPartOfWord: word.isPartOfWord,
                            isLetterGroup: word.isLetterGroup,
                            letters: makeCensoredLetters(word: word, starCount: 4)
                        ))
                    } else {
                        newWords.append(word)
                    }
                }
            }
        }

        return LyricLine(
            id: line.id,
            words: newWords,
            startMs: line.startMs,
            lineEndMs: line.lineEndMs,
            isWordSynced: line.isWordSynced,
            agent: line.agent,
            isBackground: line.isBackground,
            oppositeAligned: line.oppositeAligned,
            isSongwriter: line.isSongwriter,
            isInterlude: line.isInterlude,
            interludeEndMs: line.interludeEndMs,
            translation: censoredTrans,
            romanization: censoredRom,
            rawText: censoredRaw,
            isStatic: line.isStatic
        )
    }

    private static func extractTrailingPunctuation(from text: String) -> String {
        let punctChars = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-–—"))
        var result = ""
        for char in text.reversed() {
            if let scalar = char.unicodeScalars.first, punctChars.contains(scalar) {
                result = String(char) + result
            } else {
                break
            }
        }
        return result
    }

    private static func makeCensoredLetters(word: LyricWord, starCount: Int) -> [LyricLetter] {
        guard word.isLetterGroup, starCount > 0 else { return [] }
        let totalDur = max(word.endMs - word.startMs, starCount)
        let step = totalDur / starCount
        return (0..<starCount).map { i in
            let s = word.startMs + (i * step)
            let e = (i == starCount - 1) ? word.endMs : (s + step)
            return LyricLetter(char: "*", startMs: s, endMs: e)
        }
    }

    static func censorLines(_ lines: [LyricLine]) -> [LyricLine] {
        return lines.map { censorLine($0) }
    }
}

// MARK: - Background Vocals Engine

enum BackgroundVocalsEngine {
    static func processLines(_ lines: [LyricLine]) -> [LyricLine] {
        var result: [LyricLine] = []
        for line in lines {
            result.append(contentsOf: processLine(line))
        }
        return result
    }

    static func processLine(_ line: LyricLine) -> [LyricLine] {
        if line.isInterlude || line.isSongwriter {
            return [line]
        }

        if line.isBackground {
            return [cleanParenthesesFromBackgroundLine(line)]
        }

        if line.isWordSynced && !line.words.isEmpty {
            return processWordSyncedLine(line)
        }

        return processLineSyncedLine(line)
    }

    private static func cleanParenthesesFromBackgroundLine(_ line: LyricLine) -> LyricLine {
        var cleanWords = line.words
        if !cleanWords.isEmpty {
            cleanWords = cleanWords.compactMap { word in
                let cleaned = stripSurroundingParentheses(from: word.text)
                if cleaned.isEmpty { return nil }
                return LyricWord(
                    id: word.id,
                    text: cleaned,
                    startMs: word.startMs,
                    endMs: word.endMs,
                    isPartOfWord: word.isPartOfWord,
                    isLetterGroup: word.isLetterGroup,
                    letters: word.letters
                )
            }
        }
        let cleanRaw = line.rawText.map { stripSurroundingParentheses(from: $0) }
        return LyricLine(
            id: line.id,
            words: cleanWords,
            startMs: line.startMs,
            lineEndMs: line.lineEndMs,
            isWordSynced: line.isWordSynced && !cleanWords.isEmpty,
            agent: line.agent,
            isBackground: true,
            oppositeAligned: line.oppositeAligned,
            isSongwriter: line.isSongwriter,
            isInterlude: line.isInterlude,
            interludeEndMs: line.interludeEndMs,
            translation: line.translation,
            romanization: line.romanization,
            rawText: cleanRaw,
            isStatic: line.isStatic
        )
    }

    private static func processWordSyncedLine(_ line: LyricLine) -> [LyricLine] {
        let hasAnyParen = line.words.contains {
            $0.text.contains("(") || $0.text.contains(")") || $0.text.contains("（") || $0.text.contains("）")
        }
        guard hasAnyParen else { return [line] }

        var leadWords: [LyricWord] = []
        var bgWords: [LyricWord] = []
        var inParenthesis = false

        for word in line.words {
            let t = word.text.trimmingCharacters(in: .whitespaces)
            let opens = t.contains("(") || t.contains("（")
            let closes = t.contains(")") || t.contains("）")

            if opens {
                inParenthesis = true
            }

            let isWordInParen = inParenthesis || opens || closes

            let cleanedText = stripSurroundingParentheses(from: word.text)
            if !cleanedText.isEmpty {
                let cleanedWord = LyricWord(
                    id: word.id,
                    text: cleanedText,
                    startMs: word.startMs,
                    endMs: word.endMs,
                    isPartOfWord: word.isPartOfWord,
                    isLetterGroup: word.isLetterGroup,
                    letters: word.letters
                )
                if isWordInParen {
                    bgWords.append(cleanedWord)
                } else {
                    leadWords.append(cleanedWord)
                }
            }

            if closes {
                inParenthesis = false
            }
        }

        if bgWords.isEmpty {
            return [line]
        }

        if leadWords.isEmpty {
            let bgStart = bgWords.first?.startMs ?? line.startMs
            let bgEnd = bgWords.last?.endMs ?? line.endMs
            return [
                LyricLine(
                    id: line.id,
                    words: bgWords,
                    startMs: bgStart,
                    lineEndMs: bgEnd,
                    isWordSynced: true,
                    agent: line.agent,
                    isBackground: true,
                    oppositeAligned: line.oppositeAligned,
                    isSongwriter: line.isSongwriter,
                    isInterlude: line.isInterlude,
                    interludeEndMs: line.interludeEndMs,
                    translation: line.translation,
                    romanization: line.romanization,
                    rawText: bgWords.map(\.text).joined(separator: " "),
                    isStatic: line.isStatic
                )
            ]
        }

        let leadStart = leadWords.first?.startMs ?? line.startMs
        let leadEnd = leadWords.last?.endMs ?? line.endMs
        let leadLine = LyricLine(
            id: line.id,
            words: leadWords,
            startMs: leadStart,
            lineEndMs: leadEnd,
            isWordSynced: true,
            agent: line.agent,
            isBackground: false,
            oppositeAligned: line.oppositeAligned,
            isSongwriter: line.isSongwriter,
            isInterlude: line.isInterlude,
            interludeEndMs: line.interludeEndMs,
            translation: line.translation,
            romanization: line.romanization,
            rawText: leadWords.map(\.text).joined(separator: " "),
            isStatic: line.isStatic
        )

        let bgStart = bgWords.first?.startMs ?? line.startMs
        let bgEnd = bgWords.last?.endMs ?? line.endMs
        let bgLine = LyricLine(
            id: UUID(),
            words: bgWords,
            startMs: bgStart,
            lineEndMs: bgEnd,
            isWordSynced: true,
            agent: line.agent,
            isBackground: true,
            oppositeAligned: line.oppositeAligned,
            isSongwriter: false,
            isInterlude: false,
            interludeEndMs: -1,
            translation: nil,
            romanization: nil,
            rawText: bgWords.map(\.text).joined(separator: " "),
            isStatic: line.isStatic
        )

        return [leadLine, bgLine]
    }

    private static func processLineSyncedLine(_ line: LyricLine) -> [LyricLine] {
        let text = line.displayText
        guard text.contains("(") || text.contains("（") else { return [line] }
        if isInstrumentalText(text) { return [line] }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Case 1: Entire line is wrapped in parentheses
        if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) || (trimmed.hasPrefix("（") && trimmed.hasSuffix("）")) {
            let clean = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return [] }
            if isRepeatAnnotation(clean) { return [] }

            return [
                LyricLine(
                    id: line.id,
                    words: [],
                    startMs: line.startMs,
                    lineEndMs: line.lineEndMs,
                    isWordSynced: false,
                    agent: line.agent,
                    isBackground: true,
                    oppositeAligned: line.oppositeAligned,
                    isSongwriter: line.isSongwriter,
                    isInterlude: line.isInterlude,
                    interludeEndMs: line.interludeEndMs,
                    translation: line.translation,
                    romanization: line.romanization,
                    rawText: clean,
                    isStatic: line.isStatic
                )
            ]
        }

        // Case 2: Mixed lead and parenthesized text
        var leadParts: [String] = []
        var bgParts: [String] = []

        var currentLead = ""
        var currentBg = ""
        var inParen = false

        for ch in trimmed {
            if ch == "(" || ch == "（" {
                if !currentLead.isEmpty {
                    leadParts.append(currentLead)
                    currentLead = ""
                }
                inParen = true
            } else if ch == ")" || ch == "）" {
                if inParen && !currentBg.isEmpty {
                    bgParts.append(currentBg)
                    currentBg = ""
                }
                inParen = false
            } else {
                if inParen {
                    currentBg.append(ch)
                } else {
                    currentLead.append(ch)
                }
            }
        }

        if !currentLead.isEmpty {
            leadParts.append(currentLead)
        }
        if !currentBg.isEmpty {
            bgParts.append(currentBg)
        }

        let cleanLead = leadParts.joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanBgList = bgParts.map {
            $0.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty && !isRepeatAnnotation($0) }

        if cleanBgList.isEmpty {
            return [line]
        }

        if cleanLead.isEmpty {
            return cleanBgList.enumerated().map { (idx, bgText) in
                LyricLine(
                    id: idx == 0 ? line.id : UUID(),
                    words: [],
                    startMs: line.startMs,
                    lineEndMs: line.lineEndMs,
                    isWordSynced: false,
                    agent: line.agent,
                    isBackground: true,
                    oppositeAligned: line.oppositeAligned,
                    isSongwriter: line.isSongwriter,
                    isInterlude: line.isInterlude,
                    interludeEndMs: line.interludeEndMs,
                    translation: line.translation,
                    romanization: line.romanization,
                    rawText: bgText,
                    isStatic: line.isStatic
                )
            }
        }

        let leadLine = LyricLine(
            id: line.id,
            words: [],
            startMs: line.startMs,
            lineEndMs: line.lineEndMs,
            isWordSynced: false,
            agent: line.agent,
            isBackground: false,
            oppositeAligned: line.oppositeAligned,
            isSongwriter: line.isSongwriter,
            isInterlude: line.isInterlude,
            interludeEndMs: line.interludeEndMs,
            translation: line.translation,
            romanization: line.romanization,
            rawText: cleanLead,
            isStatic: line.isStatic
        )

        var resultLines: [LyricLine] = [leadLine]
        for bgText in cleanBgList {
            resultLines.append(
                LyricLine(
                    id: UUID(),
                    words: [],
                    startMs: line.startMs,
                    lineEndMs: line.lineEndMs,
                    isWordSynced: false,
                    agent: line.agent,
                    isBackground: true,
                    oppositeAligned: line.oppositeAligned,
                    isSongwriter: false,
                    isInterlude: false,
                    interludeEndMs: -1,
                    translation: nil,
                    romanization: nil,
                    rawText: bgText,
                    isStatic: line.isStatic
                )
            )
        }

        return resultLines
    }

    private static func isRepeatAnnotation(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.hasPrefix("x") && lower.dropFirst().allSatisfy(\.isNumber) { return true }
        if lower.hasSuffix("x") && lower.dropLast().allSatisfy(\.isNumber) { return true }
        return false
    }

    private static func stripSurroundingParentheses(from text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix("(") || s.hasPrefix("（") {
            s.removeFirst()
        }
        while s.hasSuffix(")") || s.hasSuffix("）") {
            s.removeLast()
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

struct VocalUnit {
    var leadLines: [LyricLine]
    var backgroundLines: [LyricLine]

    var allLines: [LyricLine] {
        leadLines + backgroundLines
    }

    var startMs: Int {
        allLines.map(\.startMs).min() ?? 0
    }

    var endMs: Int {
        allLines.map(\.endMs).max() ?? 0
    }
}

func isInstrumentalText(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed == "• • •" || trimmed == "..." || trimmed == "…" ||
           trimmed == "instrumental" || trimmed == "(instrumental)" ||
           trimmed == "[instrumental]" || trimmed == "♪" || trimmed == "♪♪" || trimmed == "♪♪♪"
}

func createInterludeDotWords(startMs: Int, endMs: Int) -> [LyricWord] {
    let total = max(endMs - startMs, 1000)
    let dotDur = Double(total) / 3.0

    let d0Start = startMs
    let d0End = startMs + Int(dotDur)
    let d1End = startMs + Int(2.0 * dotDur)
    let d2End = endMs

    return [
        LyricWord(text: "•", startMs: d0Start, endMs: d0End, isPartOfWord: false, isLetterGroup: false, letters: []),
        LyricWord(text: "•", startMs: d0End, endMs: d1End, isPartOfWord: false, isLetterGroup: false, letters: []),
        LyricWord(text: "•", startMs: d1End, endMs: d2End, isPartOfWord: false, isLetterGroup: false, letters: [])
    ]
}


struct SpicyAttributionUser: Hashable {
    let id: String?
    let username: String?
    let avatar: String?
    let url: String?
}

struct SpicyUploadAttribution: Hashable {
    let uploader: SpicyAttributionUser?
    let maker: SpicyAttributionUser?
}

struct ParsedLyrics {
    let lines: [LyricLine]
    let songwriters: [String]
    let source: String?
    let attribution: SpicyUploadAttribution?
    let isStatic: Bool

    init(
        lines: [LyricLine],
        songwriters: [String],
        source: String? = nil,
        attribution: SpicyUploadAttribution? = nil,
        isStatic: Bool = false
    ) {
        self.lines = lines
        self.songwriters = songwriters
        self.source = source
        self.attribution = attribution
        let nonMeta = lines.filter { !$0.isSongwriter && !$0.isInterlude }
        let looksUnsynced = !nonMeta.isEmpty && !nonMeta.contains(where: { $0.isWordSynced }) && nonMeta.allSatisfy { $0.isStatic || ($0.startMs == 0 && ($0.lineEndMs == nil || $0.lineEndMs == 0 || $0.lineEndMs! <= 3000)) }
        self.isStatic = isStatic || looksUnsynced
    }

    var hasWordSyncedLyrics: Bool {
        guard !isStatic else { return false }
        let wordSyncedLines = lines.filter {
            $0.isWordSynced && !$0.words.isEmpty && !$0.isInterlude && !$0.isSongwriter
        }
        return wordSyncedLines.count >= 2
    }
}

struct ImportedTrack: Identifiable, Hashable {
    let baseName: String
    let title: String
    let artist: String
    let audioURL: URL
    let lyricsURL: URL?

    var id: String {
        baseName.lowercased()
    }

    var hasLyrics: Bool {
        lyricsURL != nil
    }
}

struct TrackOverride: Codable {
    var title: String?
    var artist: String?
}

extension String {
    var splitArtistNames: [String] {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ["Unknown Artist"] }
        
        // Special-case common artist names with commas
        if trimmed.caseInsensitiveCompare("Tyler, The Creator") == .orderedSame {
            return ["Tyler, The Creator"]
        }
        
        // Split on common artist separators:
        // 1. Commas or semicolons: "," / ";"
        // 2. Slashes or backslashes with spaces: " / " or " \ "
        // 3. Ampersand with spaces: " & "
        // 4. Feature keywords: feat., feat, ft., ft, featuring, with, x (case-insensitive with whitespace)
        let pattern = #"(?:\s*[,;]\s*|\s+(?:/|\\|&|(?i:feat\.?|ft\.?|featuring|with|x))\s+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [trimmed]
        }
        
        let nsString = trimmed as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: trimmed, range: range)
        
        var results: [String] = []
        var lastEnd = 0
        
        for match in matches {
            let start = match.range.location
            if start > lastEnd {
                let substring = nsString.substring(with: NSRange(location: lastEnd, length: start - lastEnd))
                let clean = substring.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && !results.contains(clean) {
                    results.append(clean)
                }
            }
            lastEnd = match.range.location + match.range.length
        }
        
        if lastEnd < nsString.length {
            let substring = nsString.substring(with: NSRange(location: lastEnd, length: nsString.length - lastEnd))
            let clean = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !results.contains(clean) {
                results.append(clean)
            }
        }
        
        // Re-combine Tyler + The Creator if split by comma
        var combined: [String] = []
        var skipNext = false
        for i in 0..<results.count {
            if skipNext {
                skipNext = false
                continue
            }
            if results[i].localizedCaseInsensitiveCompare("Tyler") == .orderedSame &&
                i + 1 < results.count &&
                results[i + 1].localizedCaseInsensitiveCompare("The Creator") == .orderedSame {
                combined.append("Tyler, The Creator")
                skipNext = true
            } else {
                combined.append(results[i])
            }
        }
        
        return combined.isEmpty ? [trimmed] : combined
    }
}

// MARK: - Track Matching Utilities
enum TrackMatchUtils {
    static func normalizeCoreTitle(_ raw: String) -> String {
        var title = raw.lowercased()
        
        let patterns = [
            #"[\(\[](?:feat\.|ft\.|with|featuring)[^\)\]]*[\)\]]"#,
            #"[\(\[](?:remastered|remaster|deluxe|anniversary|bonus|expanded|edition)[^\)\]]*[\)\]]"#,
            #" - (?:remastered|remaster|deluxe|anniversary|bonus|single|radio edit).*"#,
            #"[\(\[](?:single version|radio edit|album version)[\)\]]"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                title = regex.stringByReplacingMatches(in: title, options: [], range: NSRange(location: 0, length: title.utf16.count), withTemplate: "")
            }
        }
        
        var coreWithoutAnyParens = title
        if let parenIdx = coreWithoutAnyParens.firstIndex(of: "(") {
            coreWithoutAnyParens = String(coreWithoutAnyParens[..<parenIdx])
        }
        if let bracketIdx = coreWithoutAnyParens.firstIndex(of: "[") {
            coreWithoutAnyParens = String(coreWithoutAnyParens[..<bracketIdx])
        }
        if let dashIdx = coreWithoutAnyParens.range(of: " - ") {
            coreWithoutAnyParens = String(coreWithoutAnyParens[..<dashIdx.lowerBound])
        }
        
        let cleaned = coreWithoutAnyParens.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let words = String(cleaned).split(whereSeparator: \.isWhitespace).map(String.init)
        return words.joined(separator: " ")
    }

    static func titlesMatch(requested: String, candidate: String) -> Bool {
        let reqCore = normalizeCoreTitle(requested)
        let candCore = normalizeCoreTitle(candidate)
        
        guard !reqCore.isEmpty && !candCore.isEmpty else { return false }
        if reqCore != candCore { return false }
        
        let versionKeywords = ["remix", "acoustic", "live", "instrumental", "cover", "vip", "karaoke"]
        let reqLower = requested.lowercased()
        let candLower = candidate.lowercased()
        
        for kw in versionKeywords {
            let reqHas = reqLower.contains(kw)
            let candHas = candLower.contains(kw)
            if candHas && !reqHas { return false }
            if reqHas && !candHas { return false }
        }
        
        return true
    }

    static func artistsMatch(requested: String, candidate: String) -> Bool {
        let reqClean = requested.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candClean = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !reqClean.isEmpty, !candClean.isEmpty else { return false }
        
        if reqClean == candClean { return true }
        if candClean.contains(reqClean) || reqClean.contains(candClean) { return true }
        
        let reqSplits = requested.splitArtistNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        let candSplits = candidate.splitArtistNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        
        for r in reqSplits {
            for c in candSplits {
                if r == c || (r.count >= 4 && c.count >= 4 && (r.contains(c) || c.contains(r))) {
                    return true
                }
            }
        }
        return false
    }

    static func durationsMatch(expected: Int?, candidate: Int?, maxDiffSeconds: Int = 15) -> Bool {
        guard let exp = expected, let cand = candidate, exp > 0, cand > 0 else {
            return true
        }
        return abs(exp - cand) <= maxDiffSeconds
    }
}

// MARK: - Library Song Model
struct LibrarySong: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var artistNames: String
    var albumName: String?
    var artworkUrl: String?
    var durationMs: Int
    var uri: String?
    var lastPlayedAt: Date
    var ttmlContent: String?
    var ttmlSavedAt: Date?
    var lyricsSource: String?
    var hasNoLyrics: Bool?
    var lastCheckedForLyricsAt: Date?

    // Song played within the last 30 days
    var isPlayedInLast30Days: Bool {
        Date().timeIntervalSince(lastPlayedAt) < 30 * 24 * 3600
    }

    // Has saved TTML — true if content is in-memory OR if we have a recorded save date
    // (meaning the .ttml file lives on disk even if ttmlContent was stripped from the index).
    var hasTTML: Bool {
        if let content = ttmlContent, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return ttmlSavedAt != nil
    }

    // Explicitly verified to have no lyrics (instrumental or unindexed)
    var isInstrumentalOrNoLyrics: Bool {
        return (hasNoLyrics == true) && !hasTTML
    }

    // Saved TTML is older than 30 days
    var isTTMLExpired: Bool {
        guard let savedAt = ttmlSavedAt else { return false }
        return Date().timeIntervalSince(savedAt) >= 30 * 24 * 3600
    }

    // Whether this song truly needs a lyrics update
    var needsUpdate: Bool {
        if isInstrumentalOrNoLyrics {
            return false
        }
        if hasTTML {
            return isTTMLExpired
        }
        // If it has no TTML and has never been checked for lyrics
        return lastCheckedForLyricsAt == nil
    }

    // Days until the 30-day TTML cache expires
    var daysUntilTTMLExpires: Int {
        guard let savedAt = ttmlSavedAt else { return 0 }
        let elapsed = Date().timeIntervalSince(savedAt)
        let remaining = (30 * 24 * 3600) - elapsed
        return max(0, Int(ceil(remaining / (24 * 3600))))
    }

    // Days since last played
    var daysAgoPlayed: Int {
        let elapsed = Date().timeIntervalSince(lastPlayedAt)
        return max(0, Int(floor(elapsed / (24 * 3600))))
    }

    var playedAgoDescription: String {
        let days = daysAgoPlayed
        if days == 0 {
            return "Today"
        } else if days == 1 {
            return "Yesterday"
        } else {
            return "\(days)d ago"
        }
    }
}

