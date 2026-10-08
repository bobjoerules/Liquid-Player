import Foundation

// MARK: - Decoding Helpers

private func decodeFirst<T: Decodable, K: CodingKey>(from container: KeyedDecodingContainer<K>, keys: [K]) -> T? {
    for key in keys {
        if let val = try? container.decodeIfPresent(T.self, forKey: key) {
            return val
        }
    }
    return nil
}

private func decodeFlexibleDouble<K: CodingKey>(from container: KeyedDecodingContainer<K>, keys: [K]) -> Double? {
    for key in keys {
        if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: key) {
            return doubleVal
        }
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(intVal)
        }
        if let strVal = try? container.decodeIfPresent(String.self, forKey: key), let parsed = Double(strVal) {
            return parsed
        }
    }
    return nil
}

private struct AnyDecodableDummy: Decodable {}

private func decodeLossyArray<T: Decodable, K: CodingKey>(from container: KeyedDecodingContainer<K>, keys: [K]) -> [T]? {
    for key in keys {
        if var unkeyed = try? container.nestedUnkeyedContainer(forKey: key) {
            var results: [T] = []
            while !unkeyed.isAtEnd {
                if let item = try? unkeyed.decode(T.self) {
                    results.append(item)
                } else {
                    _ = try? unkeyed.decode(AnyDecodableDummy.self)
                }
            }
            if !results.isEmpty {
                return results
            }
        }
    }
    return nil
}

// MARK: - Spicy Lyrics API Decodable Models

struct SpicyLyricsEnvelope: Decodable {
    let Body: SpicyLyricsBody?
    let Status: Int?
    let type: String?
    let UploadAttribution: SpicyUploadAttributionDTO?
    let uploader: SpicyAttributionUserDTO?
    let maker: SpicyAttributionUserDTO?

    enum CodingKeys: String, CodingKey {
        case Body, body, data, Data, result, Result
        case Status, status, statusCode
        case type = "Type", typeLower = "type"
        case UploadAttribution, uploadAttributionLower = "uploadAttribution", attribution, Attribution, credits, Credits
        case uploader, Uploader
        case maker, Maker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.Body = decodeFirst(from: container, keys: [.Body, .body, .data, .Data, .result, .Result])
        self.Status = decodeFirst(from: container, keys: [.Status, .status, .statusCode])
        self.type = decodeFirst(from: container, keys: [.type, .typeLower])
        self.UploadAttribution = decodeFirst(from: container, keys: [.UploadAttribution, .uploadAttributionLower, .attribution, .Attribution, .credits, .Credits])
        self.uploader = decodeFirst(from: container, keys: [.uploader, .Uploader])
        self.maker = decodeFirst(from: container, keys: [.maker, .Maker])
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
        case SongWriters, songWritersLower = "songwriters"
        case type = "Type", typeLower = "type"
        case StartTime, startTime
        case EndTime, endTime
        case Content, contentLower = "content"
        case Lines, linesLower = "lines"
        case UploadAttribution, uploadAttributionLower = "uploadAttribution", attribution, Attribution, credits, Credits
        case uploader, Uploader
        case maker, Maker
        case plainLyrics
        case text
        case lyrics
    }

    init(
        id: String?,
        source: String?,
        SongWriters: [String]?,
        type: String?,
        StartTime: Double?,
        EndTime: Double?,
        Content: [SpicyContentLine]?,
        UploadAttribution: SpicyUploadAttributionDTO?,
        plainLyrics: String?,
        text: String?
    ) {
        self.id = id
        self.source = source
        self.SongWriters = SongWriters
        self.type = type
        self.StartTime = StartTime
        self.EndTime = EndTime
        self.Content = Content
        self.UploadAttribution = UploadAttribution
        self.plainLyrics = plainLyrics
        self.text = text
    }

