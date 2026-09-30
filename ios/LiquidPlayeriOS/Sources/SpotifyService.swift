import Foundation
import AuthenticationServices
import CryptoKit

struct SpotifyTrackItem: Codable, Identifiable, Hashable {
    let id: String?
    let name: String
    let uri: String?
    let duration_ms: Int?
    let artists: [SpotifyArtistItem]?
    let album: SpotifyAlbumItem?

    var itemID: String {
        id ?? uri ?? "\(name)_\(duration_ms ?? 0)"
    }

    var artistNames: String {
        guard let artists = artists, !artists.isEmpty else { return "Unknown Artist" }
        return artists.map(\.name).joined(separator: ", ")
    }

    var artworkURL: URL? {
        guard let urlString = album?.images?.first?.url else { return nil }
        return URL(string: urlString)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(itemID)
    }

    static func == (lhs: SpotifyTrackItem, rhs: SpotifyTrackItem) -> Bool {
        lhs.itemID == rhs.itemID
    }
}

struct SpotifyArtistItem: Codable, Hashable {
    let id: String?
    let name: String
}

struct SpotifyAlbumItem: Codable, Hashable {
    let id: String?
    let name: String
    let images: [SpotifyImageItem]?
}

struct SpotifyImageItem: Codable, Hashable {
    let url: String
    let height: Int?
    let width: Int?
}

struct SpotifyDeviceItem: Codable, Identifiable, Hashable {
    let id: String?
    let is_active: Bool?
    let is_restricted: Bool?
    let name: String
    let type: String?
    let volume_percent: Int?

    var deviceID: String {
        id ?? name
    }
}

struct SpotifyPlaybackState: Codable {
    let is_playing: Bool?
    let progress_ms: Int?
    let item: SpotifyTrackItem?
    let shuffle_state: Bool?
    let repeat_state: String?
    let device: SpotifyDeviceItem?
    /// "track", "episode", "ad", or "unknown"
    let currently_playing_type: String?
}

struct SpotifyRecentlyPlayedResponse: Codable {
    struct PlayHistoryItem: Codable {
        let track: SpotifyTrackItem?
    }
    let items: [PlayHistoryItem]?
}

struct SpotifyTokenResponse: Codable {
    let access_token: String
    let token_type: String
    let scope: String?
    let expires_in: Int
    let refresh_token: String?
}

struct SpotifySearchResult: Codable {
    struct TracksWrapper: Codable {
        let items: [SpotifyTrackItem?]?
    }
    let tracks: TracksWrapper?
}

struct SpotifyQueueResponse: Codable {
    let currently_playing: SpotifyTrackItem?
    let queue: [SpotifyTrackItem]?
}

