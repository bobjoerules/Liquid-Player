import Foundation

// MARK: - Spicy Lyrics API Decodable Models

struct SpicyLyricsEnvelope: Decodable {
    let Body: SpicyLyricsBody?
    let Status: Int?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case Body
        case Status
        case type = "Type"
    }
}

struct SpicyLyricsBody: Decodable {
    let id: String?
    let source: String?
    let SongWriters: [String]?
    let type: String? // "Syllable", "Line", "Static"
    let StartTime: Double?
    let EndTime: Double?
    let Content: [SpicyContentLine]?
    let UploadAttribution: SpicyUploadAttributionDTO?
    let plainLyrics: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case SongWriters
        case songWritersLower = "songwriters"
        case type = "Type"
        case typeLower = "type"
        case StartTime
        case EndTime
        case Content
        case contentLower = "content"
        case Lines
        case linesLower = "lines"
        case UploadAttribution
        case plainLyrics
        case text
        case lyrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try? container.decodeIfPresent(String.self, forKey: .id)
        self.source = try? container.decodeIfPresent(String.self, forKey: .source)
        self.SongWriters = (try? container.decodeIfPresent([String].self, forKey: .SongWriters)) ??
                          (try? container.decodeIfPresent([String].self, forKey: .songWritersLower))
        self.type = (try? container.decodeIfPresent(String.self, forKey: .type)) ??
                    (try? container.decodeIfPresent(String.self, forKey: .typeLower))
        self.StartTime = try? container.decodeIfPresent(Double.self, forKey: .StartTime)
        self.EndTime = try? container.decodeIfPresent(Double.self, forKey: .EndTime)
        self.UploadAttribution = try? container.decodeIfPresent(SpicyUploadAttributionDTO.self, forKey: .UploadAttribution)
        self.plainLyrics = (try? container.decodeIfPresent(String.self, forKey: .plainLyrics)) ??
                           (try? container.decodeIfPresent(String.self, forKey: .lyrics))
        self.text = try? container.decodeIfPresent(String.self, forKey: .text)

        if let lines = try? container.decodeIfPresent([SpicyContentLine].self, forKey: .Content) {
            self.Content = lines
        } else if let lines = try? container.decodeIfPresent([SpicyContentLine].self, forKey: .Lines) {
            self.Content = lines
        } else if let lines = try? container.decodeIfPresent([SpicyContentLine].self, forKey: .linesLower) {
            self.Content = lines
        } else if let lines = try? container.decodeIfPresent([SpicyContentLine].self, forKey: .contentLower) {
            self.Content = lines
        } else if let stringArray = (try? container.decodeIfPresent([String].self, forKey: .Content)) ??
                                    (try? container.decodeIfPresent([String].self, forKey: .Lines)) ??
                                    (try? container.decodeIfPresent([String].self, forKey: .linesLower)) ??
                                    (try? container.decodeIfPresent([String].self, forKey: .contentLower)) {
            self.Content = stringArray.map { SpicyContentLine(text: $0) }
        } else if let singleString = (try? container.decodeIfPresent(String.self, forKey: .Content)) ??
                                     (try? container.decodeIfPresent(String.self, forKey: .Lines)) ??
                                     (try? container.decodeIfPresent(String.self, forKey: .linesLower)) ??
                                     (try? container.decodeIfPresent(String.self, forKey: .contentLower)) {
            self.Content = singleString.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { SpicyContentLine(text: $0) }
        } else if let fallbackText = self.plainLyrics ?? self.text {
            self.Content = fallbackText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { SpicyContentLine(text: $0) }
        } else {
            self.Content = nil
        }
    }
}

struct SpicyUploadAttributionDTO: Codable {
    let Uploader: SpicyAttributionUserDTO?
    let Maker: SpicyAttributionUserDTO?
}

struct SpicyAttributionUserDTO: Codable {
    let id: String?
    let username: String?
    let avatar: String?
    let hasProfileBanner: Bool?
    let url: String?
}

struct SpicyContentLine: Decodable {
    let type: String?
    let OppositeAligned: Bool?
    let agent: String?
    let Lead: SpicyVocalGroup?
    let Background: [SpicyVocalGroup]?
    
    // For Line-level lyrics
    let StartTime: Double?
    let EndTime: Double?
    let Text: String?
    let TransliteratedText: String?
    let TranslatedText: String?

