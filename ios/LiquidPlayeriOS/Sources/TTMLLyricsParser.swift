import Foundation

enum TTMLLyricsParser {
    static func parse(data: Data) throws -> ParsedLyrics {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate

        guard parser.parse() else {
            throw delegate.error ?? parser.parserError ?? NSError(
                domain: "LiquidPlayeriOS.TTMLParser",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse TTML lyrics."]
            )
        }

        return delegate.result()
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    struct SpanContext {
        let begin: Int?
        let end: Int?
        let hasExplicitTiming: Bool
        let isBackground: Bool
        let isTranslation: Bool
        let isRoman: Bool
    }

    var vocalUnits: [VocalUnit] = []
    var songwriters: [String] = []
    var source: String? = nil
    var uploader: SpicyAttributionUser? = nil
    var maker: SpicyAttributionUser? = nil
    var error: Error?

    private var defaultAgent: String? = "v1"
    private var divAgentStack: [String?] = []
    private var agentOrder: [String] = []
    private var inSongwriter = false
    private var inSource = false
    private var currentParagraph: ParagraphState?

    func result() -> ParsedLyrics {
        var units = vocalUnits

        // Final verification: if fewer than 2 lines have word sync in the entire song (and song has >= 2 lines),
        // treat the whole song as line-synced to prevent false karaoke animation.
        let allVocalLines = units.flatMap(\.allLines)
        let hasAnyTiming = allVocalLines.contains { $0.startMs > 0 || ($0.lineEndMs ?? 0) > 0 || $0.isWordSynced }
        let isStatic = !hasAnyTiming && !allVocalLines.isEmpty

        // Final verification: if fewer than 2 lines have word sync in the entire song (and song has >= 2 lines),
        // treat the whole song as line-synced to prevent false karaoke animation.
        let wordSyncedCount = allVocalLines.filter { $0.isWordSynced && !$0.words.isEmpty && !$0.isSongwriter && !$0.isInterlude }.count
        if isStatic || (wordSyncedCount < 2 && allVocalLines.count >= 2) {
            let makeLineSynced: (LyricLine) -> LyricLine = { line in
                if line.isSongwriter || line.isInterlude { return line }
                return LyricLine(
                    words: [],
                    startMs: line.startMs,
                    lineEndMs: line.endMs,
                    isWordSynced: false,
                    agent: line.agent,
                    isBackground: line.isBackground,
                    oppositeAligned: line.oppositeAligned,
                    isSongwriter: false,
                    isInterlude: false,
                    interludeEndMs: -1,
                    translation: line.translation,
                    romanization: line.romanization,
                    rawText: line.displayText,
                    isStatic: isStatic || line.isStatic
                )
            }

            units = units.map { unit in
                VocalUnit(
                    leadLines: unit.leadLines.map(makeLineSynced),
                    backgroundLines: unit.backgroundLines.map(makeLineSynced)
                )
            }
        } else {
            // For word-synced songs, ensure lines containing only a single word (e.g. ad-libs, "Yeah", short background lines)
            // have a LyricWord token synthesized if missing, so they animate with the same karaoke effects as other lines.
            let synthesizeSingleWordIfMissing: (LyricLine) -> LyricLine = { line in
                if line.isSongwriter || line.isInterlude || line.isWordSynced || !line.words.isEmpty {
                    return line
                }
                let tokens = line.displayText.split(whereSeparator: \.isWhitespace).map(String.init)
                guard tokens.count == 1, let singleWord = tokens.first, !singleWord.isEmpty else {
                    return line
                }
                let wStart = line.startMs
                let wEnd = max(wStart + 500, line.endMs)
                let duration = max(wEnd - wStart, 1)
                let isLetterGroup = duration >= 1200 && singleWord.count > 1 && !singleWord.contains(" ")
                let letters: [LyricLetter]
                if isLetterGroup {
                    let count = max(singleWord.count, 1)
                    let letterDur = Double(duration) / Double(count)
                    letters = singleWord.enumerated().map { off, char in
                        LyricLetter(
                            char: String(char),
                            startMs: wStart + Int(Double(off) * letterDur),
                            endMs: off == count - 1 ? wEnd : wStart + Int(Double(off + 1) * letterDur)
                        )
                    }
                } else {
                    letters = []
                }
                let word = LyricWord(
                    text: singleWord,
                    startMs: wStart,
                    endMs: wEnd,
                    isPartOfWord: false,
                    isLetterGroup: isLetterGroup,
                    letters: letters
                )
                return LyricLine(
                    words: [word],
                    startMs: wStart,
                    lineEndMs: wEnd,
                    isWordSynced: true,
                    agent: line.agent,
                    isBackground: line.isBackground,
                    oppositeAligned: line.oppositeAligned,
                    isSongwriter: false,
                    isInterlude: false,
                    interludeEndMs: -1,
                    translation: line.translation,
                    romanization: line.romanization,
                    rawText: line.displayText
                )
            }

            units = units.map { unit in
                VocalUnit(
                    leadLines: unit.leadLines.map(synthesizeSingleWordIfMissing),
                    backgroundLines: unit.backgroundLines.map(synthesizeSingleWordIfMissing)
                )
            }
        }

        if !isStatic {
            units.sort { $0.startMs < $1.startMs }
        }

        var allLines: [LyricLine] = []

        // 1. Intro interlude (only for timed synced songs)
        if !isStatic, let first = units.first, first.startMs >= 3000 {
            let dotWords = createInterludeDotWords(startMs: 0, endMs: first.startMs)
            let lead = first.leadLines.first
            allLines.append(
                LyricLine(
                    words: dotWords,
                    startMs: 0,
                    agent: lead?.agent,
                    isBackground: false,
                    oppositeAligned: lead?.oppositeAligned ?? false,
                    isSongwriter: false,
                    isInterlude: true,
                    interludeEndMs: first.startMs,
                    translation: nil,
                    romanization: nil
                )
            )
        }

        // 2. Units and inter-unit interludes
        for index in 0..<units.count {
            let unit = units[index]

            // Always append all lines in this vocal unit together:
            // lead line first, followed immediately by its background vocals!
            allLines.append(contentsOf: unit.allLines)

            if !isStatic, index < units.count - 1 {
                let nextUnit = units[index + 1]
                let gapStart = unit.endMs  // All vocals in current unit (lead + bg) have finished!
                let gapEnd = nextUnit.startMs // Next vocal unit starts!

                if gapEnd - gapStart >= 3000 {
                    let dotWords = createInterludeDotWords(startMs: gapStart, endMs: gapEnd)
                    let nextLead = nextUnit.leadLines.first
                    allLines.append(
                        LyricLine(
                            words: dotWords,
                            startMs: gapStart,
                            agent: nextLead?.agent,
                            isBackground: false,
                            oppositeAligned: nextLead?.oppositeAligned ?? false,
                            isSongwriter: false,
                            isInterlude: true,
                            interludeEndMs: gapEnd,
                            translation: nil,
                            romanization: nil
                        )
                    )
                }
            }
        }

        if !songwriters.isEmpty {
            let lastLineEnd = allLines.map(\.endMs).max() ?? 0
            let text = "Written by \(songwriters.joined(separator: ", "))"
            let tokens = text.split(separator: " ").map(String.init)
            let words = tokens.map { token in
                LyricWord(
                    text: token,
                    startMs: lastLineEnd,
                    endMs: lastLineEnd + 1000,
                    isPartOfWord: false,
                    isLetterGroup: false,
                    letters: []
                )
            }

            allLines.append(
                LyricLine(
                    words: words,
                    startMs: lastLineEnd,
                    agent: nil,
                    isBackground: false,
                    oppositeAligned: false,
                    isSongwriter: true,
                    isInterlude: false,
                    interludeEndMs: -1,
                    translation: nil,
                    romanization: nil
                )
            )
        }

        let attribution: SpicyUploadAttribution? = (uploader != nil || maker != nil) ? SpicyUploadAttribution(uploader: uploader, maker: maker) : nil
        let processedLines = BackgroundVocalsEngine.processLines(allLines)
        return ParsedLyrics(lines: processedLines, songwriters: songwriters, source: source, attribution: attribution, isStatic: isStatic)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalizedName(elementName, qName)

        switch name {
        case "songwriter":
            inSongwriter = true
        case "source":
            inSource = true
        case "uploader":
            let cleanUname = (attributeDict["username"] ?? attributeDict["name"] ?? attributeDict["displayName"] ?? attributeDict["user"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanUid = (attributeDict["id"] ?? attributeDict["xml:id"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAvatar = (attributeDict["avatar"] ?? attributeDict["avatarUrl"] ?? attributeDict["avatar_url"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanUrl = (attributeDict["url"] ?? attributeDict["profile"] ?? attributeDict["profileUrl"])?.trimmingCharacters(in: .whitespacesAndNewlines)

            let finalUname = (cleanUname?.isEmpty == false) ? cleanUname : cleanUid
            let finalUid = (cleanUid?.isEmpty == false) ? cleanUid : nil
            let finalAvatar = (cleanAvatar?.isEmpty == false) ? cleanAvatar : nil
            let finalUrl = (cleanUrl?.isEmpty == false) ? cleanUrl : nil

            if finalUname != nil || finalUid != nil {
                uploader = SpicyAttributionUser(
                    id: finalUid,
                    username: finalUname,
                    avatar: finalAvatar,
                    url: finalUrl
                )
            }
        case "maker":
            let cleanMname = (attributeDict["username"] ?? attributeDict["name"] ?? attributeDict["displayName"] ?? attributeDict["user"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanMid = (attributeDict["id"] ?? attributeDict["xml:id"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAvatar = (attributeDict["avatar"] ?? attributeDict["avatarUrl"] ?? attributeDict["avatar_url"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanUrl = (attributeDict["url"] ?? attributeDict["profile"] ?? attributeDict["profileUrl"])?.trimmingCharacters(in: .whitespacesAndNewlines)

            let finalMname = (cleanMname?.isEmpty == false) ? cleanMname : cleanMid
            let finalMid = (cleanMid?.isEmpty == false) ? cleanMid : nil
            let finalAvatar = (cleanAvatar?.isEmpty == false) ? cleanAvatar : nil
            let finalUrl = (cleanUrl?.isEmpty == false) ? cleanUrl : nil

            if finalMname != nil || finalMid != nil {
                maker = SpicyAttributionUser(
                    id: finalMid,
                    username: finalMname,
                    avatar: finalAvatar,
                    url: finalUrl
                )
            }
        case "div":
            let divAgent = attributeDict["agent"] ?? attributeDict["ttm:agent"]
            registerAgent(divAgent)
            divAgentStack.append(divAgent)
        case "agent":
            let identifier = attributeDict["xml:id"] ?? attributeDict["id"]
            registerAgent(identifier)
            if identifier == "v1" || identifier == "1" {
                defaultAgent = identifier
            }
        case "p":
            let currentDivAgent = divAgentStack.reversed().compactMap { $0 }.first
            let explicitAgent = attributeDict["agent"] ?? attributeDict["ttm:agent"]
            let agent = explicitAgent ?? currentDivAgent
            registerAgent(agent)
            if agent == "v1" || agent == "1" {
                defaultAgent = agent
            }
            currentParagraph = ParagraphState(
                beginMs: parseTimeMs(attributeDict["begin"]) ?? 0,
                endMs: parseTimeMs(attributeDict["end"]) ?? 0,
                agent: agent,
                defaultAgent: defaultAgent ?? "v1",
                agentOrder: agentOrder
            )
        case "span":
            let spanAgent = attributeDict["agent"] ?? attributeDict["ttm:agent"]
            registerAgent(spanAgent)
            currentParagraph?.pushSpan(attributes: attributeDict)
        case "br":
            currentParagraph?.insertLineBreak()
        default:
            break
        }
    }

    private func registerAgent(_ raw: String?) {
        guard let clean = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !clean.isEmpty else { return }
        if !agentOrder.contains(clean) {
            agentOrder.append(clean)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inSource {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                source = (source != nil ? "\(source!) " : "") + trimmed
            }
            return
        }

        if inSongwriter {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                songwriters.append(trimmed)
            }
            return
        }

        currentParagraph?.appendText(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalizedName(elementName, qName)

        switch name {
        case "div":
            if !divAgentStack.isEmpty {
                divAgentStack.removeLast()
            }
        case "source":
            inSource = false
        case "songwriter":
            inSongwriter = false
        case "span":
            currentParagraph?.popSpan()
        case "p":
            if var paragraph = currentParagraph {
                paragraph.flushPendingText()
                let pLines = paragraph.makeLines()
                let leadLines = pLines.filter { !$0.isBackground }
                let bgLines = pLines.filter { $0.isBackground }
                if !leadLines.isEmpty || !bgLines.isEmpty {
                    vocalUnits.append(VocalUnit(leadLines: leadLines, backgroundLines: bgLines))
                }
            }
            currentParagraph = nil
        default:
            break
        }
    }

    private func normalizedName(_ elementName: String, _ qName: String?) -> String {
        let raw = qName ?? elementName
        return raw.split(separator: ":").last.map(String.init) ?? raw
    }
}

private struct ParagraphState {
    let beginMs: Int
    let endMs: Int
    let agent: String?
    let defaultAgent: String?
    var agentOrder: [String]

    struct LineDraft {
        var words: [LyricWord] = []
        var rawText: String = ""
        var hasExplicitWordTiming: Bool = false
    }

    private var leadLines: [LineDraft] = [LineDraft()]
    private var backgroundGroups: [LineDraft] = []
    private var currentBackgroundDraft: LineDraft?
    private var inBackgroundSpan = false
    private var spanAgent: String?
    private var currentTranslation = ""
    private var currentRomanization = ""
    private var stack: [ParserDelegate.SpanContext]
    private var leadHadWhitespace = true
    private var backgroundHadWhitespace = true
    private var pendingText = ""

    init(beginMs: Int, endMs: Int, agent: String?, defaultAgent: String?, agentOrder: [String] = []) {
        self.beginMs = beginMs
        self.endMs = endMs
        self.agent = agent
        self.defaultAgent = defaultAgent
        self.agentOrder = agentOrder
        self.stack = [ParserDelegate.SpanContext(begin: beginMs, end: endMs, hasExplicitTiming: false, isBackground: false, isTranslation: false, isRoman: false)]
    }

    mutating func pushSpan(attributes: [String: String]) {
        flushPendingText()
        if let sa = attributes["agent"] ?? attributes["ttm:agent"] {
            spanAgent = sa
            let clean = sa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !clean.isEmpty && !agentOrder.contains(clean) {
                agentOrder.append(clean)
            }
        }
        let inherited = stack.last ?? ParserDelegate.SpanContext(begin: beginMs, end: endMs, hasExplicitTiming: false, isBackground: false, isTranslation: false, isRoman: false)
        let hasExplicitTiming = (attributes["begin"] != nil)
        let begin = parseTimeMs(attributes["begin"]) ?? inherited.begin
        let end = parseTimeMs(attributes["end"]) ?? inherited.end
        let role = attributes["role"] ?? attributes["ttm:role"]
        let isBackground = role == "x-bg" || inherited.isBackground
        let isTranslation = role == "x-translation" || inherited.isTranslation
        let isRoman = role == "x-roman" || inherited.isRoman

        if isBackground && currentBackgroundDraft == nil {
            currentBackgroundDraft = LineDraft()
            backgroundHadWhitespace = true
        }

        inBackgroundSpan = isBackground
        stack.append(ParserDelegate.SpanContext(begin: begin, end: end, hasExplicitTiming: hasExplicitTiming, isBackground: isBackground, isTranslation: isTranslation, isRoman: isRoman))
    }

    mutating func popSpan() {
        guard !stack.isEmpty else {
            return
        }

        flushPendingText()
        let popped = stack.removeLast()
        let nextIsBackground = stack.last?.isBackground ?? false
        if popped.isBackground && !nextIsBackground {
            if let currentBackgroundDraft, (!currentBackgroundDraft.words.isEmpty || !currentBackgroundDraft.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                backgroundGroups.append(currentBackgroundDraft)
            }
            self.currentBackgroundDraft = nil
            inBackgroundSpan = false
            backgroundHadWhitespace = true
        } else {
            inBackgroundSpan = nextIsBackground
        }
    }

    mutating func insertLineBreak() {
        flushPendingText()

        if inBackgroundSpan {
            if let currentBackgroundDraft, (!currentBackgroundDraft.words.isEmpty || !currentBackgroundDraft.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                backgroundGroups.append(currentBackgroundDraft)
                self.currentBackgroundDraft = LineDraft()
            }
            backgroundHadWhitespace = true
            return
        }

        if let currentLine = leadLines.last, (!currentLine.words.isEmpty || !currentLine.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            leadLines.append(LineDraft())
        }
        leadHadWhitespace = true
    }

    mutating func appendText(_ rawText: String) {
        pendingText += rawText
    }

    mutating func flushPendingText() {
        let rawText = pendingText
        pendingText = ""

        let context = stack.last ?? ParserDelegate.SpanContext(begin: beginMs, end: endMs, hasExplicitTiming: false, isBackground: false, isTranslation: false, isRoman: false)
        let isBackgroundToken = context.isBackground || inBackgroundSpan

        if context.isTranslation {
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if !currentTranslation.isEmpty {
                    currentTranslation += " "
                }
                currentTranslation += trimmed
            }
            return
        }

        if context.isRoman {
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if !currentRomanization.isEmpty {
                    currentRomanization += " "
                }
                currentRomanization += trimmed
            }
            return
        }

        if rawText.isEmpty {
            return
        }

        // Always accumulate raw text into the current line draft
        if isBackgroundToken {
            if currentBackgroundDraft == nil {
                currentBackgroundDraft = LineDraft()
            }
            currentBackgroundDraft?.rawText.append(rawText)
        } else {
            if leadLines.isEmpty {
                leadLines = [LineDraft()]
            }
            leadLines[leadLines.count - 1].rawText.append(rawText)
        }

        if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !rawText.contains("\n") && !rawText.contains("\r") && rawText.contains(where: \.isWhitespace) {
                if isBackgroundToken {
                    backgroundHadWhitespace = true
                } else {
                    leadHadWhitespace = true
                }
            }
            return
        }

        // CRITICAL: Only construct LyricWord instances if this span has EXPLICIT timing.
        // If the span or paragraph does not have word-level timestamps, do NOT fake words
        // by dividing paragraph duration by word count.
        guard context.hasExplicitTiming else {
            if !rawText.contains("\n") && !rawText.contains("\r") && rawText.contains(where: \.isWhitespace) {
                if isBackgroundToken {
                    backgroundHadWhitespace = true
                } else {
                    leadHadWhitespace = true
                }
            }
            return
        }

        let startsWithSpace = rawText.first?.isWhitespace == true
        let endsWithSpace = rawText.last?.isWhitespace == true
        if startsWithSpace {
            if isBackgroundToken {
                backgroundHadWhitespace = true
            } else {
                leadHadWhitespace = true
            }
        }

        var trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isBackgroundToken {
            trimmed = trimmed.replacingOccurrences(of: #"^\("#, with: "", options: .regularExpression)
            trimmed = trimmed.replacingOccurrences(of: #"\)$"#, with: "", options: .regularExpression)
        }

        if trimmed.isEmpty {
            if endsWithSpace {
                if isBackgroundToken {
                    backgroundHadWhitespace = true
                } else {
                    leadHadWhitespace = true
                }
            }
            return
        }

        let spaceTokens = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        var wordsToAdd: [(String, Bool, Bool)] = []
        for (tokenIndex, token) in spaceTokens.enumerated() {
            let subTokens = splitKeepingTrailingHyphen(token)
            for (subIndex, subToken) in subTokens.enumerated() {
                let isLastSub = subIndex == subTokens.count - 1
                let isFirstSub = subIndex == 0
                let isFirstToken = tokenIndex == 0
                let isLastToken = tokenIndex == spaceTokens.count - 1

                let hadWhitespaceBefore: Bool
                if !isFirstSub {
                    hadWhitespaceBefore = false
                } else if isFirstToken {
                    hadWhitespaceBefore = isBackgroundToken ? backgroundHadWhitespace : leadHadWhitespace
                } else {
                    hadWhitespaceBefore = true
                }

                let endsWithHyphen = subToken.hasSuffix("-") || subToken.hasSuffix("–") || subToken.hasSuffix("—")
                let isPartOfWord: Bool
                if !isLastSub || endsWithHyphen {
                    // Split mid-token or ends with hyphen: continues into next syllable
                    isPartOfWord = true
                } else if !isLastToken {
                    // Followed by whitespace within the same span: completes word
                    isPartOfWord = false
                } else {
                    // Last token in the span: continues if the span does NOT end with whitespace
                    isPartOfWord = !endsWithSpace
                }

                wordsToAdd.append((subToken, isPartOfWord, hadWhitespaceBefore))
            }
        }

        let start = context.begin ?? beginMs
        let end = context.end ?? (start + 1000)
        let duration = max(end - start, 0)
        let chunkDuration = wordsToAdd.isEmpty ? duration : duration / wordsToAdd.count

        for (index, entry) in wordsToAdd.enumerated() {
            let wordStart = start + (index * chunkDuration)
            let wordEnd = index == wordsToAdd.count - 1 ? end : start + ((index + 1) * chunkDuration)
            let wordDuration = wordEnd - wordStart
            let token = entry.0
            let isLetterGroup = wordDuration >= 1000 && token.count > 1

            let letters: [LyricLetter]
            if isLetterGroup {
                let count = max(token.count, 1)
                let letterDuration = Double(wordDuration) / Double(count)
                letters = token.enumerated().map { offset, character in
                    LyricLetter(
                        char: String(character),
                        startMs: wordStart + Int(Double(offset) * letterDuration),
                        endMs: offset == count - 1 ? wordEnd : wordStart + Int(Double(offset + 1) * letterDuration)
                    )
                }
            } else {
                letters = []
            }

            let word = LyricWord(
                text: token,
                startMs: wordStart,
                endMs: wordEnd,
                isPartOfWord: entry.1,
                isLetterGroup: isLetterGroup,
                letters: letters
            )

            let hadWhitespaceBefore = entry.2

            if isBackgroundToken {
                if !hadWhitespaceBefore, let bg = currentBackgroundDraft, !bg.words.isEmpty {
                    let lastIdx = bg.words.count - 1
                    let prev = bg.words[lastIdx]
                    currentBackgroundDraft?.words[lastIdx] = LyricWord(
                        text: prev.text,
                        startMs: prev.startMs,
                        endMs: prev.endMs,
                        isPartOfWord: true,
                        isLetterGroup: prev.isLetterGroup,
                        letters: prev.letters
                    )
                } else if hadWhitespaceBefore, let bg = currentBackgroundDraft, !bg.words.isEmpty {
                    let lastIdx = bg.words.count - 1
                    let prev = bg.words[lastIdx]
                    if !prev.text.hasSuffix("-") && !prev.text.hasSuffix("–") && !prev.text.hasSuffix("—") {
                        currentBackgroundDraft?.words[lastIdx] = LyricWord(
                            text: prev.text,
                            startMs: prev.startMs,
                            endMs: prev.endMs,
                            isPartOfWord: false,
                            isLetterGroup: prev.isLetterGroup,
                            letters: prev.letters
                        )
                    }
                }
                currentBackgroundDraft?.words.append(word)
                currentBackgroundDraft?.hasExplicitWordTiming = true
            } else {
                let lineIdx = leadLines.count - 1
                if !hadWhitespaceBefore, lineIdx >= 0, !leadLines[lineIdx].words.isEmpty {
                    let lastIdx = leadLines[lineIdx].words.count - 1
                    let prev = leadLines[lineIdx].words[lastIdx]
                    leadLines[lineIdx].words[lastIdx] = LyricWord(
                        text: prev.text,
                        startMs: prev.startMs,
                        endMs: prev.endMs,
                        isPartOfWord: true,
                        isLetterGroup: prev.isLetterGroup,
                        letters: prev.letters
                    )
                } else if hadWhitespaceBefore, lineIdx >= 0, !leadLines[lineIdx].words.isEmpty {
                    let lastIdx = leadLines[lineIdx].words.count - 1
                    let prev = leadLines[lineIdx].words[lastIdx]
                    if !prev.text.hasSuffix("-") && !prev.text.hasSuffix("–") && !prev.text.hasSuffix("—") {
                        leadLines[lineIdx].words[lastIdx] = LyricWord(
                            text: prev.text,
                            startMs: prev.startMs,
                            endMs: prev.endMs,
                            isPartOfWord: false,
                            isLetterGroup: prev.isLetterGroup,
                            letters: prev.letters
                        )
                    }
                }
                leadLines[lineIdx].words.append(word)
                leadLines[lineIdx].hasExplicitWordTiming = true
            }
        }

        if isBackgroundToken {
            backgroundHadWhitespace = endsWithSpace
        } else {
            leadHadWhitespace = endsWithSpace
        }
    }

    func makeLines() -> [LyricLine] {
        let effectiveAgent = agent ?? spanAgent
        let oppositeAligned: Bool = {
            guard let raw = effectiveAgent?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
                return false
            }
            if raw.hasPrefix("v"), let num = Int(raw.dropFirst()) {
                return num % 2 == 0
            }
            if let num = Int(raw) {
                return num % 2 == 0
            }
            if let lastDigit = raw.compactMap({ $0.wholeNumberValue }).last {
                return lastDigit % 2 == 0
            }
            if let idx = agentOrder.firstIndex(of: raw) {
                return (idx + 1) % 2 == 0
            }
            if raw == "v1" || raw == "1" {
                return false
            }
            return defaultAgent != nil && raw != defaultAgent
        }()
        let lineAgent = effectiveAgent ?? (oppositeAligned ? "v2" : "v1")
        var result: [LyricLine] = []

        for draft in leadLines {
            let trimmedRaw = draft.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.words.isEmpty && trimmedRaw.isEmpty {
                continue
            }

            var words = draft.words
            if let lastIdx = words.indices.last, words[lastIdx].isPartOfWord {
                let last = words[lastIdx]
                words[lastIdx] = LyricWord(
                    text: last.text,
                    startMs: last.startMs,
                    endMs: last.endMs,
                    isPartOfWord: false,
                    isLetterGroup: last.isLetterGroup,
                    letters: last.letters
                )
            }
            let durations = words.map { $0.endMs - $0.startMs }
            let isArtificialDivision = words.count >= 3 && Set(durations).count == 1
            let distinctStarts = words.count > 1 ? Set(words.map(\.startMs)).count > 1 : true
            let isWordSynced = draft.hasExplicitWordTiming && !words.isEmpty && distinctStarts && !isArtificialDivision

            let normalizedRaw = trimmedRaw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let effectiveRawText = !normalizedRaw.isEmpty ? normalizedRaw : words.map(\.text).joined(separator: " ")
            let isInstrumental = isInstrumentalText(effectiveRawText)
            let lineStart = max(0, (!isInstrumental && isWordSynced) ? (words.first?.startMs ?? beginMs) : beginMs)
            let lineEnd = max(lineStart + 500, (!isInstrumental && isWordSynced) ? (words.last?.endMs ?? endMs) : endMs)
            let interludeWords = isInstrumental ? createInterludeDotWords(startMs: lineStart, endMs: lineEnd) : (isWordSynced ? words : [])

            result.append(
                LyricLine(
                    words: interludeWords,
                    startMs: lineStart,
                    lineEndMs: lineEnd,
                    isWordSynced: isInstrumental ? true : isWordSynced,
                    agent: lineAgent,
                    isBackground: false,
                    oppositeAligned: oppositeAligned,
                    isSongwriter: false,
                    isInterlude: isInstrumental,
                    interludeEndMs: isInstrumental ? lineEnd : -1,
                    translation: currentTranslation.isEmpty ? nil : currentTranslation,
                    romanization: currentRomanization.isEmpty ? nil : currentRomanization,
                    rawText: isInstrumental ? "• • •" : effectiveRawText
                )
            )
        }

        var allBgGroups = backgroundGroups
        if let current = currentBackgroundDraft, (!current.words.isEmpty || !current.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            allBgGroups.append(current)
        }

        for draft in allBgGroups {
            var trimmedRaw = draft.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedRaw.hasPrefix("(") && trimmedRaw.hasSuffix(")") {
                trimmedRaw = String(trimmedRaw.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if draft.words.isEmpty && trimmedRaw.isEmpty {
                continue
            }

            var words = draft.words
            if let lastIdx = words.indices.last, words[lastIdx].isPartOfWord {
                let last = words[lastIdx]
                words[lastIdx] = LyricWord(
                    text: last.text,
                    startMs: last.startMs,
                    endMs: last.endMs,
                    isPartOfWord: false,
                    isLetterGroup: last.isLetterGroup,
                    letters: last.letters
                )
            }
            let durations = words.map { $0.endMs - $0.startMs }
            let isArtificialDivision = words.count >= 3 && Set(durations).count == 1
            let distinctStarts = words.count > 1 ? Set(words.map(\.startMs)).count > 1 : true
            let isWordSynced = draft.hasExplicitWordTiming && !words.isEmpty && distinctStarts && !isArtificialDivision

            let normalizedBgRaw = trimmedRaw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let effectiveRawText = !normalizedBgRaw.isEmpty ? normalizedBgRaw : words.map(\.text).joined(separator: " ")
            let groupStart = max(0, isWordSynced ? (words.first?.startMs ?? beginMs) : beginMs)
            let groupEnd = max(groupStart + 500, isWordSynced ? (words.last?.endMs ?? endMs) : endMs)

            result.append(
                LyricLine(
                    words: isWordSynced ? words : [],
                    startMs: groupStart,
                    lineEndMs: groupEnd,
                    isWordSynced: isWordSynced,
                    agent: lineAgent,
                    isBackground: true,
                    oppositeAligned: oppositeAligned,
                    isSongwriter: false,
                    isInterlude: false,
                    interludeEndMs: -1,
                    translation: nil,
                    romanization: nil,
                    rawText: effectiveRawText
                )
            )
        }

        return result
    }

    private func splitKeepingTrailingHyphen(_ token: String) -> [String] {
        var result: [String] = []
        var current = ""
        for char in token {
            current.append(char)
            if char == "-" || char == "–" || char == "—" || char == "/" {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

private func parseTimeMs(_ time: String?) -> Int? {
    guard let time else {
        return nil
    }

    var trimmed = time.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    
    // Check if it's an offset-time ending in "ms"
    if trimmed.hasSuffix("ms") {
        let valueString = trimmed.dropLast(2)
        if let msValue = Double(valueString) {
            return Int(msValue.rounded())
        }
        return nil
    }
    
    // Check other suffix endings like "s", "m", "h"
    var scale: Double = 1000.0 // default is seconds if it's just a number
    if trimmed.hasSuffix("s") {
        trimmed = String(trimmed.dropLast())
        scale = 1000.0
    } else if trimmed.hasSuffix("m") {
        trimmed = String(trimmed.dropLast())
        scale = 60.0 * 1000.0
    } else if trimmed.hasSuffix("h") {
        trimmed = String(trimmed.dropLast())
        scale = 3600.0 * 1000.0
    }

    let parts = trimmed.split(separator: ":").map(String.init)
    
    if parts.count == 1 {
        // Just seconds/fraction or a raw number
        if let val = Double(parts[0]) {
            return max(0, Int((val * scale).rounded()))
        }
        return nil
    }
    
    if parts.count == 2 {
        // mm:ss.ms
        let minutes = Int(parts[0]) ?? 0
        let secondsParts = parts[1].split(separator: ".", maxSplits: 1).map(String.init)
        let seconds = Int(secondsParts[0]) ?? 0
        let milliseconds = secondsParts.count > 1 ? paddedMilliseconds(secondsParts[1]) : 0
        return max(0, ((minutes * 60) + seconds) * 1000 + milliseconds)
    }

    if parts.count == 3 {
        // hh:mm:ss.ms
        let hours = Int(parts[0]) ?? 0
        let minutes = Int(parts[1]) ?? 0
        let secondsParts = parts[2].split(separator: ".", maxSplits: 1).map(String.init)
        let seconds = Int(secondsParts[0]) ?? 0
        let milliseconds = secondsParts.count > 1 ? paddedMilliseconds(secondsParts[1]) : 0
        return max(0, ((hours * 3600) + (minutes * 60) + seconds) * 1000 + milliseconds)
    }

    return nil
}

private func paddedMilliseconds(_ raw: String) -> Int {
    let prefix = String(raw.prefix(3))
    let padded = prefix.padding(toLength: 3, withPad: "0", startingAt: 0)
    return Int(padded) ?? 0
}

// MARK: - TTML Exporter
enum TTMLExporter {
    static func export(
        lines: [LyricLine],
        songwriters: [String] = [],
        title: String? = nil,
        artist: String? = nil,
        source: String? = nil,
        attribution: SpicyUploadAttribution? = nil
    ) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        xml += "<tt xmlns=\"http://www.w3.org/ns/ttml\" xmlns:ttm=\"http://www.w3.org/ns/ttml#metadata\">\n"
        xml += "  <head>\n"
        xml += "    <metadata>\n"
        if let title = title, !title.isEmpty {
            xml += "      <ttm:title>\(xmlEscape(title))</ttm:title>\n"
        }
        if let artist = artist, !artist.isEmpty {
            xml += "      <ttm:agent type=\"person\">\(xmlEscape(artist))</ttm:agent>\n"
        }
        if let source = source, !source.isEmpty {
            xml += "      <source>\(xmlEscape(source))</source>\n"
        }
        if let attr = attribution {
            if let uploader = attr.uploader, (uploader.username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || uploader.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) {
                xml += "      <uploader id=\"\(xmlEscape(uploader.id ?? ""))\" username=\"\(xmlEscape(uploader.username ?? ""))\" avatar=\"\(xmlEscape(uploader.avatar ?? ""))\" url=\"\(xmlEscape(uploader.url ?? ""))\" />\n"
            }
            if let maker = attr.maker, (maker.username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || maker.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) {
                xml += "      <maker id=\"\(xmlEscape(maker.id ?? ""))\" username=\"\(xmlEscape(maker.username ?? ""))\" avatar=\"\(xmlEscape(maker.avatar ?? ""))\" url=\"\(xmlEscape(maker.url ?? ""))\" />\n"
            }
        }
        for songwriter in songwriters {
            xml += "      <songwriter>\(xmlEscape(songwriter))</songwriter>\n"
        }
        xml += "    </metadata>\n"
        xml += "  </head>\n"
        xml += "  <body>\n"
        xml += "    <div>\n"

        let regularLines = lines.filter { !$0.isSongwriter && !$0.isInterlude }
        for line in regularLines {
            let start = formatTime(ms: line.startMs)
            let end = formatTime(ms: line.endMs)
            let agentAttr = line.agent.map { " agent=\"\(xmlEscape($0))\"" } ?? ""
            let backgroundAttr = line.isBackground ? " ttm:role=\"background\"" : ""

            let isStaticLine = line.isStatic || (line.startMs == 0 && (line.lineEndMs == nil || line.lineEndMs == 0))
            if isStaticLine {
                xml += "      <p\(agentAttr)\(backgroundAttr)>\n"
            } else {
                xml += "      <p begin=\"\(start)\" end=\"\(end)\"\(agentAttr)\(backgroundAttr)>\n"
            }

            if line.isWordSynced && !line.words.isEmpty {
                for (wIndex, word) in line.words.enumerated() {
                    let wStart = formatTime(ms: word.startMs)
                    let wEnd = formatTime(ms: word.endMs)
                    let isLast = wIndex == line.words.count - 1
                    let trailing = (!isLast && !word.isPartOfWord && !word.text.hasSuffix("-")) ? " " : ""
                    xml += "        <span begin=\"\(wStart)\" end=\"\(wEnd)\">\(xmlEscape(word.text))\(trailing)</span>\n"
                }
            } else {
                xml += "        <span>\(xmlEscape(line.displayText))</span>\n"
            }

            if let trans = line.translation, !trans.isEmpty {
                xml += "        <span ttm:role=\"translation\">\(xmlEscape(trans))</span>\n"
            }
            if let rom = line.romanization, !rom.isEmpty {
                xml += "        <span ttm:role=\"romanization\">\(xmlEscape(rom))</span>\n"
            }

            xml += "      </p>\n"
        }

        xml += "    </div>\n"
        xml += "  </body>\n"
        xml += "</tt>\n"
        return xml
    }

    static func export(
        parsed: ParsedLyrics,
        title: String? = nil,
        artist: String? = nil
    ) -> String {
        return export(
            lines: parsed.lines,
            songwriters: parsed.songwriters,
            title: title,
            artist: artist,
            source: parsed.source,
            attribution: parsed.attribution
        )
    }

    private static func formatTime(ms: Int) -> String {
        let totalSeconds = max(0, ms) / 1000
        let milliseconds = max(0, ms) % 1000
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    private static func xmlEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

