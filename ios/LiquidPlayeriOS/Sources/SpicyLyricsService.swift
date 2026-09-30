import Foundation

// MARK: - Spicy Lyrics API Decodable Models

struct SpicyLyricsEnvelope: Codable {
    let Body: SpicyLyricsBody?
    let Status: Int
    let type: String?

    enum CodingKeys: String, CodingKey {
        case Body
        case Status
        case type = "Type"
    }
}

struct SpicyLyricsBody: Codable {
    let id: String?
    let source: String?
    let SongWriters: [String]?
    let type: String? // "Syllable", "Line", "Static"
    let StartTime: Double?
    let EndTime: Double?
    let Content: [SpicyContentLine]?
    let UploadAttribution: SpicyUploadAttributionDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case SongWriters
        case type = "Type"
        case StartTime
        case EndTime
        case Content
        case UploadAttribution
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

struct SpicyContentLine: Codable {
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

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case OppositeAligned
        case agent
        case Lead
        case Background
        case StartTime
        case EndTime
        case Text
        case TransliteratedText
        case TranslatedText
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

        let isSongLineSynced = (body.type?.caseInsensitiveCompare("Line") == .orderedSame) ||
                               (body.type?.caseInsensitiveCompare("Static") == .orderedSame)

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
                    let startMs = max(0, Int((contentLine.StartTime ?? contentLine.Lead?.StartTime ?? 0.0) * 1000.0))
                    let endMs = max(startMs + 500, Int((contentLine.EndTime ?? contentLine.Lead?.EndTime ?? (Double(startMs) / 1000.0 + 3.0)) * 1000.0))
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
                            rawText: text
                        )
                    )
                } else if let lead = contentLine.Lead {
                    let opposite = contentLine.OppositeAligned ?? contentLine.Lead?.OppositeAligned ?? (contentLine.agent != nil && contentLine.agent != "1" && contentLine.agent != "v1")
                    let startMs = max(0, Int((lead.StartTime ?? 0.0) * 1000.0))
                    let endMs = max(startMs + 500, Int((lead.EndTime ?? Double(startMs) / 1000.0 + 3.0) * 1000.0))
                    let rawSyllables = lead.Syllables ?? []

                    var candidateWords: [LyricWord] = []
                    for syl in rawSyllables {
                        let sylStart = max(0, Int(syl.StartTime * 1000.0))
                        let sylEnd = max(sylStart + 1, Int(syl.EndTime * 1000.0))
                        let rawToken = syl.Text
                        let trimmedToken = rawToken.trimmingCharacters(in: .whitespaces)
                        guard !trimmedToken.isEmpty else { continue }

                        let hasLeadingSpace = rawToken.hasPrefix(" ")
                        let isPart = (syl.IsPartOfWord ?? false) && !hasLeadingSpace
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
                            for syl in bgSyllables {
                                let sStart = Int(syl.StartTime * 1000.0)
                                let sEnd = Int(syl.EndTime * 1000.0)
                                let rawToken = syl.Text
                                let trimmedToken = rawToken.trimmingCharacters(in: .whitespaces)
                                guard !trimmedToken.isEmpty else { continue }
                                let hasLeadingSpace = rawToken.hasPrefix(" ")
                                let isPart = (syl.IsPartOfWord ?? false) && !hasLeadingSpace
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
                    rawText: line.displayText
                )
            }

            vocalUnits = vocalUnits.map { unit in
                VocalUnit(
                    leadLines: unit.leadLines.map(makeLineSynced),
                    backgroundLines: unit.backgroundLines.map(makeLineSynced)
                )
            }
        }

        // Sort vocal units by their startMs
        vocalUnits.sort { $0.startMs < $1.startMs }

        var sortedAll: [LyricLine] = []

        // 1. Intro interlude if first vocal unit starts after >= 3000ms
        if let first = vocalUnits.first, first.startMs >= 3000 {
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

            if index < vocalUnits.count - 1 {
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
            attribution: attribution
        )
    }
}