    init(
        type: String? = "Line",
        OppositeAligned: Bool? = false,
        agent: String? = nil,
        Lead: SpicyVocalGroup? = nil,
        Background: [SpicyVocalGroup]? = nil,
        StartTime: Double? = nil,
        EndTime: Double? = nil,
        Text: String? = nil,
        TransliteratedText: String? = nil,
        TranslatedText: String? = nil
    ) {
        self.type = type
        self.OppositeAligned = OppositeAligned
        self.agent = agent
        self.Lead = Lead
        self.Background = Background
        self.StartTime = StartTime
        self.EndTime = EndTime
        self.Text = Text
        self.TransliteratedText = TransliteratedText
        self.TranslatedText = TranslatedText
    }

    init(text: String) {
        self.init(
            type: "Line",
            OppositeAligned: false,
            agent: nil,
            Lead: nil,
            Background: nil,
            StartTime: nil,
            EndTime: nil,
            Text: text,
            TransliteratedText: nil,
            TranslatedText: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case OppositeAligned
        case agent
        case Lead
        case Background
        case StartTime
        case EndTime
        case Text
        case textLower = "text"
        case TransliteratedText
        case transliteratedTextLower = "transliteratedText"
        case TranslatedText
        case translatedTextLower = "translatedText"
    }

    init(from decoder: Decoder) throws {
        if let singleString = try? decoder.singleValueContainer().decode(String.self) {
            self.init(text: singleString)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try? container.decodeIfPresent(String.self, forKey: .type)
        let OppositeAligned = try? container.decodeIfPresent(Bool.self, forKey: .OppositeAligned)
        let agent = try? container.decodeIfPresent(String.self, forKey: .agent)
        let Lead = try? container.decodeIfPresent(SpicyVocalGroup.self, forKey: .Lead)
        let Background = try? container.decodeIfPresent([SpicyVocalGroup].self, forKey: .Background)
        let StartTime = try? container.decodeIfPresent(Double.self, forKey: .StartTime)
        let EndTime = try? container.decodeIfPresent(Double.self, forKey: .EndTime)
        let Text = (try? container.decodeIfPresent(String.self, forKey: .Text)) ??
                    (try? container.decodeIfPresent(String.self, forKey: .textLower))
        let TransliteratedText = (try? container.decodeIfPresent(String.self, forKey: .TransliteratedText)) ??
                                 (try? container.decodeIfPresent(String.self, forKey: .transliteratedTextLower))
        let TranslatedText = (try? container.decodeIfPresent(String.self, forKey: .TranslatedText)) ??
                             (try? container.decodeIfPresent(String.self, forKey: .translatedTextLower))

        self.init(
            type: type,
            OppositeAligned: OppositeAligned,
            agent: agent,
            Lead: Lead,
            Background: Background,
            StartTime: StartTime,
            EndTime: EndTime,
            Text: Text,
            TransliteratedText: TransliteratedText,
            TranslatedText: TranslatedText
        )
    }
}

struct SpicyVocalGroup: Codable {
    let StartTime: Double?
    let EndTime: Double?
    let OppositeAligned: Bool?
    let TransliteratedText: String?
    let TranslatedText: String?
    let Syllables: [SpicySyllable]?
}

struct SpicySyllable: Codable {
    let Text: String
    let StartTime: Double
    let EndTime: Double
    let IsPartOfWord: Bool?
    let TransliteratedText: String?
}

// MARK: - Service Implementation

actor SpicyLyricsService {
    static let shared = SpicyLyricsService()
    
    private var cache: [String: ParsedLyrics] = [:]
    private var inFlightTasks: [String: Task<ParsedLyrics, Error>] = [:]

    func getCachedLyrics(for trackId: String) -> ParsedLyrics? {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        return cache[cleanId]
    }

    func isLyricsCached(for trackId: String) -> Bool {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        return cache[cleanId] != nil
    }

    func prefetchLyrics(for trackId: String) async {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }
        if cache[cleanId] != nil { return }
        _ = try? await fetchLyrics(for: cleanId)
    }

    func prefetchLyrics(for trackIds: [String]) async {
        for id in trackIds.prefix(5) {
            await prefetchLyrics(for: id)
        }
    }

    func fetchLyrics(for trackId: String) async throws -> ParsedLyrics {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else {
            throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid track ID."])
        }

        if let cached = cache[cleanId] {
            return cached
        }

        // Deduplicate in-flight requests for the same track
        if let existingTask = inFlightTasks[cleanId] {
            return try await existingTask.value
        }

        let task = Task<ParsedLyrics, Error> {
            guard let url = URL(string: "https://api.spicylyrics.org/v1/lyrics/\(cleanId)") else {
                throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL."])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(APIConfig.spicyLyricsApiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: 404, userInfo: [NSLocalizedDescriptionKey: "Lyrics not found for this track."])
                }
                if httpResponse.statusCode == 503 {
                    throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: 503, userInfo: [NSLocalizedDescriptionKey: "Upstream lyrics service temporarily unavailable."])
                }
                throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
            }

            let envelope = try JSONDecoder().decode(SpicyLyricsEnvelope.self, from: data)
            guard let body = envelope.Body else {
                throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty lyrics response"])
            }

            let parsed = self.parseLyricsBody(body)
            return parsed
        }

