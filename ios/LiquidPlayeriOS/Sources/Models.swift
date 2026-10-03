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
    let id = UUID()
    let char: String
    let startMs: Int
    let endMs: Int
}

struct LyricWord: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let startMs: Int
    let endMs: Int
    let isPartOfWord: Bool
    let isLetterGroup: Bool
    let letters: [LyricLetter]

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
    let id = UUID()
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