    func withUploadAttribution(_ attr: SpicyUploadAttributionDTO?) -> SpicyLyricsBody {
        SpicyLyricsBody(
            id: id,
            source: source,
            SongWriters: SongWriters,
            type: type,
            StartTime: StartTime,
            EndTime: EndTime,
            Content: Content,
            UploadAttribution: attr ?? UploadAttribution,
            plainLyrics: plainLyrics,
            text: text
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try? container.decodeIfPresent(String.self, forKey: .id)
        self.source = try? container.decodeIfPresent(String.self, forKey: .source)
        self.SongWriters = decodeFirst(from: container, keys: [.SongWriters, .songWritersLower])
        self.type = decodeFirst(from: container, keys: [.type, .typeLower])
        self.StartTime = decodeFlexibleDouble(from: container, keys: [.StartTime, .startTime])
        self.EndTime = decodeFlexibleDouble(from: container, keys: [.EndTime, .endTime])

        var resolvedUploadAttr: SpicyUploadAttributionDTO? = decodeFirst(from: container, keys: [.UploadAttribution, .uploadAttributionLower, .attribution, .Attribution, .credits, .Credits])
        if resolvedUploadAttr == nil {
            let rootUploader: SpicyAttributionUserDTO? = decodeFirst(from: container, keys: [.uploader, .Uploader])
            let rootMaker: SpicyAttributionUserDTO? = decodeFirst(from: container, keys: [.maker, .Maker])
            if rootUploader != nil || rootMaker != nil {
                resolvedUploadAttr = SpicyUploadAttributionDTO(uploader: rootUploader, maker: rootMaker)
            }
        }
        self.UploadAttribution = resolvedUploadAttr

        self.plainLyrics = decodeFirst(from: container, keys: [.plainLyrics, .lyrics])
        self.text = try? container.decodeIfPresent(String.self, forKey: .text)

        let lineKeys: [CodingKeys] = [.Content, .Lines, .linesLower, .contentLower]
        if let lines: [SpicyContentLine] = decodeFirst(from: container, keys: lineKeys) {
            self.Content = lines
        } else if let lossyLines: [SpicyContentLine] = decodeLossyArray(from: container, keys: lineKeys) {
            self.Content = lossyLines
        } else if let stringArray: [String] = decodeFirst(from: container, keys: lineKeys) {
            self.Content = stringArray.map { SpicyContentLine(text: $0) }
        } else if let singleString: String = decodeFirst(from: container, keys: lineKeys) {
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

struct SpicyUploadAttributionDTO: Decodable {
    let Uploader: SpicyAttributionUserDTO?
    let Maker: SpicyAttributionUserDTO?

    enum CodingKeys: String, CodingKey {
        case Uploader, uploader, uploadUser = "upload_user", contributor, author
        case Maker, maker, syncMaker = "sync_maker", syncedBy = "synced_by", editor
    }

    init(uploader: SpicyAttributionUserDTO?, maker: SpicyAttributionUserDTO?) {
        self.Uploader = uploader
        self.Maker = maker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.Uploader = decodeFirst(from: container, keys: [.Uploader, .uploader, .uploadUser, .contributor, .author])
        self.Maker = decodeFirst(from: container, keys: [.Maker, .maker, .syncMaker, .syncedBy, .editor])
    }
}

struct SpicyAttributionUserDTO: Decodable {
    let id: String?
    let username: String?
    let avatar: String?
    let hasProfileBanner: Bool?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id, Id, ID, userId, user_id
        case username, Username, name, Name, displayName, DisplayName, user, User
        case avatar, Avatar, avatarUrl, avatar_url, AvatarUrl, image, Image
        case hasProfileBanner, has_profile_banner
        case url, Url, profile, Profile, profileUrl, profile_url
    }

    init(id: String?, username: String?, avatar: String?, hasProfileBanner: Bool?, url: String?) {
        self.id = id
        self.username = username
        self.avatar = avatar
        self.hasProfileBanner = hasProfileBanner
        self.url = url
    }

    init(from decoder: Decoder) throws {
        if let singleString = try? decoder.singleValueContainer().decode(String.self) {
            let clean = singleString.trimmingCharacters(in: .whitespacesAndNewlines)
            self.init(id: nil, username: clean.isEmpty ? nil : clean, avatar: nil, hasProfileBanner: nil, url: nil)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        var resolvedId: String? = decodeFirst(from: container, keys: [.id, .Id, .ID, .userId, .user_id])
        if resolvedId == nil {
            if let intId: Int = decodeFirst(from: container, keys: [.id, .Id, .ID, .userId, .user_id]) {
                resolvedId = String(intId)
            } else if let doubleId: Double = decodeFirst(from: container, keys: [.id, .Id, .ID, .userId, .user_id]) {
                resolvedId = String(format: "%.0f", doubleId)
            }
        }

        let resolvedUsername: String? = decodeFirst(from: container, keys: [.username, .Username, .name, .Name, .displayName, .DisplayName, .user, .User])
        let cleanUsername = resolvedUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAvatar: String? = decodeFirst(from: container, keys: [.avatar, .Avatar, .avatarUrl, .avatar_url, .AvatarUrl, .image, .Image])
        let resolvedBanner: Bool? = decodeFirst(from: container, keys: [.hasProfileBanner, .has_profile_banner])
        let resolvedUrl: String? = decodeFirst(from: container, keys: [.url, .Url, .profile, .Profile, .profileUrl, .profile_url])

        self.init(
            id: resolvedId,
            username: cleanUsername,
            avatar: resolvedAvatar,
            hasProfileBanner: resolvedBanner,
            url: resolvedUrl
        )
    }
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
        case typeLower = "type"
        case OppositeAligned, oppositeAligned
        case agent
        case Lead, lead
        case Background, background
        case StartTime, startTime, start, Start, begin, Begin
        case EndTime, endTime, end, End
        case Text, text
        case TransliteratedText, transliteratedText
        case TranslatedText, translatedText
    }

    init(from decoder: Decoder) throws {
        if let singleString = try? decoder.singleValueContainer().decode(String.self) {
            self.init(text: singleString)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type: String? = decodeFirst(from: container, keys: [.type, .typeLower])
        let OppositeAligned: Bool? = decodeFirst(from: container, keys: [.OppositeAligned, .oppositeAligned])
        let agent = try? container.decodeIfPresent(String.self, forKey: .agent)
        let Lead: SpicyVocalGroup? = decodeFirst(from: container, keys: [.Lead, .lead])
        let Background: [SpicyVocalGroup]? = decodeFirst(from: container, keys: [.Background, .background])
        let StartTime = decodeFlexibleDouble(from: container, keys: [.StartTime, .startTime, .start, .Start, .begin, .Begin])
        let EndTime = decodeFlexibleDouble(from: container, keys: [.EndTime, .endTime, .end, .End])
        let Text: String? = decodeFirst(from: container, keys: [.Text, .text])
        let TransliteratedText: String? = decodeFirst(from: container, keys: [.TransliteratedText, .transliteratedText])
        let TranslatedText: String? = decodeFirst(from: container, keys: [.TranslatedText, .translatedText])

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

struct SpicyVocalGroup: Decodable {
    let StartTime: Double?
    let EndTime: Double?
    let OppositeAligned: Bool?
    let agent: String?
    let TransliteratedText: String?
    let TranslatedText: String?
    let Syllables: [SpicySyllable]?

    enum CodingKeys: String, CodingKey {
        case StartTime, startTime, start, Start, begin, Begin
        case EndTime, endTime, end, End
        case OppositeAligned, oppositeAligned
        case agent
        case TransliteratedText, transliteratedText
        case TranslatedText, translatedText
        case Syllables, syllables, words, Words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.StartTime = decodeFlexibleDouble(from: container, keys: [.StartTime, .startTime, .start, .Start, .begin, .Begin])
        self.EndTime = decodeFlexibleDouble(from: container, keys: [.EndTime, .endTime, .end, .End])
        self.OppositeAligned = decodeFirst(from: container, keys: [.OppositeAligned, .oppositeAligned])
        self.agent = try? container.decodeIfPresent(String.self, forKey: .agent)
        self.TransliteratedText = decodeFirst(from: container, keys: [.TransliteratedText, .transliteratedText])
        self.TranslatedText = decodeFirst(from: container, keys: [.TranslatedText, .translatedText])
        self.Syllables = decodeFirst(from: container, keys: [.Syllables, .syllables, .words, .Words])
    }
}

struct SpicySyllable: Decodable {
    let Text: String
    let StartTime: Double
    let EndTime: Double
    let IsPartOfWord: Bool?
    let TransliteratedText: String?

    enum CodingKeys: String, CodingKey {
        case Text, text
        case StartTime, startTime, start, Start, begin, Begin
        case EndTime, endTime, end, End
        case IsPartOfWord, isPartOfWord
        case TransliteratedText, transliteratedText
    }

    init(from decoder: Decoder) throws {
        if let singleString = try? decoder.singleValueContainer().decode(String.self) {
            let clean = singleString.trimmingCharacters(in: .whitespacesAndNewlines)
            self.Text = clean
            self.StartTime = 0.0
            self.EndTime = 0.0
            self.IsPartOfWord = false
            self.TransliteratedText = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.Text = decodeFirst(from: container, keys: [.Text, .text]) ?? ""
        let start = decodeFlexibleDouble(from: container, keys: [.StartTime, .startTime, .start, .Start, .begin, .Begin]) ?? 0.0
        self.StartTime = start
        self.EndTime = decodeFlexibleDouble(from: container, keys: [.EndTime, .endTime, .end, .End]) ?? (start + 0.3)
        self.IsPartOfWord = decodeFirst(from: container, keys: [.IsPartOfWord, .isPartOfWord])
        self.TransliteratedText = decodeFirst(from: container, keys: [.TransliteratedText, .transliteratedText])
    }
}

// MARK: - Service Implementation

actor SpicyLyricsService {
    static let shared = SpicyLyricsService()
    
    private var cache: [String: ParsedLyrics] = [:]
    private var inFlightTasks: [String: Task<ParsedLyrics, Error>] = [:]
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }

    static func cleanTrackId(_ trackId: String) -> String {
        let stripped = trackId
            .replacingOccurrences(of: "spotify:track:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = stripped.range(of: #"[A-Za-z0-9]{22}"#, options: .regularExpression) {
            return String(stripped[match])
        }
        return stripped
    }

    func getCachedLyrics(for trackId: String) -> ParsedLyrics? {
        let cleanId = Self.cleanTrackId(trackId)
        return cache[cleanId]
    }

    func isLyricsCached(for trackId: String) -> Bool {
        let cleanId = Self.cleanTrackId(trackId)
        return cache[cleanId] != nil
    }

    func clearCache(for trackId: String) {
        let cleanId = Self.cleanTrackId(trackId)
        cache.removeValue(forKey: cleanId)
        inFlightTasks[cleanId]?.cancel()
        inFlightTasks.removeValue(forKey: cleanId)
    }

    func prefetchLyrics(for trackId: String) async {
        let cleanId = Self.cleanTrackId(trackId)
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
        let cleanId = Self.cleanTrackId(trackId)
        guard !cleanId.isEmpty else {
            throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid track ID."])
        }

        let rawApiKey = APIConfig.spicyLyricsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanApiKey = rawApiKey
            .replacingOccurrences(of: "Bearer ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\t\n\r "))

        guard !cleanApiKey.isEmpty else {
            throw NSError(
                domain: "LiquidPlayer.SpicyLyrics",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Spicy Lyrics API key not configured. Add Liquid Player from \(APIConfig.spicyLyricsCatalogUrl) to get your personal client key."]
            )
        }

        if let cached = cache[cleanId] {
            return cached
        }

        // Deduplicate in-flight requests for the same track
        if let existingTask = inFlightTasks[cleanId] {
            return try await existingTask.value
        }

        let task = Task<ParsedLyrics, Error> {
            let urlString = "https://api.spicylyrics.org/v1/lyrics/\(cleanId)"
            guard let requestUrl = URL(string: urlString) else {
                throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid request URL for \(cleanId)."])
            }

            var request = URLRequest(url: requestUrl)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(cleanApiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(cleanApiKey, forHTTPHeaderField: "Client-Key")
            request.setValue(cleanApiKey, forHTTPHeaderField: "X-Client-Key")
            request.setValue(cleanApiKey, forHTTPHeaderField: "X-API-Key")
            request.setValue("LiquidPlayer/1.1.4 (iOS; SpicyLyrics-Client)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json, text/xml, application/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")

            var lastError: Error?
            // Attempt request with 1 retry for transient network glitches
            for attempt in 1...2 {
                do {
                    let (data, response) = try await session.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
                    }

                    if httpResponse.statusCode == 404 {
                        throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: 404, userInfo: [NSLocalizedDescriptionKey: "Lyrics not found for \(cleanId)."])
                    }

                    guard httpResponse.statusCode == 200 else {
                        if httpResponse.statusCode == 503 {
                            throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: 503, userInfo: [NSLocalizedDescriptionKey: "Upstream lyrics service temporarily unavailable."])
                        }
                        throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                    }

                        // 1. Direct TTML / XML response check
                        let textStr = String(data: data, encoding: .utf8)
                        let trimmedText = textStr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if trimmedText.hasPrefix("<") || trimmedText.contains("<?xml") || (trimmedText.contains("<tt") && !trimmedText.hasPrefix("{")) {
                            if let parsed = try? TTMLLyricsParser.parse(data: data), !parsed.lines.isEmpty {
                                return parsed
                            }
                        }

                        // 2. Safely parse JSON dictionary to extract attribution and check embedded TTML without dropping credits
                        let jsonDict = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                        let extractedAttr = Self.extractAttribution(from: jsonDict)
                        let extractedSongwriters = Self.extractSongwriters(from: jsonDict)

                        // Check candidate embedded TTML string keys
                        let ttmlKeys = ["ttml", "TTML", "xml", "XML"]
                        for key in ttmlKeys {
                            let candidateXml: String? = (jsonDict[key] as? String) ?? ((jsonDict["body"] as? [String: Any])?[key] as? String) ?? ((jsonDict["data"] as? [String: Any])?[key] as? String)
                            if let xml = candidateXml, xml.contains("<tt") {
                                if let parsed = try? TTMLLyricsParser.parse(data: Data(xml.utf8)), !parsed.lines.isEmpty {
                                    let finalAttr = extractedAttr ?? parsed.attribution
                                    return ParsedLyrics(
                                        lines: parsed.lines,
                                        songwriters: !parsed.songwriters.isEmpty ? parsed.songwriters : extractedSongwriters,
                                        source: parsed.source ?? "Spicy Lyrics",
                                        attribution: finalAttr,
                                        isStatic: parsed.isStatic
                                    )
                                }
                            }
                        }

                        // 3. Flexible JSON decoding: Try envelope first, then direct body
                        let body: SpicyLyricsBody
                        if let envelope = try? JSONDecoder().decode(SpicyLyricsEnvelope.self, from: data), let envBody = envelope.Body {
                            if envBody.UploadAttribution == nil {
                                let envelopeAttr = envelope.UploadAttribution ?? (
                                    (envelope.uploader != nil || envelope.maker != nil) ? SpicyUploadAttributionDTO(uploader: envelope.uploader, maker: envelope.maker) : nil
                                )
                                body = envBody.withUploadAttribution(envelopeAttr)
                            } else {
                                body = envBody
                            }
                        } else if let directBody = try? JSONDecoder().decode(SpicyLyricsBody.self, from: data),
                                  (directBody.Content != nil || directBody.plainLyrics != nil || directBody.text != nil) {
                            body = directBody
                        } else if let bodyDict = (jsonDict["Body"] as? [String: Any]) ?? (jsonDict["body"] as? [String: Any]) ?? (jsonDict["data"] as? [String: Any]),
                                  let bodyData = try? JSONSerialization.data(withJSONObject: bodyDict),
                                  let parsedDictBody = try? JSONDecoder().decode(SpicyLyricsBody.self, from: bodyData) {
                            body = parsedDictBody
                        } else {
                            throw NSError(domain: "LiquidPlayer.SpicyLyrics", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty or unrecognized Spicy Lyrics response format."])
                        }

                        // 4. If plainLyrics or text contains TTML XML, parse it with TTMLLyricsParser while PRESERVING attribution!
                        if let ttmlText = body.plainLyrics ?? body.text, ttmlText.contains("<tt") {
                            if let parsed = try? TTMLLyricsParser.parse(data: Data(ttmlText.utf8)), !parsed.lines.isEmpty {
                                let finalAttr = extractedAttr ?? self.resolveAttribution(from: body.UploadAttribution) ?? parsed.attribution
                                let resolvedSrc: String
                                if let rawSource = body.source?.trimmingCharacters(in: .whitespacesAndNewlines), !rawSource.isEmpty {
                                    if rawSource.lowercased().contains("community") {
                                        resolvedSrc = "Spicy Lyrics Community"
                                    } else if rawSource.lowercased().contains("spicy") {
                                        resolvedSrc = finalAttr != nil ? "Spicy Lyrics Community" : "Spicy Lyrics"
                                    } else {
                                        resolvedSrc = "Spicy Lyrics (\(rawSource.replacingOccurrences(of: "_", with: " ").capitalized))"
                                    }
                                } else if finalAttr != nil {
                                    resolvedSrc = "Spicy Lyrics Community"
                                } else {
                                    resolvedSrc = parsed.source ?? "Spicy Lyrics"
                                }
                                return ParsedLyrics(
                                    lines: parsed.lines,
                                    songwriters: !parsed.songwriters.isEmpty ? parsed.songwriters : (body.SongWriters ?? extractedSongwriters),
                                    source: resolvedSrc,
                                    attribution: finalAttr,
                                    isStatic: parsed.isStatic
                                )
                            }
                        }

                        let parsed = self.parseLyricsBody(body, overrideAttribution: extractedAttr)
                        if !parsed.lines.isEmpty {
                            return parsed
                        }
                    } catch {
                        lastError = error
                        // Don't retry client errors (e.g. 404 or 401)
                        if let nsErr = error as NSError?, nsErr.code == 404 || nsErr.code == 401 {
                            break
                        }
                        if attempt < 2 {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }
                    }
                }

            throw lastError ?? NSError(domain: "LiquidPlayer.SpicyLyrics", code: -1, userInfo: [NSLocalizedDescriptionKey: "Spicy Lyrics request failed."])
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

    // MARK: - Attribution & Metadata Extraction Helpers

    private static func extractUser(from raw: Any?) -> SpicyAttributionUser? {
        guard let raw = raw else { return nil }
        if let str = raw as? String {
            let clean = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : SpicyAttributionUser(id: nil, username: clean, avatar: nil, url: nil)
        }
        if let num = raw as? NSNumber {
            let idStr = num.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return idStr.isEmpty ? nil : SpicyAttributionUser(id: idStr, username: idStr, avatar: nil, url: nil)
        }
        if let dict = raw as? [String: Any] {
            let id: String? = {
                if let s = dict["id"] as? String {
                    let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    return clean.isEmpty ? nil : clean
                }
                if let n = dict["id"] as? NSNumber { return n.stringValue }
                if let s = dict["userId"] as? String ?? dict["user_id"] as? String {
                    let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    return clean.isEmpty ? nil : clean
                }
                if let n = dict["userId"] as? NSNumber ?? dict["user_id"] as? NSNumber { return n.stringValue }
                return nil
            }()
            let username: String? = {
                let candidates = ["username", "Username", "name", "Name", "displayName", "DisplayName", "user", "User"]
                for key in candidates {
                    if let s = dict[key] as? String {
                        let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { return clean }
                    }
                }
                return nil
            }()
            let avatar: String? = {
                let candidates = ["avatar", "Avatar", "avatarUrl", "avatar_url", "AvatarUrl", "image", "Image"]
                for key in candidates {
                    if let s = dict[key] as? String {
                        let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { return clean }
                    }
                }
                return nil
            }()
            let url: String? = {
                let candidates = ["url", "Url", "profile", "Profile", "profileUrl", "profile_url"]
                for key in candidates {
                    if let s = dict[key] as? String {
                        let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { return clean }
                    }
                }
                return nil
            }()

            let finalUsername = username ?? id
            guard finalUsername != nil || id != nil else { return nil }
            return SpicyAttributionUser(id: id, username: finalUsername, avatar: avatar, url: url)
        }
        return nil
    }

    private static func extractAttribution(from jsonDict: [String: Any]) -> SpicyUploadAttribution? {
        let bodyDict = jsonDict["body"] as? [String: Any] ?? jsonDict["data"] as? [String: Any] ?? [:]

        let attrContainers = [
            jsonDict["uploadAttribution"] as? [String: Any],
            jsonDict["attribution"] as? [String: Any],
            jsonDict["credits"] as? [String: Any],
            bodyDict["uploadAttribution"] as? [String: Any],
            bodyDict["attribution"] as? [String: Any],
            bodyDict["credits"] as? [String: Any]
        ].compactMap { $0 }

        var resolvedUploader: SpicyAttributionUser? = nil
        var resolvedMaker: SpicyAttributionUser? = nil

        for container in attrContainers {
            if resolvedUploader == nil {
                let uploaderRaw = container["uploader"] ?? container["Uploader"] ?? container["uploadUser"] ?? container["upload_user"] ?? container["contributor"] ?? container["author"]
                resolvedUploader = extractUser(from: uploaderRaw)
            }
            if resolvedMaker == nil {
                let makerRaw = container["maker"] ?? container["Maker"] ?? container["syncMaker"] ?? container["sync_maker"] ?? container["syncedBy"] ?? container["synced_by"] ?? container["editor"]
                resolvedMaker = extractUser(from: makerRaw)
            }
        }

        // Direct root or body user keys
        if resolvedUploader == nil {
            resolvedUploader = extractUser(from: jsonDict["uploader"] ?? jsonDict["Uploader"] ?? bodyDict["uploader"] ?? bodyDict["Uploader"])
        }
        if resolvedMaker == nil {
            resolvedMaker = extractUser(from: jsonDict["maker"] ?? jsonDict["Maker"] ?? bodyDict["maker"] ?? bodyDict["Maker"])
        }

        if resolvedUploader != nil || resolvedMaker != nil {
            return SpicyUploadAttribution(uploader: resolvedUploader, maker: resolvedMaker)
        }
        return nil
    }

    private static func extractSongwriters(from jsonDict: [String: Any]) -> [String] {
        let bodyDict = jsonDict["body"] as? [String: Any] ?? jsonDict["data"] as? [String: Any] ?? [:]
        let candidates = [
            jsonDict["songWriters"] as? [String],
            jsonDict["songwriters"] as? [String],
            jsonDict["SongWriters"] as? [String],
            bodyDict["songWriters"] as? [String],
            bodyDict["songwriters"] as? [String],
            bodyDict["SongWriters"] as? [String]
        ]
        for c in candidates {
            if let writers = c, !writers.isEmpty {
                return writers
            }
        }
        return []
    }

    private func resolveAttribution(from uploadAttr: SpicyUploadAttributionDTO?) -> SpicyUploadAttribution? {
        guard let uploadAttr = uploadAttr else { return nil }
        let uploader = uploadAttr.Uploader.flatMap { dto -> SpicyAttributionUser? in
            let uname = dto.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            let uid = dto.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (uname != nil && !uname!.isEmpty) || (uid != nil && !uid!.isEmpty) else { return nil }
            return SpicyAttributionUser(id: uid, username: (uname != nil && !uname!.isEmpty) ? uname : uid, avatar: dto.avatar, url: dto.url)
        }
        let maker = uploadAttr.Maker.flatMap { dto -> SpicyAttributionUser? in
            let uname = dto.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            let uid = dto.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (uname != nil && !uname!.isEmpty) || (uid != nil && !uid!.isEmpty) else { return nil }
            return SpicyAttributionUser(id: uid, username: (uname != nil && !uname!.isEmpty) ? uname : uid, avatar: dto.avatar, url: dto.url)
        }
        if uploader != nil || maker != nil {
            return SpicyUploadAttribution(uploader: uploader, maker: maker)
        }
        return nil
    }

    private func isOppositeAligned(contentLine: SpicyContentLine, agentOrder: [String] = []) -> Bool {
        let agentCandidate = contentLine.agent ?? contentLine.Lead?.agent ?? contentLine.Background?.compactMap(\.agent).first
        if let agent = agentCandidate?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !agent.isEmpty {
            if agent.hasPrefix("v"), let num = Int(agent.dropFirst()) {
                return num % 2 == 0
            }
            if let num = Int(agent) {
                return num % 2 == 0
            }
            if let lastDigit = agent.compactMap({ $0.wholeNumberValue }).last {
                return lastDigit % 2 == 0
            }
            if let idx = agentOrder.firstIndex(of: agent) {
                return (idx + 1) % 2 == 0
            }
            if agent == "v1" || agent == "1" {
                return false
            }
        }
        return (contentLine.OppositeAligned == true) || (contentLine.Lead?.OppositeAligned == true)
    }

    private func parseLyricsBody(_ body: SpicyLyricsBody, overrideAttribution: SpicyUploadAttribution? = nil) -> ParsedLyrics {
        let songwriters = body.SongWriters ?? []
        var vocalUnits: [VocalUnit] = []
        var agentOrder: [String] = []

        if let contentLines = body.Content {
            for contentLine in contentLines {
                let candidate = contentLine.agent ?? contentLine.Lead?.agent ?? contentLine.Background?.compactMap(\.agent).first
                if let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty {
                    if !agentOrder.contains(raw) {
                        agentOrder.append(raw)
                    }
                }
            }
        }

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
                    let opposite = isOppositeAligned(contentLine: contentLine, agentOrder: agentOrder)

                    unitLeadLines.append(
                        LyricLine(
                            words: [],
                            startMs: startMs,
                            lineEndMs: endMs,
                            isWordSynced: false,
                            agent: contentLine.agent ?? contentLine.Lead?.agent ?? (opposite ? "v2" : "v1"),
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
                    let opposite = isOppositeAligned(contentLine: contentLine, agentOrder: agentOrder)
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
                            agent: contentLine.agent ?? contentLine.Lead?.agent ?? (opposite ? "v2" : "v1"),
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
                            let opposite = isOppositeAligned(contentLine: contentLine, agentOrder: agentOrder)
                            unitBgLines.append(
                                LyricLine(
                                    words: hasWordTimings ? effectiveBgWords : [],
                                    startMs: actualStart,
                                    lineEndMs: actualEnd,
                                    isWordSynced: hasWordTimings,
                                    agent: bg.agent ?? contentLine.agent ?? contentLine.Lead?.agent ?? (opposite ? "v2" : "v1"),
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

        var attribution: SpicyUploadAttribution? = overrideAttribution
        if attribution == nil, let uploadAttr = body.UploadAttribution {
            let uploader = uploadAttr.Uploader.flatMap { dto -> SpicyAttributionUser? in
                let uname = dto.username?.trimmingCharacters(in: .whitespacesAndNewlines)
                let uid = dto.id?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (uname != nil && !uname!.isEmpty) || (uid != nil && !uid!.isEmpty) else { return nil }
                return SpicyAttributionUser(id: uid, username: (uname != nil && !uname!.isEmpty) ? uname : uid, avatar: dto.avatar, url: dto.url)
            }
            let maker = uploadAttr.Maker.flatMap { dto -> SpicyAttributionUser? in
                let uname = dto.username?.trimmingCharacters(in: .whitespacesAndNewlines)
                let uid = dto.id?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (uname != nil && !uname!.isEmpty) || (uid != nil && !uid!.isEmpty) else { return nil }
                return SpicyAttributionUser(id: uid, username: (uname != nil && !uname!.isEmpty) ? uname : uid, avatar: dto.avatar, url: dto.url)
            }
            if uploader != nil || maker != nil {
                attribution = SpicyUploadAttribution(uploader: uploader, maker: maker)
            }
        }

        let resolvedSource: String
        if let rawSource = body.source?.trimmingCharacters(in: .whitespacesAndNewlines), !rawSource.isEmpty {
            if rawSource.lowercased().contains("community") {
                resolvedSource = "Spicy Lyrics Community"
            } else if rawSource.lowercased().contains("spicy") {
                resolvedSource = attribution != nil ? "Spicy Lyrics Community" : "Spicy Lyrics"
            } else {
                resolvedSource = "Spicy Lyrics (\(rawSource.replacingOccurrences(of: "_", with: " ").capitalized))"
            }
        } else if attribution != nil {
            resolvedSource = "Spicy Lyrics Community"
        } else {
            resolvedSource = "Spicy Lyrics"
        }

        let processedLines = BackgroundVocalsEngine.processLines(sortedAll)
        return ParsedLyrics(
            lines: processedLines,
            songwriters: songwriters,
            source: resolvedSource,
            attribution: attribution,
            isStatic: isStatic
        )
    }
}
