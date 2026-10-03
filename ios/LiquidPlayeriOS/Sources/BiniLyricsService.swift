import Foundation

actor BiniLyricsService {
    static let shared = BiniLyricsService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    private struct BiniResponse: Codable {
        let total: Int?
        let source: String?
        let results: [BiniTrackResult]?
    }

    private struct BiniTrackResult: Codable {
        let id: String?
        let track_name: String?
        let artist_name: String?
        let album_name: String?
        let duration: Int?
        let isrc: String?
        let timing_type: String?
        let lyricsUrl: String?
    }

    func fetchLyrics(
        isrc: String? = nil,
        trackTitle: String,
        artistName: String,
        albumName: String? = nil,
        durationSeconds: Int? = nil
    ) async -> ParsedLyrics? {
        var queryItems: [URLQueryItem] = []
        if let isrc = isrc, !isrc.isEmpty {
            queryItems.append(URLQueryItem(name: "isrc", value: isrc))
        } else {
            let cleanArtist = artistName.splitArtistNames.first ?? artistName
            queryItems.append(URLQueryItem(name: "track", value: trackTitle))
            queryItems.append(URLQueryItem(name: "artist", value: cleanArtist))
            if let album = albumName, !album.isEmpty {
                queryItems.append(URLQueryItem(name: "album", value: album))
            }
        }

        var components = URLComponents(string: "https://lyrics-api.binimum.org/")
        components?.queryItems = queryItems
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let envelope = try? JSONDecoder().decode(BiniResponse.self, from: data),
              let results = envelope.results else {
            return nil
        }

        // Validate candidate results against title, artist, and duration
        let matchingResult = results.first { candidate in
            guard let url = candidate.lyricsUrl, !url.isEmpty else { return false }

            // If ISRC was queried and matches, accept
            if let isrc = isrc, !isrc.isEmpty, let candIsrc = candidate.isrc, !candIsrc.isEmpty {
                if isrc.caseInsensitiveCompare(candIsrc) == .orderedSame {
                    return true
                }
            }

            // Duration verification: reject if duration differs significantly (e.g. remix vs original edit)
            if !TrackMatchUtils.durationsMatch(expected: durationSeconds, candidate: candidate.duration) {
                return false
            }

            // Track title matching verification
            guard let candTitle = candidate.track_name, !candTitle.isEmpty else { return false }
            guard TrackMatchUtils.titlesMatch(requested: trackTitle, candidate: candTitle) else { return false }

            // Artist verification
            if let candArtist = candidate.artist_name, !candArtist.isEmpty {
                let cleanArtist = artistName.splitArtistNames.first ?? artistName
                guard TrackMatchUtils.artistsMatch(requested: cleanArtist, candidate: candArtist) else { return false }
            }

            return true
        }

        guard let matched = matchingResult,
              let lyricsUrlString = matched.lyricsUrl,
              let lyricsURL = URL(string: lyricsUrlString) else {
            return nil
        }

        // Fetch the TTML file from lyricsUrl
        var ttmlRequest = URLRequest(url: lyricsURL)
        ttmlRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (ttmlData, ttmlResponse) = try? await session.data(for: ttmlRequest),
              let httpTtmlResponse = ttmlResponse as? HTTPURLResponse,
              httpTtmlResponse.statusCode == 200 else {
            return nil
        }

        guard let parsed = try? TTMLLyricsParser.parse(data: ttmlData),
              !parsed.lines.isEmpty else {
            return nil
        }

        return ParsedLyrics(
            lines: parsed.lines,
            songwriters: parsed.songwriters,
            source: "Apple Music (BiniLyrics)",
            attribution: nil
        )
    }
}