        inFlightTasks[cleanId] = task

        do {
            let result = try await task.value
            inFlightTasks.removeValue(forKey: cleanId)
            cache[cleanId] = result
            return result
        } catch {
            inFlightTasks.removeValue(forKey: cleanId)
            throw error
        }
    }

    private func parseLyricsBody(_ body: SpicyLyricsBody) -> ParsedLyrics {
        let songwriters = body.SongWriters ?? []
        var vocalUnits: [VocalUnit] = []

        let isStatic = (body.type?.caseInsensitiveCompare("Static") == .orderedSame) ||
                       (body.type == nil && (body.Content?.allSatisfy { ($0.StartTime == nil || $0.StartTime == 0) && ($0.EndTime == nil || $0.EndTime == 0) && $0.Lead == nil } ?? false))
        let isSongLineSynced = isStatic || (body.type?.caseInsensitiveCompare("Line") == .orderedSame)

        if let contentLines = body.Content {
            for contentLine in contentLines {
                var unitLeadLines: [LyricLine] = []
                var unitBgLines: [LyricLine] = []

                let isContentLineSynced = isSongLineSynced ||
                                          (contentLine.type?.caseInsensitiveCompare("Line") == .orderedSame) ||
                                          (contentLine.Lead == nil) ||
                                          (contentLine.Lead?.Syllables == nil) ||
                                          (contentLine.Lead?.Syllables?.isEmpty == true)

                if isContentLineSynced {
                    // Line-level: show line directly without fake word timings
                    let rawContentText = contentLine.Text ?? contentLine.Lead?.Syllables?.map(\.Text).joined(separator: " ") ?? ""
                    let text = rawContentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let startMs = isStatic ? 0 : max(0, Int((contentLine.StartTime ?? contentLine.Lead?.StartTime ?? 0.0) * 1000.0))
                    let endMs = isStatic ? 0 : max(startMs + 500, Int((contentLine.EndTime ?? contentLine.Lead?.EndTime ?? (Double(startMs) / 1000.0 + 3.0)) * 1000.0))
                    let opposite = contentLine.OppositeAligned ?? contentLine.Lead?.OppositeAligned ?? (contentLine.agent != nil && contentLine.agent != "1" && contentLine.agent != "v1")

                    unitLeadLines.append(
                        LyricLine(
                            words: [],
                            startMs: startMs,
                            lineEndMs: endMs,
                            isWordSynced: false,
                            agent: contentLine.agent ?? (opposite ? "v2" : "v1"),
                            isBackground: false,
                            oppositeAligned: opposite,
                            isSongwriter: false,
                            isInterlude: false,
                            interludeEndMs: -1,
                            translation: contentLine.TranslatedText ?? contentLine.Lead?.TranslatedText,
                            romanization: contentLine.TransliteratedText ?? contentLine.Lead?.TransliteratedText,
                            rawText: text,
                            isStatic: isStatic
                        )
                    )
                } else if let lead = contentLine.Lead {
                    let opposite = contentLine.OppositeAligned ?? contentLine.Lead?.OppositeAligned ?? (contentLine.agent != nil && contentLine.agent != "1" && contentLine.agent != "v1")
                    let startMs = max(0, Int((lead.StartTime ?? 0.0) * 1000.0))
                    let endMs = max(startMs + 500, Int((lead.EndTime ?? Double(startMs) / 1000.0 + 3.0) * 1000.0))
                    let rawSyllables = lead.Syllables ?? []

                    var candidateWords: [LyricWord] = []
                    for (sylIndex, syl) in rawSyllables.enumerated() {
                        let sylStart = max(0, Int(syl.StartTime * 1000.0))
                        let sylEnd = max(sylStart + 1, Int(syl.EndTime * 1000.0))
                        let rawToken = syl.Text
                        let trimmedToken = rawToken.trimmingCharacters(in: .whitespaces)
                        guard !trimmedToken.isEmpty else { continue }

                        let hasTrailingSpace = rawToken.hasSuffix(" ") || rawToken.hasSuffix("\t")
                        let endsWithHyphen = trimmedToken.hasSuffix("-") || trimmedToken.hasSuffix("–") || trimmedToken.hasSuffix("—")
                        let isLastSyllable = sylIndex == rawSyllables.count - 1

                        var nextHasLeadingSpace = false
                        if sylIndex + 1 < rawSyllables.count {
                            let nextRaw = rawSyllables[sylIndex + 1].Text
                            nextHasLeadingSpace = nextRaw.hasPrefix(" ") || nextRaw.hasPrefix("\t")
                        }

                        let isPart: Bool
                        if isLastSyllable {
                            isPart = false
                        } else if hasTrailingSpace || nextHasLeadingSpace {
                            isPart = false
                        } else if endsWithHyphen {
                            isPart = true
                        } else if let explicitPart = syl.IsPartOfWord {
                            isPart = explicitPart
                        } else {
                            isPart = true
                        }
                        let duration = max(sylEnd - sylStart, 1)

                        // Only genuine single syllables without spaces held over 1.2s should animate letter groups
                        let isLetterGroup = duration >= 1200 && trimmedToken.count > 1 && !trimmedToken.contains(" ")
                        let letters: [LyricLetter]
                        if isLetterGroup {
                            let count = max(trimmedToken.count, 1)
                            let letterDur = Double(duration) / Double(count)
                            letters = trimmedToken.enumerated().map { off, char in
                                LyricLetter(
                                    char: String(char),
                                    startMs: sylStart + Int(Double(off) * letterDur),
                                    endMs: off == count - 1 ? sylEnd : sylStart + Int(Double(off + 1) * letterDur)
                                )
                            }
                        } else {
                            letters = []
                        }

                        candidateWords.append(
                            LyricWord(
                                text: trimmedToken,
                                startMs: sylStart,
                                endMs: sylEnd,
                                isPartOfWord: isPart,
                                isLetterGroup: isLetterGroup,
                                letters: letters
                            )
                        )
                    }

                    if let lastIdx = candidateWords.indices.last, candidateWords[lastIdx].isPartOfWord {
                        let last = candidateWords[lastIdx]
                        candidateWords[lastIdx] = LyricWord(
                            text: last.text,
                            startMs: last.startMs,
                            endMs: last.endMs,
                            isPartOfWord: false,
                            isLetterGroup: last.isLetterGroup,
                            letters: last.letters
                        )
                    }

                    let lineText = contentLine.Text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? candidateWords.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !candidateWords.isEmpty || !lineText.isEmpty else { continue }

                    // A line is word-synced if the song is word-synced, words are present,
                    // and multi-token lines have distinct start times (not artificially divided)
                    var effectiveWords = candidateWords
                    let explicitLeadStart = lead.StartTime.map { max(0, Int($0 * 1000.0)) }
                    if effectiveWords.isEmpty && !isSongLineSynced {
                        let tokens = lineText.split(whereSeparator: \.isWhitespace).map(String.init)
                        if tokens.count == 1, let singleWord = tokens.first, !singleWord.isEmpty {
                            let wStart = explicitLeadStart ?? max(0, Int((contentLine.StartTime ?? 0.0) * 1000.0))
                            let wEnd = max(wStart + 500, endMs)
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
                            effectiveWords = [
                                LyricWord(
                                    text: singleWord,
                                    startMs: wStart,
                                    endMs: wEnd,
                                    isPartOfWord: false,
                                    isLetterGroup: isLetterGroup,
                                    letters: letters
                                )
                            ]
                        }
                    }

                    let distinctStarts = effectiveWords.count > 1 ? Set(effectiveWords.map(\.startMs)).count > 1 : true
                    let durations = effectiveWords.map { $0.endMs - $0.startMs }
                    let isIdenticalDurations = effectiveWords.count >= 3 && Set(durations).count == 1
                    let isTrulyWordSynced = !isSongLineSynced && !effectiveWords.isEmpty && distinctStarts && !isIdenticalDurations

                    let actualStart = effectiveWords.first?.startMs ?? explicitLeadStart ?? max(0, Int((contentLine.StartTime ?? 0.0) * 1000.0))
                    let actualEnd = effectiveWords.last?.endMs ?? max(actualStart + 500, endMs)

                    unitLeadLines.append(
                        LyricLine(
                            words: isTrulyWordSynced ? effectiveWords : [],
                            startMs: actualStart,
                            lineEndMs: actualEnd,
                            isWordSynced: isTrulyWordSynced,
                            agent: contentLine.agent ?? (opposite ? "v2" : "v1"),
                            isBackground: false,
                            oppositeAligned: opposite,
                            isSongwriter: false,
                            isInterlude: false,
                            interludeEndMs: -1,
                            translation: lead.TranslatedText ?? contentLine.TranslatedText,
                            romanization: lead.TransliteratedText ?? contentLine.TransliteratedText,
                            rawText: lineText
                        )
                    )
                }

                // Background vocals if present in this contentLine
                if let bgList = contentLine.Background {
                    for bg in bgList {
                        let baseLeadStart = unitLeadLines.first?.startMs ?? 0
                        let bgStart = Int((bg.StartTime ?? Double(baseLeadStart) / 1000.0) * 1000.0)
                        var bgWords: [LyricWord] = []
                        if let bgSyllables = bg.Syllables {
                            for (sylIndex, syl) in bgSyllables.enumerated() {
                                let sStart = Int(syl.StartTime * 1000.0)
                                let sEnd = Int(syl.EndTime * 1000.0)
                                let rawToken = syl.Text
                                let trimmedToken = rawToken.trimmingCharacters(in: .whitespaces)
                                guard !trimmedToken.isEmpty else { continue }
                                let hasLeadingSpace = rawToken.hasPrefix(" ") || rawToken.hasPrefix("\t")
                                let hasTrailingSpace = rawToken.hasSuffix(" ") || rawToken.hasSuffix("\t")
                                let endsWithHyphen = trimmedToken.hasSuffix("-") || trimmedToken.hasSuffix("–") || trimmedToken.hasSuffix("—")
                                let isLastSyllable = sylIndex == bgSyllables.count - 1

                                var nextHasLeadingSpace = false
                                if sylIndex + 1 < bgSyllables.count {
                                    let nextRaw = bgSyllables[sylIndex + 1].Text
                                    nextHasLeadingSpace = nextRaw.hasPrefix(" ") || nextRaw.hasPrefix("\t")
                                }

                                let isPart: Bool
                                if isLastSyllable {
                                    isPart = false
                                } else if hasTrailingSpace || nextHasLeadingSpace {
                                    isPart = false
                                } else if endsWithHyphen {
                                    isPart = true
                                } else if let explicitPart = syl.IsPartOfWord {
                                    isPart = explicitPart
                                } else {
                                    isPart = true
                                }
                                bgWords.append(
                                    LyricWord(
                                        text: trimmedToken,
                                        startMs: sStart,
                                        endMs: sEnd,
                                        isPartOfWord: isPart,
                                        isLetterGroup: false,
                                        letters: []
                                    )
                                )
                            }
                        }

                        if let lastIdx = bgWords.indices.last, bgWords[lastIdx].isPartOfWord {
                            let last = bgWords[lastIdx]
                            bgWords[lastIdx] = LyricWord(
                                text: last.text,
                                startMs: last.startMs,
                                endMs: last.endMs,
                                isPartOfWord: false,
                                isLetterGroup: last.isLetterGroup,
                                letters: last.letters
                            )
                        }

                        let rawBgText = bg.TranslatedText ?? bg.TransliteratedText ?? ""
                        let bgText = !bgWords.isEmpty ? bgWords.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines) : rawBgText.trimmingCharacters(in: .whitespacesAndNewlines)

                        var effectiveBgWords = bgWords
                        if effectiveBgWords.isEmpty && !isSongLineSynced && !bgText.isEmpty {
                            let bgTokens = bgText.split(whereSeparator: \.isWhitespace).map(String.init)
                            if bgTokens.count == 1, let singleBg = bgTokens.first, !singleBg.isEmpty {
                                let bStart = bgStart
                                let bEnd = bg.EndTime.map { Int($0 * 1000.0) } ?? (bStart + 1500)
                                effectiveBgWords = [
                                    LyricWord(
                                        text: singleBg,
                                        startMs: bStart,
                                        endMs: bEnd,
                                        isPartOfWord: false,
                                        isLetterGroup: false,
                                        letters: []
                                    )
                                ]
                            }
                        }

                        if !effectiveBgWords.isEmpty || !bgText.isEmpty {
                            let actualStart = effectiveBgWords.first?.startMs ?? bgStart
                            let actualEnd = bg.EndTime.map { Int($0 * 1000.0) } ?? effectiveBgWords.last?.endMs ?? actualStart
                            let bgDurations = effectiveBgWords.map { $0.endMs - $0.startMs }
                            let bgIdentical = effectiveBgWords.count >= 3 && Set(bgDurations).count == 1
                            let bgDistinctStarts = effectiveBgWords.count > 1 ? Set(effectiveBgWords.map(\.startMs)).count > 1 : true
                            let hasWordTimings = !isSongLineSynced && !effectiveBgWords.isEmpty && bgDistinctStarts && !bgIdentical
                            let opposite = contentLine.OppositeAligned ?? contentLine.Lead?.OppositeAligned ?? (contentLine.agent != nil && contentLine.agent != "1" && contentLine.agent != "v1")
                            unitBgLines.append(
                                LyricLine(
                                    words: hasWordTimings ? effectiveBgWords : [],
                                    startMs: actualStart,
                                    lineEndMs: actualEnd,
                                    isWordSynced: hasWordTimings,
                                    agent: contentLine.agent ?? (opposite ? "v2" : "v1"),
                                    isBackground: true,
                                    oppositeAligned: opposite,
                                    isSongwriter: false,
                                    isInterlude: false,
                                    interludeEndMs: -1,
                                    translation: bg.TranslatedText,
                                    romanization: bg.TransliteratedText,
                                    rawText: hasWordTimings ? nil : bgText
                                )
                            )
                        }
                    }
                }

                if !unitLeadLines.isEmpty || !unitBgLines.isEmpty {
                    vocalUnits.append(VocalUnit(leadLines: unitLeadLines, backgroundLines: unitBgLines))
                }
            }
        }

        // Whole-song verification: If fewer than 2 lines have genuine word timings,
        // then the entire song is line-synced! Ensure all lines are clean whole lines.
        let allVocalLines = vocalUnits.flatMap(\.allLines)
        let wordSyncedLineCount = allVocalLines.filter { $0.isWordSynced && !$0.words.isEmpty && !$0.isInterlude && !$0.isSongwriter }.count
        if wordSyncedLineCount < 2 {
            let makeLineSynced: (LyricLine) -> LyricLine = { line in
                if line.isInterlude || line.isSongwriter { return line }
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

            vocalUnits = vocalUnits.map { unit in
                VocalUnit(
                    leadLines: unit.leadLines.map(makeLineSynced),
                    backgroundLines: unit.backgroundLines.map(makeLineSynced)
                )
            }
        }

        if !isStatic {
            // Sort vocal units by their startMs for timed songs
            vocalUnits.sort { $0.startMs < $1.startMs }
        }

        var sortedAll: [LyricLine] = []

        // 1. Intro interlude if first vocal unit starts after >= 3000ms (only for synced songs)
        if !isStatic, let first = vocalUnits.first, first.startMs >= 3000 {
            let dotWords = createInterludeDotWords(startMs: 0, endMs: first.startMs)
            let lead = first.leadLines.first
            sortedAll.append(
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
        for index in 0..<vocalUnits.count {
            let unit = vocalUnits[index]

            // Always append the vocal unit's lines together (lead vocal first, followed immediately by its background vocals)
            sortedAll.append(contentsOf: unit.allLines)

            if !isStatic, index < vocalUnits.count - 1 {
                let nextUnit = vocalUnits[index + 1]
                let gapStart = unit.endMs  // All vocals (lead AND background) have ended!
                let gapEnd = nextUnit.startMs // Next vocal unit begins!

                if gapEnd - gapStart >= 3000 {
                    let dotWords = createInterludeDotWords(startMs: gapStart, endMs: gapEnd)
                    let nextLead = nextUnit.leadLines.first
                    sortedAll.append(
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

        var attribution: SpicyUploadAttribution? = nil
        if let uploadAttr = body.UploadAttribution {
            let uploader = uploadAttr.Uploader.map {
                SpicyAttributionUser(id: $0.id, username: $0.username, avatar: $0.avatar, url: $0.url)
            }
            let maker = uploadAttr.Maker.map {
                SpicyAttributionUser(id: $0.id, username: $0.username, avatar: $0.avatar, url: $0.url)
            }
            attribution = SpicyUploadAttribution(uploader: uploader, maker: maker)
        }

        return ParsedLyrics(
            lines: sortedAll,
            songwriters: songwriters,
            source: body.source,
            attribution: attribution,
            isStatic: isStatic
        )
    }
}
