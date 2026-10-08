import Foundation

actor LRCLIBService {
    static let shared = LRCLIBService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    private struct LRCLIBResponse: Codable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    func fetchLyrics(
        trackTitle: String,
        artistName: String,
        albumName: String? = nil,
        durationSeconds: Int? = nil
    ) async -> ParsedLyrics? {
        let cleanTitle = trackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artistName.splitArtistNames.first ?? artistName
        guard !cleanTitle.isEmpty, !cleanArtist.isEmpty else { return nil }

        // 1. Try exact match query
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: cleanTitle),
            URLQueryItem(name: "artist_name", value: cleanArtist)
        ]
        if let album = albumName?.trimmingCharacters(in: .whitespacesAndNewlines), !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration = durationSeconds, duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: "\(duration)"))
        }

        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = queryItems

        if let url = components?.url {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            if let (data, response) = try? await session.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let lrcResp = try? JSONDecoder().decode(LRCLIBResponse.self, from: data) {
                // If the exact match is verified instrumental, this track has no lyrics.
                // Do not fall back to fuzzy search which might pull remixes or covers!
                if lrcResp.instrumental == true {
                    return nil
                }
                if let parsed = parseResponse(lrcResp) {
                    return parsed
                }
            }
        }

        // 2. Fallback to search query if exact get was not found
        var searchComponents = URLComponents(string: "https://lrclib.net/api/search")
        searchComponents?.queryItems = [
            URLQueryItem(name: "track_name", value: cleanTitle),
            URLQueryItem(name: "artist_name", value: cleanArtist)
        ]

        if let searchUrl = searchComponents?.url {
            var searchRequest = URLRequest(url: searchUrl)
            searchRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            searchRequest.setValue("application/json", forHTTPHeaderField: "Accept")

            if let (searchData, searchResponse) = try? await session.data(for: searchRequest),
               let httpSearchResponse = searchResponse as? HTTPURLResponse,
               httpSearchResponse.statusCode == 200,
               let results = try? JSONDecoder().decode([LRCLIBResponse].self, from: searchData) {
                for result in results {
                    if result.instrumental == true {
                        continue
                    }
                    guard let candTitle = result.trackName, !candTitle.isEmpty else { continue }
                    guard TrackMatchUtils.titlesMatch(requested: cleanTitle, candidate: candTitle) else { continue }

                    if let candArtist = result.artistName, !candArtist.isEmpty {
                        guard TrackMatchUtils.artistsMatch(requested: cleanArtist, candidate: candArtist) else { continue }
                    }

                    let candDuration = result.duration.map { Int($0) }
                    guard TrackMatchUtils.durationsMatch(expected: durationSeconds, candidate: candDuration) else { continue }

                    if let parsed = parseResponse(result) {
                        return parsed
                    }
                }
            }
        }

        return nil
    }

    private func parseResponse(_ resp: LRCLIBResponse) -> ParsedLyrics? {
        if resp.instrumental == true {
            return nil
        }

        // Try synchronized LRC lyrics first
        if let synced = resp.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty {
                return ParsedLyrics(
                    lines: lines,
                    songwriters: [],
                    source: "LRCLIB (Line Synced)",
                    attribution: nil,
                    isStatic: false
                )
            }
        }

        // Fallback to plain (unsynced) lyrics
        if let plain = resp.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = parsePlain(plain)
            if !lines.isEmpty {
                return ParsedLyrics(
                    lines: lines,
                    songwriters: [],
                    source: "LRCLIB",
                    attribution: nil,
                    isStatic: true
                )
            }
        }

        return nil
    }

    private func parseLRC(_ syncedLyrics: String) -> [LyricLine] {
        let rawLines = syncedLyrics.components(separatedBy: .newlines)
        var parsedLines: [(startMs: Int, text: String)] = []

        let pattern = #"^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let nsString = trimmed as NSString
            let matches = regex.matches(in: trimmed, options: [], range: NSRange(location: 0, length: nsString.length))
            guard let match = matches.first, match.numberOfRanges >= 3 else { continue }

            let minStr = nsString.substring(with: match.range(at: 1))
            let secStr = nsString.substring(with: match.range(at: 2))
            let msStr: String = match.range(at: 3).location != NSNotFound ? nsString.substring(with: match.range(at: 3)) : "0"
            let textStr: String = match.numberOfRanges >= 5 && match.range(at: 4).location != NSNotFound ? nsString.substring(with: match.range(at: 4)) : ""

            guard let mins = Int(minStr), let secs = Int(secStr) else { continue }
            let msFrac: Int = {
                if msStr.count == 1 { return (Int(msStr) ?? 0) * 100 }
                if msStr.count == 2 { return (Int(msStr) ?? 0) * 10 }
                return Int(msStr) ?? 0
            }()
            let startMs = mins * 60_000 + secs * 1000 + msFrac
            let text = textStr.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            parsedLines.append((startMs: startMs, text: text))
        }

        parsedLines.sort { $0.startMs < $1.startMs }

        var result: [LyricLine] = []

        if let first = parsedLines.first, first.startMs >= 3000 {
            let dotWords = createInterludeDotWords(startMs: 0, endMs: first.startMs)
            result.append(
                LyricLine(
                    words: dotWords,
                    startMs: 0,
                    lineEndMs: first.startMs,
                    isWordSynced: false,
                    agent: "v1",
                    isBackground: false,
                    oppositeAligned: false,
                    isSongwriter: false,
                    isInterlude: true,
                    interludeEndMs: first.startMs,
                    rawText: "• • •",
                    isStatic: false
                )
            )
        }

        for i in 0..<parsedLines.count {
            let curr = parsedLines[i]
            let nextStart = (i + 1 < parsedLines.count) ? parsedLines[i + 1].startMs : (curr.startMs + 4000)
            let isInstrumental = isInstrumentalText(curr.text)

            let lineEnd: Int = {
                if isInstrumental {
                    return nextStart
                } else if nextStart - curr.startMs >= 7000 {
                    return curr.startMs + 4500
                } else {
                    return nextStart
                }
            }()

            if isInstrumental {
                let dotWords = createInterludeDotWords(startMs: curr.startMs, endMs: nextStart)
                result.append(
                    LyricLine(
                        words: dotWords,
                        startMs: curr.startMs,
                        lineEndMs: nextStart,
                        isWordSynced: false,
                        agent: "v1",
                        isBackground: false,
                        oppositeAligned: false,
                        isSongwriter: false,
                        isInterlude: true,
                        interludeEndMs: nextStart,
                        rawText: "• • •",
                        isStatic: false
                    )
                )
            } else {
                result.append(
                    LyricLine(
                        words: [],
                        startMs: curr.startMs,
                        lineEndMs: max(curr.startMs + 500, lineEnd),
                        isWordSynced: false,
                        agent: "v1",
                        isBackground: false,
                        oppositeAligned: false,
                        isSongwriter: false,
                        isInterlude: false,
                        rawText: curr.text,
                        isStatic: false
                    )
                )

                if i + 1 < parsedLines.count && (nextStart - lineEnd) >= 3500 {
                    let dotWords = createInterludeDotWords(startMs: lineEnd, endMs: nextStart)
                    result.append(
                        LyricLine(
                            words: dotWords,
                            startMs: lineEnd,
                            lineEndMs: nextStart,
                            isWordSynced: false,
                            agent: "v1",
                            isBackground: false,
                            oppositeAligned: false,
                            isSongwriter: false,
                            isInterlude: true,
                            interludeEndMs: nextStart,
                            rawText: "• • •",
                            isStatic: false
                        )
                    )
                }
            }
        }
        return BackgroundVocalsEngine.processLines(result)
    }

    private func parsePlain(_ plainLyrics: String) -> [LyricLine] {
        let rawLines = plainLyrics.components(separatedBy: .newlines)
        var result: [LyricLine] = []
        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result.append(
                LyricLine(
                    words: [],
                    startMs: 0,
                    lineEndMs: 0,
                    isWordSynced: false,
                    agent: "v1",
                    isBackground: false,
                    oppositeAligned: false,
                    rawText: trimmed,
                    isStatic: true
                )
            )
        }
        return BackgroundVocalsEngine.processLines(result)
    }
}