@MainActor
final class SpotifyService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isAuthenticated: Bool = false
    @Published var currentPlayback: SpotifyPlaybackState?
    @Published var currentTrack: SpotifyTrackItem?
    @Published var isPlaying: Bool = false
    @Published var progressMs: Int = 0
    @Published var durationMs: Int = 0
    @Published var isShuffleEnabled: Bool = false
    @Published var activeDeviceName: String? {
        didSet {
            if let val = activeDeviceName {
                UserDefaults.standard.set(val, forKey: "LiquidPlayer.spotifyLastActiveDeviceName")
            } else {
                UserDefaults.standard.removeObject(forKey: "LiquidPlayer.spotifyLastActiveDeviceName")
            }
        }
    }
    @Published var availableDevices: [SpotifyDeviceItem] = []
    @Published var authError: String?

    private(set) var lastActiveDeviceId: String? {
        get { UserDefaults.standard.string(forKey: "LiquidPlayer.spotifyLastActiveDeviceId") }
        set {
            if let val = newValue {
                UserDefaults.standard.set(val, forKey: "LiquidPlayer.spotifyLastActiveDeviceId")
            } else {
                UserDefaults.standard.removeObject(forKey: "LiquidPlayer.spotifyLastActiveDeviceId")
            }
        }
    }
    private var seekLockoutUntil: Date = .distantPast
    private var expectedSeekMs: Int = 0

    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "LiquidPlayer.spotifyAccessToken") }
        set { UserDefaults.standard.set(newValue, forKey: "LiquidPlayer.spotifyAccessToken") }
    }

    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "LiquidPlayer.spotifyRefreshToken") }
        set { UserDefaults.standard.set(newValue, forKey: "LiquidPlayer.spotifyRefreshToken") }
    }

    private var tokenExpiration: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "LiquidPlayer.spotifyTokenExpiration")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "LiquidPlayer.spotifyTokenExpiration")
        }
    }

    private var pollTimer: Timer?
    private var codeVerifier: String?
    private var refreshTask: Task<String?, Never>?

    @MainActor
    override init() {
        super.init()
        if let savedName = UserDefaults.standard.string(forKey: "LiquidPlayer.spotifyLastActiveDeviceName") {
            self.activeDeviceName = savedName
        }
        let hasSavedSession = (refreshToken != nil) || (accessToken != nil)
        if hasSavedSession {
            isAuthenticated = true
            startPolling()
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.refreshTokenIfNeeded()
                await self.fetchPlaybackState()
                _ = await self.fetchAvailableDevices()
            }
        }
        setupAppLifecycleObservers()
    }

    private func setupAppLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isAuthenticated else { return }
                self.startPolling()
                _ = await self.refreshTokenIfNeeded()
                await self.fetchPlaybackState()
                _ = await self.fetchAvailableDevices()
            }
        }
        #endif
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSWindow()
        #else
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
        #endif
    }

    // MARK: - OAuth Authentication
    func authorize() {
        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        let scopes = [
            "user-read-playback-state",
            "user-modify-playback-state",
            "user-read-currently-playing",
            "user-read-playback-position",
            "user-read-recently-played"
        ].joined(separator: " ")

        components.queryItems = [
            URLQueryItem(name: "client_id", value: APIConfig.spotifyClientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: APIConfig.spotifyRedirectUri),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: scopes)
        ]

        guard let authURL = components.url else { return }

        let callbackScheme = URL(string: APIConfig.spotifyRedirectUri)?.scheme ?? "liquidplayer"

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self = self else { return }
            if let error = error {
                Task { @MainActor in
                    self.authError = error.localizedDescription
                }
                return
            }

            guard let callbackURL = callbackURL,
                  let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
                Task { @MainActor in
                    self.authError = "Missing authorization code"
                }
                return
            }

            Task {
                await self.exchangeCodeForToken(code: code)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func login() {
        authorize()
    }

    func disconnect() {
        stopPolling()
        accessToken = nil
        refreshToken = nil
        tokenExpiration = nil
        lastActiveDeviceId = nil
        isAuthenticated = false
        currentPlayback = nil
        currentTrack = nil
        isPlaying = false
        progressMs = 0
        activeDeviceName = nil
        availableDevices = []
    }

    func logout() {
        disconnect()
    }

    private func exchangeCodeForToken(code: String) async {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        var items: [URLQueryItem] = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: APIConfig.spotifyRedirectUri),
            URLQueryItem(name: "client_id", value: APIConfig.spotifyClientId)
        ]

        if let verifier = codeVerifier {
            items.append(URLQueryItem(name: "code_verifier", value: verifier))
        }

        if !APIConfig.spotifyClientSecret.isEmpty {
            let authString = "\(APIConfig.spotifyClientId):\(APIConfig.spotifyClientSecret)"
            if let authData = authString.data(using: .utf8) {
                let base64 = authData.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }

        bodyComponents.queryItems = items
        request.httpBody = bodyComponents.query?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "Failed to exchange token"
                self.authError = msg
                return
            }

            let tokenData = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            self.accessToken = tokenData.access_token
            if let refresh = tokenData.refresh_token, !refresh.isEmpty {
                self.refreshToken = refresh
            }
            self.tokenExpiration = Date().addingTimeInterval(TimeInterval(max(tokenData.expires_in - 60, 60)))
            self.isAuthenticated = true
            self.authError = nil

            // Immediately fetch active playback and devices
            await fetchPlaybackState()
            _ = await fetchAvailableDevices()

            if self.currentTrack == nil {
                if let recent = await fetchRecentlyPlayedTrack() {
                    self.currentTrack = recent
                    self.isPlaying = false
                    self.progressMs = 0
                    if let dur = recent.duration_ms, dur > 0 {
                        self.durationMs = dur
                    }
                }
            }

            startPolling()
        } catch {
            self.authError = error.localizedDescription
        }
    }

    func refreshTokenIfNeeded(force: Bool = false) async -> String? {
        if let ongoing = refreshTask {
            return await ongoing.value
        }

        let needsRefresh = force
            || accessToken == nil
            || tokenExpiration == nil
            || Date() >= (tokenExpiration ?? Date())

        if !needsRefresh, let token = accessToken {
            return token
        }

        guard let currentRefresh = refreshToken, !currentRefresh.isEmpty else {
            return accessToken
        }

        let task = Task<String?, Never> { @MainActor [weak self] () -> String? in
            defer { self?.refreshTask = nil }
            return await self?.performRefreshToken(currentRefresh: currentRefresh)
        }
        self.refreshTask = task
        return await task.value
    }

    private func performRefreshToken(currentRefresh: String) async -> String? {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            return accessToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        var items: [URLQueryItem] = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: currentRefresh),
            URLQueryItem(name: "client_id", value: APIConfig.spotifyClientId)
        ]

        if !APIConfig.spotifyClientSecret.isEmpty {
            items.append(URLQueryItem(name: "client_secret", value: APIConfig.spotifyClientSecret))
            let authString = "\(APIConfig.spotifyClientId):\(APIConfig.spotifyClientSecret)"
            if let authData = authString.data(using: .utf8) {
                let base64 = authData.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }

        bodyComponents.queryItems = items
        request.httpBody = bodyComponents.query?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return accessToken
            }

            if (200...299).contains(httpResponse.statusCode) {
                let tokenData = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
                self.accessToken = tokenData.access_token
                if let newRefresh = tokenData.refresh_token, !newRefresh.isEmpty {
                    self.refreshToken = newRefresh
                }
                self.tokenExpiration = Date().addingTimeInterval(TimeInterval(max(tokenData.expires_in - 60, 60)))
                self.isAuthenticated = true
                self.authError = nil
                return tokenData.access_token
            } else if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let err = errorJson["error"] as? String, err == "invalid_grant" {
                    print("[SpotifyService] Token refresh revoked (invalid_grant). Disconnecting.")
                    self.disconnect()
                    return nil
                }
                return accessToken
            } else {
                return accessToken
            }
        } catch {
            return accessToken
        }
    }

    // MARK: - Playback State Polling
    func startPolling() {
        stopPolling()
        Task { @MainActor [weak self] in
            await self?.fetchPlaybackState()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollTimer?.invalidate()
            let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.fetchPlaybackState()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.pollTimer = timer
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func fetchPlaybackState() async {
        guard let token = await refreshTokenIfNeeded(),
              let url = URL(string: "https://api.spotify.com/v1/me/player") else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let requestStartTime = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let roundTripDuration = Date().timeIntervalSince(requestStartTime)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 401 {
                // Token expired mid-session. Force refresh and retry once.
                if let newToken = await refreshTokenIfNeeded(force: true) {
                    var retryRequest = URLRequest(url: url)
                    retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let retryStartTime = Date()
                    if let (retryData, retryResp) = try? await URLSession.shared.data(for: retryRequest),
                       let retryHttp = retryResp as? HTTPURLResponse {
                        let retryRtt = Date().timeIntervalSince(retryStartTime)
                        await handlePlaybackResponse(data: retryData, statusCode: retryHttp.statusCode, roundTripDuration: retryRtt)
                    }
                }
                return
            }

            await handlePlaybackResponse(data: data, statusCode: httpResponse.statusCode, roundTripDuration: roundTripDuration)
        } catch {
            // Silently continue polling
        }
    }

    private func handlePlaybackResponse(data: Data, statusCode: Int, roundTripDuration: TimeInterval = 0) async {
        if statusCode == 204 {
            // No active playback via /me/player, but connection is alive!
            self.isAuthenticated = true
            self.isPlaying = false
            if self.currentTrack == nil {
                await fetchCurrentlyPlayingTrackFallback()
            }
            if self.activeDeviceName == nil {
                _ = await fetchAvailableDevices()
            }
            return
        }

        guard (200...299).contains(statusCode) else { return }

        do {
            let state = try JSONDecoder().decode(SpotifyPlaybackState.self, from: data)
            self.isAuthenticated = true
            self.currentPlayback = state

            if let item = state.item {
                self.currentTrack = item
                if let dur = item.duration_ms, dur > 0 {
                    self.durationMs = dur
                }
            } else if state.currently_playing_type == "track" || state.currently_playing_type == nil {
                // item decoded as nil despite Spotify reporting a track is playing.
                await fetchCurrentlyPlayingTrackFallback()
            }

            let playing = state.is_playing ?? false
            self.isPlaying = playing
            let reportedProgress = state.progress_ms ?? 0
            // Compensate for one-way network transit latency while playing (approx. half of RTT, clamped to 350ms)
            let latencyCompensationMs = playing ? Int(min(roundTripDuration / 2.0, 0.35) * 1000.0) : 0
            let adjustedProgress = reportedProgress + latencyCompensationMs

            if Date() < self.seekLockoutUntil {
                if abs(adjustedProgress - self.expectedSeekMs) <= 1500 {
                    self.progressMs = adjustedProgress
                    self.seekLockoutUntil = .distantPast
                }
            } else {
                self.progressMs = adjustedProgress
            }
            self.isShuffleEnabled = state.shuffle_state ?? false
            if let device = state.device {
                self.activeDeviceName = device.name
                self.lastActiveDeviceId = device.id
            }
        } catch {
            print("[SpotifyService] Decode error in handlePlaybackResponse: \(error)")
            await fetchCurrentlyPlayingTrackFallback()
        }
    }

    /// Fallback fetch using the /currently-playing endpoint, which returns only the
    /// current track item and is more reliably populated than the full /player state.
    private func fetchCurrentlyPlayingTrackFallback() async {
        guard let token = await refreshTokenIfNeeded(),
              let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return }

        // The currently-playing response wraps item at the top level (same shape as SpotifyPlaybackState)
        if let state = try? JSONDecoder().decode(SpotifyPlaybackState.self, from: data) {
            if let item = state.item {
                self.currentTrack = item
                if let dur = item.duration_ms, dur > 0 {
                    self.durationMs = dur
                }
            }
            self.isPlaying = state.is_playing ?? false
            if let prog = state.progress_ms {
                self.progressMs = prog
            }
            return
        }

        // Last resort: try decoding the item directly as a SpotifyTrackItem
        if let item = try? JSONDecoder().decode(SpotifyTrackItem.self, from: data) {
            self.currentTrack = item
            if let dur = item.duration_ms, dur > 0 {
                self.durationMs = dur
            }
        }
    }

    // MARK: - Device Management
    struct SpotifyDevicesResponse: Codable {
        let devices: [SpotifyDeviceItem]
    }

    private func findBestTargetDevice(from devices: [SpotifyDeviceItem]) -> SpotifyDeviceItem? {
        // 1. Any device that Spotify currently reports as active
        if let active = devices.first(where: { $0.is_active == true }) {
            return active
        }

        // 2. Previously active device by ID (stays on the device that was playing before pausing)
        if let lastId = lastActiveDeviceId, let match = devices.first(where: { $0.id == lastId }) {
            return match
        }

        // 3. Previously active device by name (in case device ID rotated while device stayed the same)
        if let lastName = activeDeviceName?.lowercased(),
           let match = devices.first(where: { $0.name.lowercased() == lastName }) {
            return match
        }

        // 4. Current iPhone/iPad name or mobile device (fallback only when no previous active device exists)
        #if canImport(UIKit)
        let currentDeviceName = UIDevice.current.name.lowercased()
        if let match = devices.first(where: {
            let devName = $0.name.lowercased()
            return devName == currentDeviceName || currentDeviceName.contains(devName) || devName.contains(currentDeviceName)
        }) {
            return match
        }
        if let mobile = devices.first(where: {
            let type = ($0.type ?? "").lowercased()
            return type == "smartphone" || type == "tablet"
        }) {
            return mobile
        }
        #elseif canImport(AppKit)
        if let match = devices.first(where: { ($0.type ?? "").lowercased() == "computer" }) {
            return match
        }
        #endif

        // 5. Fallback to first available device
        return devices.first
    }

    @discardableResult
    func fetchAvailableDevices() async -> [SpotifyDeviceItem] {
        guard let token = await refreshTokenIfNeeded(),
              let url = URL(string: "https://api.spotify.com/v1/me/player/devices") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let decoded = try? JSONDecoder().decode(SpotifyDevicesResponse.self, from: data) else {
            return []
        }

        let devices = decoded.devices
        self.availableDevices = devices

        // Carefully preserve activeDeviceName / lastActiveDeviceId without switching away from user's device
        if let active = devices.first(where: { $0.is_active == true }) {
            self.activeDeviceName = active.name
            self.lastActiveDeviceId = active.id
        } else if let lastId = lastActiveDeviceId, let match = devices.first(where: { $0.id == lastId }) {
            self.activeDeviceName = match.name
            self.lastActiveDeviceId = match.id
        } else if let lastName = activeDeviceName?.lowercased(), let match = devices.first(where: { $0.name.lowercased() == lastName }) {
            self.activeDeviceName = match.name
            self.lastActiveDeviceId = match.id
        } else if self.lastActiveDeviceId == nil, let best = findBestTargetDevice(from: devices) {
            self.activeDeviceName = best.name
            self.lastActiveDeviceId = best.id
        }
        return devices
    }

    func getOrSelectDeviceId() async -> String? {
        let devices = await fetchAvailableDevices()
        return findBestTargetDevice(from: devices)?.id
    }

    // MARK: - Playback Controls
    func play() async {
        // 1. Resume on the currently active playback device without specifying a device (prevents device transfer)
        let result = await sendPlayerCommand(endpoint: "play", method: "PUT")
        if result.success {
            self.isPlaying = true
            try? await Task.sleep(nanoseconds: 200_000_000)
            await fetchPlaybackState()
            return
        }

        // 2. If Spotify has no active device session (e.g. paused device went idle/sleep),
        // try resuming explicitly on the last active device without switching devices
        if let lastId = lastActiveDeviceId {
            let resumeResult = await sendPlayerCommand(endpoint: "play?device_id=\(lastId)", method: "PUT")
            if resumeResult.success {
                self.isPlaying = true
                try? await Task.sleep(nanoseconds: 200_000_000)
                await fetchPlaybackState()
                return
            }
        }

        // 3. If that failed (device disconnected/offline), check available devices
        // and prefer the last active device/name before falling back
        let devices = await fetchAvailableDevices()
        if let target = findBestTargetDevice(from: devices), let targetId = target.id {
            self.lastActiveDeviceId = targetId
            self.activeDeviceName = target.name
            let retryResult = await sendPlayerCommand(endpoint: "play?device_id=\(targetId)", method: "PUT")
            if retryResult.success {
                self.isPlaying = true
                try? await Task.sleep(nanoseconds: 200_000_000)
                await fetchPlaybackState()
                return
            }
        }

        // Could not start playback
        self.isPlaying = false
        await fetchPlaybackState()
    }

    func pause() async {
        self.isPlaying = false
        let result = await sendPlayerCommand(endpoint: "pause", method: "PUT")
        if !result.success {
            await fetchPlaybackState()
        }
    }

    func togglePlayPause() async {
        if isPlaying {
            await pause()
        } else {
            await play()
        }
    }

    func next() async {
        _ = await sendPlayerCommand(endpoint: "next", method: "POST")
        try? await Task.sleep(nanoseconds: 300_000_000)
        await fetchPlaybackState()
    }

    func previous() async {
        _ = await sendPlayerCommand(endpoint: "previous", method: "POST")
        try? await Task.sleep(nanoseconds: 300_000_000)
        await fetchPlaybackState()
    }

    func seek(to positionMs: Int) async {
        let now = Date()
        self.seekLockoutUntil = now.addingTimeInterval(1.6)
        self.expectedSeekMs = positionMs
        self.progressMs = positionMs
        _ = await sendPlayerCommand(endpoint: "seek?position_ms=\(positionMs)", method: "PUT")
    }

    func toggleShuffle() async {
        let newState = !isShuffleEnabled
        self.isShuffleEnabled = newState
        _ = await sendPlayerCommand(endpoint: "shuffle?state=\(newState)", method: "PUT")
    }

    func fetchTrack(id: String) async -> SpotifyTrackItem? {
        guard let token = await refreshTokenIfNeeded() else { return nil }
        guard let url = URL(string: "https://api.spotify.com/v1/tracks/\(id)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                if let refreshedToken = await refreshTokenIfNeeded(force: true) {
                    var retryRequest = URLRequest(url: url)
                    retryRequest.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                    if let retryHttp = retryResponse as? HTTPURLResponse, (200...299).contains(retryHttp.statusCode) {
                        return try JSONDecoder().decode(SpotifyTrackItem.self, from: retryData)
                    }
                }
                return nil
            }
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(SpotifyTrackItem.self, from: data)
        } catch {
            return nil
        }
    }

    func fetchQueue() async -> [SpotifyTrackItem] {
        guard let token = await refreshTokenIfNeeded(),
              let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                if let refreshedToken = await refreshTokenIfNeeded(force: true) {
                    var retryRequest = URLRequest(url: url)
                    retryRequest.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                    if let retryHttp = retryResponse as? HTTPURLResponse, (200...299).contains(retryHttp.statusCode) {
                        let decoded = try JSONDecoder().decode(SpotifyQueueResponse.self, from: retryData)
                        return decoded.queue ?? []
                    }
                }
                return []
            }
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(SpotifyQueueResponse.self, from: data)
            return decoded.queue ?? []
        } catch {
            return []
        }
    }

    func fetchRecentlyPlayedTrack() async -> SpotifyTrackItem? {
        guard let token = await refreshTokenIfNeeded(),
              let url = URL(string: "https://api.spotify.com/v1/me/player/recently-played?limit=1") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
            return decoded.items?.first?.track
        } catch {
            return nil
        }
    }

    func searchTracks(query: String) async -> [SpotifyTrackItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Check if query is a Spotify track URL, URI, or 22-character ID
        var directId: String? = nil
        if trimmed.contains("/track/") {
            let parts = trimmed.components(separatedBy: "/track/")
            if let lastPart = parts.last {
                let clean = lastPart.components(separatedBy: "?").first ?? lastPart
                if clean.count == 22 {
                    directId = clean
                }
            }
        } else if trimmed.starts(with: "spotify:track:") {
            let id = String(trimmed.dropFirst("spotify:track:".count))
            if id.count == 22 {
                directId = id
            }
        } else if trimmed.count == 22 && !trimmed.contains(" ") {
            directId = trimmed
        }

        if let id = directId, let track = await fetchTrack(id: id) {
            return [track]
        }

        guard let token = await refreshTokenIfNeeded(),
              var components = URLComponents(string: "https://api.spotify.com/v1/search") else {
            return []
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "25")
        ]

        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                if let refreshedToken = await refreshTokenIfNeeded(force: true) {
                    var retryRequest = URLRequest(url: url)
                    retryRequest.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                    if let retryHttp = retryResponse as? HTTPURLResponse, (200...299).contains(retryHttp.statusCode) {
                        let result = try JSONDecoder().decode(SpotifySearchResult.self, from: retryData)
                        return result.tracks?.items?.compactMap { $0 } ?? []
                    }
                }
                return []
            }
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            let result = try JSONDecoder().decode(SpotifySearchResult.self, from: data)
            return result.tracks?.items?.compactMap { $0 } ?? []
        } catch {
            return []
        }
    }

    func playTrack(uri: String) async {
        let body: [String: Any] = ["uris": [uri]]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        // Try playing directly on current active device without transfer
        let result = await sendPlayerCommand(endpoint: "play", method: "PUT", body: bodyData)
        if result.success {
            self.isPlaying = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            await fetchPlaybackState()
            return
        }

        // If no active session, attempt last active device first before transferring
        if let lastId = lastActiveDeviceId {
            let retryResult = await sendPlayerCommand(endpoint: "play?device_id=\(lastId)", method: "PUT", body: bodyData)
            if retryResult.success {
                self.isPlaying = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                await fetchPlaybackState()
                return
            }
        }

        // If that fails, find best target device from available devices
        let devices = await fetchAvailableDevices()
        if let target = findBestTargetDevice(from: devices), let targetId = target.id {
            self.lastActiveDeviceId = targetId
            self.activeDeviceName = target.name
            let retryResult = await sendPlayerCommand(endpoint: "play?device_id=\(targetId)", method: "PUT", body: bodyData)
            if retryResult.success {
                self.isPlaying = true
            }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        await fetchPlaybackState()
    }

    func transferPlayback(to deviceId: String, play: Bool = true) async {
        let body: [String: Any] = ["device_ids": [deviceId], "play": play]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)
        let result = await sendPlayerCommand(endpoint: "", method: "PUT", body: bodyData)
        if result.success {
            self.lastActiveDeviceId = deviceId
            try? await Task.sleep(nanoseconds: 300_000_000)
            await fetchPlaybackState()
            _ = await fetchAvailableDevices()
        }
    }

    @discardableResult
    private func sendPlayerCommand(endpoint: String, method: String, body: Data? = nil) async -> (success: Bool, statusCode: Int) {
        guard let token = await refreshTokenIfNeeded() else {
            return (false, 401)
        }

        let path = endpoint.isEmpty ? "" : (endpoint.starts(with: "?") ? endpoint : "/\(endpoint)")
        let fullUrlString = endpoint.starts(with: "http") ? endpoint : "https://api.spotify.com/v1/me/player\(path)"
        guard let url = URL(string: fullUrlString) else {
            return (false, 400)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, -1)
            }

            if httpResponse.statusCode == 401 {
                if let newToken = await refreshTokenIfNeeded(force: true) {
                    var retryRequest = request
                    retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    if let (_, retryResp) = try? await URLSession.shared.data(for: retryRequest),
                       let retryHttp = retryResp as? HTTPURLResponse {
                        return ((200...299).contains(retryHttp.statusCode), retryHttp.statusCode)
                    }
                }
                return (false, 401)
            }

            return ((200...299).contains(httpResponse.statusCode), httpResponse.statusCode)
        } catch {
            return (false, -1)
        }
    }

    // MARK: - PKCE Helper
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .ascii) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
