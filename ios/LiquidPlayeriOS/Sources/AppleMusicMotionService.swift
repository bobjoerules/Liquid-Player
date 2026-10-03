import Foundation

struct MotionArtworkResult: Codable, Hashable {
    let squareVideoURL: URL?
    let tallVideoURL: URL?
    let previewImageURL: URL?
    let backgroundColorHex: String?
    let albumName: String?
    let artistName: String?
    let collectionId: Int?

    var hasVideo: Bool {
        squareVideoURL != nil || tallVideoURL != nil
    }
}

actor AppleMusicMotionService {
    static let shared = AppleMusicMotionService()

    private var memoryCache: [String: MotionArtworkResult] = [:]
    private var negativeCache: Set<String> = []
    private var inFlightTasks: [String: Task<MotionArtworkResult?, Never>] = [:]

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    /// Fetches Apple Music moving album artwork (.m3u8 HLS streams)
    func fetchMotionArtwork(
        trackTitle: String,
        artistName: String,
        albumName: String? = nil,
        isrc: String? = nil
    ) async -> MotionArtworkResult? {
        let key = cacheKey(artist: artistName, title: trackTitle, album: albumName, isrc: isrc)

        // 1. Fast cache check
        if let cached = memoryCache[key] {
            return cached
        }
        if negativeCache.contains(key) {
            return nil
        }

        // 2. In-flight task deduplication
        if let existingTask = inFlightTasks[key] {
            return await existingTask.value
        }

        let task = Task<MotionArtworkResult?, Never> { [weak self] () -> MotionArtworkResult? in
            guard let self = self else { return nil }
            return await self.performLookup(trackTitle: trackTitle, artistName: artistName, albumName: albumName, isrc: isrc)
        }

        inFlightTasks[key] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: key)

        if let result = result, result.hasVideo {
            memoryCache[key] = result
        } else {
            negativeCache.insert(key)
        }

        return result
    }

    private struct MatchedAlbumCandidate {
        let collectionId: Int
        let collectionName: String?
        let artistName: String?
        let score: Int
    }

    private func performLookup(
        trackTitle: String,
        artistName: String,
        albumName: String?,
        isrc: String?
    ) async -> MotionArtworkResult? {
        // Step 1: Collect candidates from song search (most specific to the currently playing track)
        var candidates = await searchAppleMusicSongCandidates(artist: artistName, title: trackTitle, album: albumName)

        // Step 2: If albumName is provided, also search album candidates
        if let album = albumName, !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let albumCandidates = await searchAppleMusicAlbumCandidates(artist: artistName, album: album)
            candidates.append(contentsOf: albumCandidates)
        }

        guard !candidates.isEmpty else {
            return nil
        }

        // Step 3: Sort by score descending and deduplicate by collectionId
        candidates.sort(by: { $0.score > $1.score })
        var seenIds = Set<Int>()
        var uniqueCandidates: [MatchedAlbumCandidate] = []
        for c in candidates {
            if !seenIds.contains(c.collectionId) {
                seenIds.insert(c.collectionId)
                uniqueCandidates.append(c)
            }
        }

        // Step 4: Check up to the top 3 candidates for motion artwork on Apple Music
        for candidate in uniqueCandidates.prefix(3) {
            let collectionId = candidate.collectionId
            let albumPageUrl = "https://music.apple.com/us/album/\(collectionId)"
            guard let url = URL(string: albumPageUrl) else { continue }

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")

            guard let (data, response) = try? await session.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                continue
            }

            // Extract motionDetailSquare and motionDetailTall video streams (.m3u8)
            let squareVideo = extractStreamURL(pattern: #""motionDetailSquare":\{.*?"video":"(https:[^"]+m3u8)""#, from: html)
            let tallVideo = extractStreamURL(pattern: #""motionDetailTall":\{.*?"video":"(https:[^"]+m3u8)""#, from: html)
            let bgColor = extractColorHex(pattern: #""bgColor":"([a-fA-F0-9]{6})""#, from: html)
            let previewImg = extractStreamURL(pattern: #""motionDetailSquare":\{.*?"url":"(https:[^"]+)""#, from: html)

            if squareVideo != nil || tallVideo != nil {
                return MotionArtworkResult(
                    squareVideoURL: squareVideo,
                    tallVideoURL: tallVideo,
                    previewImageURL: previewImg,
                    backgroundColorHex: bgColor,
                    albumName: candidate.collectionName,
                    artistName: candidate.artistName,
                    collectionId: collectionId
                )
            }
        }

        return nil
    }

    // MARK: - Normalization & Matching

    private func normalizeText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var s = text.lowercased()

        let patterns = [
            #"\s*[\(\[](?:feat\.?|ft\.?|featuring|with)\s+[^\)\]]+[\)\]]"#,
            #"\s*[\(\[](?:remastered|remaster|\d{4}\s+remaster|deluxe|expanded|anniversary|bonus\s+track|version|edition|single|explicit)[^\)\]]*[\)\]]"#,
            #"\s*-\s*(?:remastered|remaster|\d{4}\s+remaster|deluxe|expanded|bonus|single|version|explicit)[^$]*$"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: s.utf16.count), withTemplate: "")
            }
        }

        let cleaned = s.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    private func cleanSearchQuery(title: String) -> String {
        let normalized = normalizeText(title)
        return normalized.isEmpty ? title : normalized
    }

    private func matchTitles(candidate: String?, target: String) -> (matches: Bool, score: Int) {
        guard let candidate = candidate, !candidate.isEmpty else { return (false, 0) }
        let normCand = normalizeText(candidate)
        let normTarget = normalizeText(target)

        guard !normCand.isEmpty, !normTarget.isEmpty else { return (false, 0) }

        if normCand == normTarget {
            return (true, 100)
        }

        if normCand.count >= 4 && normTarget.count >= 4 && (normCand.hasPrefix(normTarget) || normTarget.hasPrefix(normCand)) {
            return (true, 75)
        }

        let wordsCand = Set(normCand.split(separator: " "))
        let wordsTarget = Set(normTarget.split(separator: " "))
        if !wordsCand.isEmpty && !wordsTarget.isEmpty {
            if wordsCand == wordsTarget {
                return (true, 90)
            }
            if wordsTarget.isSubset(of: wordsCand) || wordsCand.isSubset(of: wordsTarget) {
                let overlap = Double(wordsCand.intersection(wordsTarget).count) / Double(max(wordsCand.count, wordsTarget.count))
                if overlap >= 0.6 {
                    return (true, Int(50.0 + 30.0 * overlap))
                }
            }
        }

        return (false, 0)
    }

    private func matchArtists(candidate: String?, target: String) -> (matches: Bool, score: Int) {
        guard let candidate = candidate, !candidate.isEmpty else { return (false, 0) }
        let normCand = normalizeText(candidate)
        let normTarget = normalizeText(target)

        guard !normCand.isEmpty, !normTarget.isEmpty else { return (false, 0) }

        if normCand == normTarget {
            return (true, 60)
        }

        let candSplits = candidate.splitArtistNames.map { normalizeText($0) }.filter { !$0.isEmpty }
        let targetSplits = target.splitArtistNames.map { normalizeText($0) }.filter { !$0.isEmpty }

        if let firstCand = candSplits.first, let firstTarget = targetSplits.first, firstCand == firstTarget {
            return (true, 60)
        }

        for ca in candSplits {
            for ta in targetSplits {
                if ca == ta || (ca.count >= 4 && ta.count >= 4 && (ca.contains(ta) || ta.contains(ca))) {
                    return (true, 40)
                }
            }
        }

        return (false, 0)
    }

    private func matchAlbum(candidate: String?, target: String?) -> Bool {
        guard let candidate = candidate, let target = target, !target.isEmpty else { return false }
        let normCand = normalizeText(candidate)
        let normTarget = normalizeText(target)
        guard !normCand.isEmpty, !normTarget.isEmpty else { return false }

        if normCand == normTarget { return true }
        if normCand.count >= 4 && normTarget.count >= 4 && (normCand.contains(normTarget) || normTarget.contains(normCand)) {
            return true
        }
        return false
    }

    // MARK: - Search API Calls

    private struct iTunesAlbumSearchResponse: Codable {
        let resultCount: Int
        let results: [iTunesAlbumResult]
    }

    private struct iTunesAlbumResult: Codable {
        let collectionId: Int
        let collectionName: String?
        let artistName: String?
        let collectionViewUrl: String?
    }

    private struct iTunesSongSearchResponse: Codable {
        let resultCount: Int
        let results: [iTunesSongResult]
    }

    private struct iTunesSongResult: Codable {
        let collectionId: Int?
        let collectionName: String?
        let artistName: String?
        let trackName: String?
    }

    private func searchAppleMusicSongCandidates(artist: String, title: String, album: String?) async -> [MatchedAlbumCandidate] {
        let cleanArtist = artist.splitArtistNames.first ?? artist
        let cleanTitle = cleanSearchQuery(title: title)
        let terms = "\(cleanTitle) \(cleanArtist)"

        guard let encoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=15") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let decoded = try? JSONDecoder().decode(iTunesSongSearchResponse.self, from: data) else {
            return []
        }

        var candidates: [MatchedAlbumCandidate] = []
        for song in decoded.results {
            guard let colId = song.collectionId else { continue }

            // 1. Validate title match
            let (titleMatches, titleScore) = matchTitles(candidate: song.trackName, target: title)
            guard titleMatches else { continue }

            // 2. Validate artist match
            let (artistMatches, artistScore) = matchArtists(candidate: song.artistName, target: artist)
            guard artistMatches else { continue }

            // 3. Album bonus if candidate matches the playing album
            var totalScore = titleScore + artistScore
            if matchAlbum(candidate: song.collectionName, target: album) {
                totalScore += 40
            }

            candidates.append(MatchedAlbumCandidate(
                collectionId: colId,
                collectionName: song.collectionName,
                artistName: song.artistName,
                score: totalScore
            ))
        }

        return candidates
    }

    private func searchAppleMusicAlbumCandidates(artist: String, album: String) async -> [MatchedAlbumCandidate] {
        guard !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let cleanArtist = artist.splitArtistNames.first ?? artist
        let cleanAlbum = cleanSearchQuery(title: album)
        let terms = "\(cleanAlbum) \(cleanArtist)"

        guard let encoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=album&limit=10") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let decoded = try? JSONDecoder().decode(iTunesAlbumSearchResponse.self, from: data) else {
            return []
        }

        var candidates: [MatchedAlbumCandidate] = []
        for alb in decoded.results {
            // Validate album match
            guard matchAlbum(candidate: alb.collectionName, target: album) else { continue }

            // Validate artist match
            let (artistMatches, artistScore) = matchArtists(candidate: alb.artistName, target: artist)
            guard artistMatches else { continue }

            let score = 120 + artistScore
            candidates.append(MatchedAlbumCandidate(
                collectionId: alb.collectionId,
                collectionName: alb.collectionName,
                artistName: alb.artistName,
                score: score
            ))
        }

        return candidates
    }

    // MARK: - Stream Extraction

    private func extractStreamURL(pattern: String, from text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        let raw = nsString.substring(with: match.range(at: 1))
        let cleaned = raw.replacingOccurrences(of: #"\\/"#, with: "/")
        return URL(string: cleaned)
    }

    private func extractColorHex(pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        let hex = nsString.substring(with: match.range(at: 1))
        return "#\(hex)"
    }

    private func cacheKey(artist: String, title: String, album: String?, isrc: String?) -> String {
        if let isrc = isrc, !isrc.isEmpty {
            return "isrc_\(isrc.lowercased())"
        }
        let cleanArtist = normalizeText(artist)
        let cleanTitle = normalizeText(title)
        let cleanAlbum = normalizeText(album ?? "")
        return "\(cleanArtist)_\(cleanTitle)_\(cleanAlbum)"
    }

    public func clearCache() {
        memoryCache.removeAll()
        negativeCache.removeAll()
    }
}
