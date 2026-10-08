import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

private var isMac: Bool {
    return isMacPlatform
}

private func formatRemainingSeconds(_ totalSeconds: Int) -> String {
    if totalSeconds >= 3600 {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    } else if totalSeconds >= 60 {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(seconds)s"
    } else {
        return "\(totalSeconds)s"
    }
}

struct ContentView: View {
    private enum AppTab: Hashable {
        case nowPlaying
        case library
        case settings
    }

    private enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "Last 30 Days"
        case saved = "Saved TTML"
        case needsUpdate = "Needs Update"

        var id: String { self.rawValue }
    }

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = PlayerViewModel()
    @ObservedObject private var libraryManager = LibraryManager.shared
    @AppStorage("hasCompletedIntro") private var hasCompletedIntro = false
    @State private var isFullScreenNowPlaying = false
    @State private var isFullScreenControlsHidden = false
    @State private var selectedTab: AppTab = .nowPlaying
    @State private var libraryFilter: LibraryFilter = .all
    @Namespace private var libraryFilterNamespace
    @State private var librarySearchText = ""
    @State private var viewingTTMLSong: LibrarySong? = nil
    @State private var isShowingQueue = false
    @State private var isShowingSpicyConnect = false
    @State private var isShowingTTMLImporter = false
    @State private var targetSongForTTMLImport: LibrarySong? = nil
    @State private var isAppLoading: Bool = true
    @State private var logoScale: CGFloat = 0.85
    @State private var logoOpacity: Double = 0.0

    var body: some View {
        ZStack {
            mainContent
                .sheet(isPresented: $isShowingQueue) {
                    QueueView(viewModel: viewModel)
                }
                .sheet(item: $viewingTTMLSong) { song in
                    TTMLViewerSheet(
                        song: song,
                        onUpload: {
                            targetSongForTTMLImport = song
                            isShowingTTMLImporter = true
                        },
                        onDelete: {
                            viewModel.deleteSavedTTML(for: song.id)
                        }
                    )
                }
                .sheet(isPresented: $isShowingSpicyConnect) {
                    SpicyLyricsConnectSheet(viewModel: viewModel)
                        .presentationDetents([.fraction(0.85), .large])
                        .presentationDragIndicator(.visible)
                }
                .fileImporter(
                    isPresented: $isShowingTTMLImporter,
                    allowedContentTypes: [
                        UTType(filenameExtension: "ttml") ?? .xml,
                        .xml,
                        .plainText
                    ],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        for url in urls {
                            viewModel.importLocalTTML(url: url, targetTrackId: targetSongForTTMLImport?.id)
                        }
                    case .failure(let error):
                        viewModel.errorMessage = "Import cancelled: \(error.localizedDescription)"
                    }
                }
                .background {
                    Button("") {
                        viewModel.togglePlayback()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .opacity(0.001)
                    .frame(width: 1, height: 1)
                }
                .onChange(of: isFullScreenNowPlaying) { _, isFS in
                    if !isFS {
                        isFullScreenControlsHidden = false
                    }
                }

            if let toast = viewModel.importToastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text(toast)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    .padding(.bottom, isFullScreenNowPlaying ? 40 : 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation {
                                viewModel.importToastMessage = nil
                            }
                        }
                    }
                }
                .zIndex(200)
            }

            if isAppLoading {
                appLoadingView
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.55)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.45)) {
                isAppLoading = false
            }
        }
    }

    // MARK: - App Loading Splash View
    private var appLoadingView: some View {
        ZStack {
            (colorScheme == .light ? Color(uiColor: .systemBackground) : Color.black)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                #if canImport(UIKit)
                if let uiImage = UIImage(named: "AppLogo") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: isMac ? 130 : 108, height: isMac ? 130 : 108)
                        .clipShape(RoundedRectangle(cornerRadius: isMac ? 30 : 25, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: isMac ? 30 : 25, style: .continuous)
                                .stroke(colorScheme == .light ? Color.black.opacity(0.10) : Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .light ? 0.15 : 0.6), radius: 24, y: 12)
                        .shadow(color: (colorScheme == .light ? Color.clear : Color.white.opacity(0.12)), radius: 28, y: 0)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 108, height: 108)
                        .background((colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.12)), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }
                #else
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(colorScheme == .light ? Color.black.opacity(0.10) : Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .light ? 0.15 : 0.6), radius: 24, y: 12)
                    .shadow(color: (colorScheme == .light ? Color.clear : Color.white.opacity(0.12)), radius: 28, y: 0)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                #endif

                VStack(spacing: 8) {
                    Text("Liquid Player")
                        .font(.system(size: isMac ? 26 : 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .opacity(logoOpacity)

                    ProgressView()
                        .tint(Color.primary.opacity(0.7))
                        .scaleEffect(0.9)
                }
            }
        }
        .transition(.asymmetric(
            insertion: .identity,
            removal: .opacity.combined(with: .scale(scale: 1.05))
        ))
        .zIndex(100)
    }

    private var mainContent: some View {
        ZStack {
            #if canImport(UIKit)
            PlayerBackgroundView(
                style: viewModel.backgroundStyle,
                artwork: viewModel.artwork,
                motionURL: viewModel.isMotionArtworkEnabled ? (viewModel.motionArtworkTallURL ?? viewModel.motionArtworkURL) : nil,
                paletteHexes: viewModel.artworkPaletteHexes
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: viewModel.backgroundStyle)
            #else
            (colorScheme == .light ? Color.white : Color.black).ignoresSafeArea()
            #endif

            if !hasCompletedIntro && !viewModel.spotifyService.isAuthenticated && viewModel.selectedTrackID == nil {
                introductionView
            } else if isFullScreenNowPlaying {
                fullScreenNowPlayingView
                    .transition(.opacity)
                    .zIndex(50)
            } else {
                TabView(selection: $selectedTab) {
                    nowPlayingPage
                        .tag(AppTab.nowPlaying)
                        .tabItem {
                            Label("Now Playing", systemImage: "quote.bubble.fill")
                        }

                    libraryPage
                        .tag(AppTab.library)
                        .tabItem {
                            Label("Library", systemImage: "music.note.list")
                        }

                    settingsPage
                        .tag(AppTab.settings)
                        .tabItem {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                }
                .tint(colorScheme == .light ? .black : .white)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Now Playing Page
    private var nowPlayingPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            topBar(title: "Now Playing")

            spotifyStatusBanner

            if viewModel.selectedTrackID != nil && viewModel.lines.isEmpty && !viewModel.isLoadingLyrics {
                Spacer()

                VStack(spacing: 24) {
                    dynamicArtworkView(size: isMac ? 280 : 220)
                        .shadow(color: .black.opacity(colorScheme == .light ? 0.15 : 0.3), radius: 15, x: 0, y: 10)

                    VStack(spacing: 6) {
                        MarqueeText(
                            text: viewModel.nowPlayingTitle,
                            font: .system(size: isMac ? 32 : 24, weight: .bold),
                            color: .primary,
                            alignment: .center
                        )
                        .padding(.horizontal, 32)

                        MarqueeText(
                            text: viewModel.authorMetadata,
                            font: .system(size: isMac ? 18 : 15, weight: .semibold),
                            color: .secondary,
                            alignment: .center
                        )
                        .padding(.horizontal, 32)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                VStack(spacing: 16) {
                    timelineSeekBar
                    controls
                }
            } else if viewModel.selectedTrackID != nil {
                if isMac {
                    macSideBySideNowPlayingView(isFullScreen: false)
                } else {
                    heroPanel
                    timelineSeekBar
                    lyricsPanel()
                    controls

                    Spacer(minLength: 0)
                }
            } else {
                // Empty state when nothing is playing
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.1, green: 0.8, blue: 0.5).opacity(0.2), Color.blue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 140, height: 140)

                        Image(systemName: "music.note")
                            .font(.system(size: 54))
                            .foregroundStyle(.primary.opacity(0.7))
                    }

                    VStack(spacing: 8) {
                        Text(viewModel.spotifyService.isAuthenticated ? "Connected to Spotify" : "No Spotify Track Active")
                            .font(.system(size: isMac ? 28 : 24, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(viewModel.spotifyService.isAuthenticated ? "Play any song on Spotify to start live syllable synchronization, or pick a track from your Library." : "Play a track on Spotify or connect your account to start live syllable synchronization.")
                            .font(.system(size: isMac ? 17 : 15, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            if !viewModel.spotifyService.isAuthenticated {
                                Button {
                                    viewModel.spotifyService.login()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "link")
                                            .font(.system(size: isMac ? 17 : 15, weight: .bold))
                                        Text("Connect Spotify")
                                            .font(.system(size: isMac ? 17 : 15, weight: .bold))
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 0.11, green: 0.73, blue: 0.33), in: Capsule())
                                    .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                openSpotifyApp()
                            } label: {
                                HStack(spacing: 8) {
                                    SpotifyLogoShape(size: isMac ? 20 : 18, color: viewModel.spotifyService.isAuthenticated ? .white : .primary)
                                    Text("Open Spotify")
                                        .font(.system(size: isMac ? 17 : 15, weight: .semibold))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(viewModel.spotifyService.isAuthenticated ? Color(red: 0.11, green: 0.73, blue: 0.33) : (colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.12)), in: Capsule())
                                .foregroundStyle(viewModel.spotifyService.isAuthenticated ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            isShowingSpicyConnect = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: isMac ? 17 : 15, weight: .bold))
                                Text(viewModel.isSpicyLyricsConnected ? "Spicy Lyrics API Active" : "Connect Spicy Lyrics")
                                    .font(.system(size: isMac ? 17 : 15, weight: .bold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.45, blue: 0.1), Color(red: 0.95, green: 0.22, blue: 0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                            .foregroundStyle(.white)
                            .shadow(color: Color.orange.opacity(0.35), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Settings Page
    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar(title: "Settings")
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 8)

            SettingsView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom) {
            if viewModel.selectedTrackID != nil {
                miniPlayerBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Library Page (Songs Played in the Last 30 Days with Saved TTML)
    private var libraryPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header: Apple Music Large Title & Actions
                topBar(title: "Library", subtitle: "Played in last 30 days") {
                    Button {
                        targetSongForTTMLImport = nil
                        isShowingTTMLImporter = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.doc.fill")
                                .font(.system(size: isMac ? 14 : 12, weight: .semibold))
                            Text("Upload TTML")
                                .font(.system(size: isMac ? 13 : 11, weight: .bold))
                        }
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Upload TTML files locally")
                }
                .padding(.top, 8)

                // Outdated TTML Notice (Only shown if songs actually need update!)
                if !libraryManager.songsNeedingTTMLUpdate.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundStyle(Color.orange)
                            .font(.system(size: 16))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(libraryManager.songsNeedingTTMLUpdate.count) songs have outdated lyrics")
                                .font(.system(size: isMac ? 15 : 13, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            Text("Saved over 30 days ago")
                                .font(.system(size: isMac ? 13 : 11))
                                .foregroundStyle(Color.secondary)
                        }

                        Spacer()

                        Button {
                            Task {
                                await libraryManager.updateAllExpired()
                            }
                        } label: {
                            if libraryManager.isBatchUpdating {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.primary)
                            } else {
                                Text("Update")
                                    .font(.system(size: isMac ? 14 : 12, weight: .bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(libraryManager.isBatchUpdating)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Apple-style Filter Tabs (Taller Touch Target & Modern Glass Style)
                HStack(spacing: 4) {
                    libraryFilterTab(
                        title: "All",
                        count: libraryManager.songsPlayedInLast30Days.count,
                        filter: .all
                    )

                    libraryFilterTab(
                        title: "Saved TTML",
                        count: libraryManager.songsWithValidTTML.count,
                        filter: .saved
                    )

                    if !libraryManager.songsNeedingTTMLUpdate.isEmpty {
                        libraryFilterTab(
                            title: "Needs Update",
                            count: libraryManager.songsNeedingTTMLUpdate.count,
                            filter: .needsUpdate,
                            badgeColor: .orange
                        )
                    }
                }
                .padding(4)
                .modifier(LibraryFilterContainerGlassModifier())

                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.secondary)
                        .font(.system(size: isMac ? 16 : 14))

                    TextField("Search library", text: $librarySearchText)
                        .font(.system(size: isMac ? 16 : 14))
                        .foregroundStyle(Color.primary)
                        .autocorrectionDisabled()

                    if !librarySearchText.isEmpty {
                        Button {
                            librarySearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(colorScheme == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Songs List (Clean, Borderless Apple Music Rows)
                let songs = filteredLibrarySongs
                if songs.isEmpty {
                    emptyLibraryState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            VStack(spacing: 0) {
                                LibrarySongRowView(
                                    song: song,
                                    isCurrent: viewModel.currentTrackId == song.id,
                                    isUpdating: libraryManager.updatingTrackIds.contains(song.id),
                                    onPlay: {
                                        viewModel.playLibrarySong(song)
                                        selectedTab = .nowPlaying
                                    },
                                    onUpdateTTML: {
                                        Task {
                                            _ = await libraryManager.updateTTML(for: song.id)
                                        }
                                    },
                                    onViewTTML: {
                                        viewingTTMLSong = song
                                    },
                                    onUploadTTML: {
                                        targetSongForTTMLImport = song
                                        isShowingTTMLImporter = true
                                    },
                                    onDeleteTTML: {
                                        viewModel.deleteSavedTTML(for: song.id)
                                    }
                                )

                                if index < songs.count - 1 {
                                    Divider()
                                        .overlay(Color.primary.opacity(0.08))
                                        .padding(.leading, 64)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.selectedTrackID != nil {
                miniPlayerBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
    }

    private func libraryFilterTab(
        title: String,
        count: Int,
        filter: LibraryFilter,
        badgeColor: Color? = nil
    ) -> some View {
        let isSelected = libraryFilter == filter
        let isLight = colorScheme == .light

        let countTextColor: Color = {
            if let badgeColor = badgeColor {
                return badgeColor
            }
            return isSelected ? .primary : .secondary
        }()

        let badgeFillColor: Color = {
            if isSelected {
                return isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.20)
            } else {
                return isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08)
            }
        }()

        let badgeStrokeColor: Color = {
            if isLight {
                return Color.black.opacity(isSelected ? 0.12 : 0.05)
            } else {
                return Color.white.opacity(isSelected ? 0.25 : 0.10)
            }
        }()

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                libraryFilter = filter
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: isMac ? 15 : 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text("\(count)")
                    .font(.system(size: isMac ? 13 : 11, weight: .bold))
                    .foregroundStyle(countTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(badgeFillColor)
                            .overlay(
                                Capsule()
                                    .stroke(badgeStrokeColor, lineWidth: 0.8)
                            )
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: isMac ? 46 : 42)
            .background {
                if isSelected {
                    Color.clear
                        .modifier(LibraryFilterActiveTabGlassModifier())
                        .matchedGeometryEffect(id: "activeLibraryFilterTab", in: libraryFilterNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredLibrarySongs: [LibrarySong] {
        let base: [LibrarySong]
        switch libraryFilter {
        case .all:
            base = libraryManager.songsPlayedInLast30Days
        case .saved:
            base = libraryManager.songsWithValidTTML
        case .needsUpdate:
            base = libraryManager.songsNeedingTTMLUpdate
        }

        if librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return base
        }

        let query = librarySearchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(query) ||
            $0.artistNames.lowercased().contains(query) ||
            ($0.albumName?.lowercased().contains(query) ?? false)
        }
    }

    @ViewBuilder
    private var emptyLibraryState: some View {
        VStack(spacing: 14) {
            Image(systemName: libraryFilter == .needsUpdate ? "checkmark.seal.fill" : "music.note.list")
                .font(.system(size: isMac ? 48 : 40))
                .foregroundStyle(libraryFilter == .needsUpdate ? Color.green.opacity(0.8) : .secondary)

            Text(emptyStateTitle)
                .font(.system(size: isMac ? 20 : 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(emptyStateSubtitle)
                .font(.system(size: isMac ? 15 : 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyStateTitle: String {
        switch libraryFilter {
        case .all:
            return librarySearchText.isEmpty ? "No Songs Played in the Last 30 Days" : "No Matching Songs"
        case .saved:
            return "No Saved TTML Yet"
        case .needsUpdate:
            return "All Saved TTML Up to Date"
        }
    }

    private var emptyStateSubtitle: String {
        switch libraryFilter {
        case .all:
            return librarySearchText.isEmpty ? "Songs you play will automatically appear here with their saved TTML lyrics." : "Try searching for another track or artist name."
        case .saved:
            return "Play songs to automatically download and cache their TTML lyrics offline for 30 days."
        case .needsUpdate:
            return "All songs played in the last 30 days have fresh TTML lyrics (< 30 days old)."
        }
    }

    @ViewBuilder
    private var spotifyStatusBanner: some View {
        if viewModel.spotifyService.isRateLimited {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 14))
                    Text("Spotify rate-limited: resuming in \(formatRemainingSeconds(viewModel.spotifyService.rateLimitRetryAfter))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                if viewModel.spotifyService.rateLimitRetryAfter > 180 {
                    Text("Bypass this wait immediately by adding your own Spotify Client ID in Settings > API Configuration.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        } else if viewModel.spotifyService.sessionNeedsReauth {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text("Spotify session expired.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    viewModel.spotifyService.login()
                } label: {
                    Text("Reconnect")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.11, green: 0.73, blue: 0.33), in: Capsule())
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        } else if viewModel.spotifyService.isDeviceIdle && !viewModel.spotifyService.isPlaying && viewModel.selectedTrackID != nil {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                Text("Spotify is idle. Play music in Spotify to resume sync.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    openSpotifyApp()
                } label: {
                    Text("Open Spotify")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.12), in: Capsule())
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Top Bar
    private func topBar<Trailing: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(alignment: subtitle != nil ? .firstTextBaseline : .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: isMac ? 38 : 34, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: isMac ? 15 : 13, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: isMac ? 15 : 13, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.67))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                trailing()

                if title == "Now Playing" {
                    Button {
                        targetSongForTTMLImport = nil
                        isShowingTTMLImporter = true
                    } label: {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: isMac ? 16 : 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: isMac ? 44 : 38, height: isMac ? 44 : 38)
                            .modifier(MiniPlayerButtonBackgroundModifier())
                            .contentShape(Circle())
                    }
                    .buttonStyle(LiquidScaleButtonStyle())
                    .help("Upload Local TTML Lyrics")

                    Button {
                        isShowingSpicyConnect = true
                    } label: {
                        Image(systemName: "flame.fill")
                            .font(.system(size: isMac ? 16 : 14, weight: .semibold))
                            .foregroundStyle(viewModel.isSpicyLyricsConnected ? Color.orange : .secondary)
                            .frame(width: isMac ? 44 : 38, height: isMac ? 44 : 38)
                            .modifier(MiniPlayerButtonBackgroundModifier())
                            .contentShape(Circle())
                    }
                    .buttonStyle(LiquidScaleButtonStyle())
                    .help("Spicy Lyrics API Connection")

                    if viewModel.selectedTrackID != nil {
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                isFullScreenNowPlaying = true
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: isMac ? 17 : 14, weight: isMac ? .bold : .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: isMac ? 44 : 38, height: isMac ? 44 : 38)
                                .modifier(MiniPlayerButtonBackgroundModifier())
                                .contentShape(Circle())
                        }
                        .buttonStyle(LiquidScaleButtonStyle())
                    }
                }
            }
        }
    }

    private var syncSection: some View {
        HStack(spacing: 8) {
            syncButton(title: "-100") {
                viewModel.adjustLyricOffset(by: -100)
            }

            syncButton(title: "-50") {
                viewModel.adjustLyricOffset(by: -50)
            }

            syncButton(title: "Reset") {
                viewModel.resetLyricOffset()
            }

            syncButton(title: "+50") {
                viewModel.adjustLyricOffset(by: 50)
            }

            syncButton(title: "+100") {
                viewModel.adjustLyricOffset(by: 100)
            }

            Spacer()

            Text("Sync \(viewModel.lyricOffsetMs >= 0 ? "+" : "")\(viewModel.lyricOffsetMs) ms")
                .font(.system(size: isMac ? 15 : 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var heroPanel: some View {
        HStack(spacing: 16) {
            artworkView
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        isFullScreenNowPlaying = true
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                MarqueeText(
                    text: viewModel.nowPlayingTitle,
                    font: .system(size: isMac ? 36 : 28, weight: .semibold),
                    color: .primary
                )

                MarqueeText(
                    text: viewModel.authorMetadata,
                    font: .system(size: isMac ? 19 : 15, weight: .medium),
                    color: .secondary
                )
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var miniPlayerBar: some View {
        HStack(spacing: 14) {
            compactArtworkView
                .onTapGesture {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        isFullScreenNowPlaying = true
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(
                    text: viewModel.nowPlayingTitle,
                    font: .system(size: isMac ? 18 : 15, weight: .semibold),
                    color: .primary
                )

                Text(viewModel.authorMetadata)
                    .font(.system(size: isMac ? 14 : 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    isFullScreenNowPlaying = true
                }
            }

            HStack(spacing: 10) {
                Button(action: viewModel.togglePlayback) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(LiquidScaleButtonStyle())
                .highPriorityGesture(TapGesture().onEnded {
                    viewModel.togglePlayback()
                })

                Button {
                    viewModel.playNextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(colorScheme == .light ? Color.black.opacity(0.05) : Color.white.opacity(0.10), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(LiquidScaleButtonStyle())
                .highPriorityGesture(TapGesture().onEnded {
                    viewModel.playNextTrack()
                })
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(MiniPlayerBackgroundModifier())
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                isFullScreenNowPlaying = true
            }
        }
    }

    private var compactArtworkView: some View {
        ZStack {
            #if canImport(UIKit)
            if let artwork = viewModel.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                artworkFallback
            }

            if viewModel.isMotionArtworkEnabled, let motionURL = viewModel.motionArtworkURL {
                MotionArtworkPlayerView(streamURL: motionURL, placeholder: viewModel.artwork)
            }
            #else
            artworkFallback
            #endif
        }
        .frame(width: isMac ? 68 : 52, height: isMac ? 68 : 52)
        .clipShape(RoundedRectangle(cornerRadius: isMac ? 10 : 8, style: .continuous))
    }

    private var artworkView: some View {
        ZStack {
            #if canImport(UIKit)
            if let artwork = viewModel.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                artworkFallback
            }

            if viewModel.isMotionArtworkEnabled, let motionURL = viewModel.motionArtworkURL {
                MotionArtworkPlayerView(streamURL: motionURL, placeholder: viewModel.artwork)
            }
            #else
            artworkFallback
            #endif
        }
        .frame(width: isMac ? 150 : 108, height: isMac ? 150 : 108)
        .clipShape(RoundedRectangle(cornerRadius: isMac ? 14 : 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isMac ? 14 : 10, style: .continuous)
                .stroke(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
    }

    private var artworkFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.18),
                    colorScheme == .light ? Color.black.opacity(0.03) : Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: isMac ? 44 : 30, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var hasTranslations: Bool {
        viewModel.lines.contains { $0.translation != nil }
    }

    private var hasRomanization: Bool {
        viewModel.lines.contains { $0.romanization != nil }
    }

    private func lyricsPanel(isFullScreen: Bool = false) -> some View {
        LyricsPanelView(
            timeKeeper: viewModel.timeKeeper,
            viewModel: viewModel,
            isFullScreen: isFullScreen,
            isFullScreenControlsHidden: isFullScreenControlsHidden,
            isFullScreenNowPlaying: isFullScreenNowPlaying
        )
    }

    private var controls: some View {
        HStack(spacing: 0) {
            // Far left control: Shuffle
            controlButton(systemName: "shuffle", isActive: viewModel.isShuffleEnabled, isAction: false) {
                viewModel.toggleShuffle()
            }

            Spacer(minLength: 8)

            // Centered controls: Backward, Play/Pause, Forward
            HStack(spacing: isMac ? 20 : 24) {
                controlButton(systemName: "backward.fill") {
                    viewModel.playPreviousTrack()
                }

                Button(action: viewModel.togglePlayback) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 66, height: 66)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LiquidScaleButtonStyle())
                .highPriorityGesture(TapGesture().onEnded {
                    viewModel.togglePlayback()
                })

                controlButton(systemName: "forward.fill") {
                    viewModel.playNextTrack()
                }
            }

            Spacer(minLength: 8)

            // Far right control: Open Spotify
            Button {
                openSpotifyApp()
            } label: {
                SpotifyLogoShape(size: 24, color: .primary)
                    .frame(width: isMac ? 56 : 52, height: isMac ? 56 : 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LiquidScaleButtonStyle())
            .highPriorityGesture(TapGesture().onEnded {
                openSpotifyApp()
            })
            .help("Open in Spotify")
        }
        .padding(.horizontal, 8)
    }

    private func controlButton(systemName: String, isActive: Bool = false, isAction: Bool = true, action: @escaping () -> Void) -> some View {
        let isHighlighted = isActive || isAction
        let isHeart = systemName.contains("heart")
        let foregroundColor: Color = {
            if isHeart && isActive {
                return .red
            }
            return isHighlighted ? .primary : .secondary
        }()

        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isMac ? 24 : 22, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: isMac ? 56 : 52, height: isMac ? 56 : 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(LiquidScaleButtonStyle())
        .highPriorityGesture(TapGesture().onEnded {
            action()
        })
    }

    private func openSpotifyApp() {
        #if canImport(UIKit)
        if let appUrl = URL(string: "spotify:") {
            UIApplication.shared.open(appUrl, options: [:]) { success in
                if !success {
                    if let webUrl = URL(string: "https://open.spotify.com") {
                        UIApplication.shared.open(webUrl)
                    }
                }
            }
        }
        #elseif canImport(AppKit)
        if let appUrl = URL(string: "spotify:") {
            NSWorkspace.shared.open(appUrl)
        } else if let webUrl = URL(string: "https://open.spotify.com") {
            NSWorkspace.shared.open(webUrl)
        }
        #endif
    }

    private func syncButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: isMac ? 15 : 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mac Side-by-Side Now Playing Layout
    @ViewBuilder
    private func macSideBySideNowPlayingView(isFullScreen: Bool) -> some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let totalHeight = geo.size.height
            let isCompactWindow = totalWidth < 680

            if isCompactWindow {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        heroPanel
                        timelineSeekBar
                        controls
                        lyricsPanel(isFullScreen: isFullScreen)
                    }
                    .padding(.top, isFullScreen ? 36 : 0)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            } else {
                HStack(spacing: 0) {
                    // Left Column: Album Cover, Scrubber, Title & Author, Controls
                    let leftColWidth = max(340, min(totalWidth * 0.44, 480))
                    let maxArtByWidth = leftColWidth - 48
                    let maxArtByHeight = totalHeight * 0.48
                    let artworkSize = max(240, min(maxArtByWidth, maxArtByHeight, 380))

                    VStack(spacing: 14) {
                        Spacer(minLength: 16)

                        dynamicArtworkView(size: artworkSize)
                            .shadow(color: .black.opacity(colorScheme == .light ? 0.20 : 0.50), radius: 24, x: 0, y: 12)

                        TimelineSeekBarView(
                            timeKeeper: viewModel.timeKeeper,
                            viewModel: viewModel,
                            isCompactHorizontal: true
                        )
                        .frame(width: artworkSize)

                        VStack(spacing: 4) {
                            MarqueeText(
                                text: viewModel.displayTrackTitle,
                                font: .system(size: isFullScreen ? 28 : 24, weight: .bold, design: .rounded),
                                color: .primary,
                                alignment: .center
                            )

                            MarqueeText(
                                text: viewModel.displayTrackArtist,
                                font: .system(size: isFullScreen ? 17 : 15, weight: .semibold, design: .rounded),
                                color: .secondary,
                                alignment: .center
                            )
                        }
                        .frame(maxWidth: max(artworkSize, min(leftColWidth - 48, 400)))

                        controls
                            .frame(maxWidth: leftColWidth - 32)

                        Spacer(minLength: 16)
                    }
                    .padding(.top, isFullScreen ? 36 : 0)
                    .frame(width: leftColWidth)
                    .contentShape(Rectangle())

                    // Right Column: Lyrics
                    Group {
                        if !viewModel.lines.isEmpty || viewModel.isLoadingLyrics {
                            lyricsPanel(isFullScreen: isFullScreen)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.trailing, 24)
                        } else {
                            VStack(spacing: 12) {
                                Spacer()
                                Image(systemName: "music.note")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.secondary.opacity(0.6))
                                Text("No Lyrics Available")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("No synchronized lyrics found for this track.")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.trailing, 24)
                        }
                    }
                    .padding(.top, isFullScreen ? 36 : 0)
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var fullScreenNowPlayingView: some View {
        ZStack(alignment: .topTrailing) {
            #if canImport(UIKit)
            PlayerBackgroundView(
                style: viewModel.backgroundStyle,
                artwork: viewModel.artwork,
                motionURL: viewModel.isMotionArtworkEnabled ? (viewModel.motionArtworkTallURL ?? viewModel.motionArtworkURL) : nil,
                paletteHexes: viewModel.artworkPaletteHexes
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: viewModel.backgroundStyle)
            #else
            (colorScheme == .light ? Color.white : Color.black).ignoresSafeArea()
            #endif

            if isMac {
                macSideBySideNowPlayingView(isFullScreen: true)
            } else {
                iosFullScreenNowPlayingView
            }

            if isMac {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        isFullScreenNowPlaying = false
                        isFullScreenControlsHidden = false
                    }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .modifier(MiniPlayerButtonBackgroundModifier())
                        .contentShape(Circle())
                }
                .buttonStyle(LiquidScaleButtonStyle())
                .contentShape(Circle())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            isFullScreenNowPlaying = false
                            isFullScreenControlsHidden = false
                        }
                    }
                )
                .keyboardShortcut(.escape, modifiers: [])
                .padding(.top, 48)
                .padding(.trailing, 24)
                .zIndex(100)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var iosFullScreenNowPlayingView: some View {
        VStack(spacing: isFullScreenControlsHidden ? 12 : 20) {
            // Header with dismiss button and title
            if !isFullScreenControlsHidden {
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            isFullScreenNowPlaying = false
                            isFullScreenControlsHidden = false
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: isMac ? 18 : 15, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: isMac ? 44 : 38, height: isMac ? 44 : 38)
                            .modifier(MiniPlayerButtonBackgroundModifier())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                isFullScreenNowPlaying = false
                                isFullScreenControlsHidden = false
                            }
                        }
                    )

                    Spacer()

                    Text("Now Playing")
                        .font(.system(size: isMac ? 20 : 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isFullScreenControlsHidden.toggle()
                            }
                        }

                    Spacer()

                    Color.clear
                        .frame(width: isMac ? 44 : 38, height: isMac ? 44 : 38)
                }
                .padding(.horizontal, isMac ? 24 : 18)
                .padding(.top, isMac ? 20 : 16)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }

            if viewModel.selectedTrackID != nil && viewModel.lines.isEmpty && !viewModel.isLoadingLyrics {
                VStack(spacing: 28) {
                    Spacer()

                    dynamicArtworkView(size: isMac ? 340 : 280)
                        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 12)

                    VStack(spacing: 8) {
                        MarqueeText(
                            text: viewModel.nowPlayingTitle,
                            font: .system(size: isMac ? 32 : 26, weight: .bold),
                            color: .primary,
                            alignment: .center
                        )
                        .padding(.horizontal, 32)

                        MarqueeText(
                            text: viewModel.authorMetadata,
                            font: .system(size: isMac ? 19 : 16, weight: .semibold),
                            color: .secondary,
                            alignment: .center
                        )
                        .padding(.horizontal, 32)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isFullScreenControlsHidden.toggle()
                    }
                }

                VStack(spacing: 24) {
                    timelineSeekBar
                    if !isFullScreenControlsHidden {
                        controls
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            ))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, isFullScreenControlsHidden ? 32 : 36)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: 20) {
                    largeArtworkView

                    VStack(alignment: .leading, spacing: 6) {
                        MarqueeText(
                            text: viewModel.nowPlayingTitle,
                            font: .system(size: isMac ? 30 : 24, weight: .bold),
                            color: .primary
                        )

                        MarqueeText(
                            text: viewModel.authorMetadata,
                            font: .system(size: isMac ? 18 : 15, weight: .medium),
                            color: .secondary
                        )
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, isFullScreenControlsHidden ? 16 : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isFullScreenControlsHidden.toggle()
                    }
                }

                lyricsPanel(isFullScreen: true)
                    .background(
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isFullScreenControlsHidden.toggle()
                                }
                            }
                    )

                VStack(spacing: 20) {
                    timelineSeekBar
                    if !isFullScreenControlsHidden {
                        controls
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            ))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, isFullScreenControlsHidden ? 30 : 24)
                .contentShape(Rectangle())
            }
        }
    }

    private var largeArtworkView: some View {
        dynamicArtworkView(size: isMac ? 104 : 86)
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    private func dynamicArtworkView(size: CGFloat) -> some View {
        let cornerRadius = min(max(size * 0.055, 10), 24)
        return ZStack {
            #if canImport(UIKit)
            if let artwork = viewModel.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                dynamicFallback(size: size)
            }

            if viewModel.isMotionArtworkEnabled, let motionURL = viewModel.motionArtworkURL {
                MotionArtworkPlayerView(streamURL: motionURL, placeholder: viewModel.artwork)
            }
            #else
            dynamicFallback(size: size)
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func dynamicFallback(size: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.18),
                    colorScheme == .light ? Color.black.opacity(0.03) : Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.35, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var timelineSeekBar: some View {
        TimelineSeekBarView(timeKeeper: viewModel.timeKeeper, viewModel: viewModel)
    }

    private var introductionView: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 36) {
                    VStack(spacing: 12) {
                        Text("Liquid Player")
                            .font(.system(size: isMac ? 54 : 42, weight: .black))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.11, green: 0.85, blue: 0.45), Color(red: 0.2, green: 0.65, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("Your Music, Liquid & Synchronized.")
                            .font(.system(size: isMac ? 22 : 18, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("Syllable-synchronized lyrics powered by Spicy Lyrics and Spotify.")
                            .font(.system(size: isMac ? 16 : 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 24) {
                        tutorialRow(
                            systemImage: "waveform.badge.magnifyingglass",
                            title: "Spotify Web API",
                            description: "Connect your Spotify account to control playback, search tracks, and sync state smoothly in real-time."
                        )

                        tutorialRow(
                            systemImage: "quote.bubble.fill",
                            title: "Spicy Lyrics API",
                            description: "Instant syllable-level and line-level synchronized lyrics rendered with bouncy physics."
                        )

                        tutorialRow(
                            systemImage: "sparkles",
                            title: "Liquid Experience",
                            description: "Dynamic artwork background, Romaji romanization, instant translation, and keyboard shortcuts."
                        )
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }

            VStack(spacing: 16) {
                Button {
                    hasCompletedIntro = true
                    viewModel.spotifyService.login()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(.system(size: 18, weight: .bold))
                        Text("Connect with Spotify")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.11, green: 0.73, blue: 0.33), in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button("Explore App First") {
                    withAnimation(.spring()) {
                        hasCompletedIntro = true
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(
                LinearGradient(
                    colors: [
                        .clear,
                        (colorScheme == .light ? Color(uiColor: .systemBackground).opacity(0.85) : Color.black.opacity(0.85)),
                        (colorScheme == .light ? Color(uiColor: .systemBackground) : Color.black)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((colorScheme == .light ? Color(uiColor: .systemBackground) : Color.black).ignoresSafeArea())
    }

    private func tutorialRow(systemImage: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: isMac ? 32 : 28))
                .foregroundStyle(Color(red: 0.11, green: 0.85, blue: 0.45))
                .frame(width: isMac ? 40 : 36)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: isMac ? 19 : 17, weight: .bold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: isMac ? 16 : 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(colorScheme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - Spotify Brand Icon & Artwork Components
struct SpotifyLogoShape: View {
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let s = min(w, h) / 24.0

            // 1. Draw solid circular base disc
            let circleRect = CGRect(x: 0, y: 0, width: 24.0 * s, height: 24.0 * s)
            context.fill(Path(ellipseIn: circleRect), with: .color(color))

            // 2. Cut out authentic Spotify sound waves using destinationOut
            var waves = context
            waves.blendMode = .destinationOut

            func drawWave(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, strokeWidth: CGFloat) {
                var path = Path()
                path.move(to: CGPoint(x: start.x * s, y: start.y * s))
                path.addCurve(
                    to: CGPoint(x: end.x * s, y: end.y * s),
                    control1: CGPoint(x: control1.x * s, y: control1.y * s),
                    control2: CGPoint(x: control2.x * s, y: control2.y * s)
                )
                waves.stroke(
                    path,
                    with: .color(.black),
                    style: StrokeStyle(lineWidth: strokeWidth * s, lineCap: .round)
                )
            }

            drawWave(
                start: CGPoint(x: 4.8, y: 8.6),
                control1: CGPoint(x: 10.5, y: 6.8),
                control2: CGPoint(x: 15.5, y: 7.2),
                end: CGPoint(x: 19.5, y: 9.8),
                strokeWidth: 2.2
            )
            drawWave(
                start: CGPoint(x: 5.4, y: 12.0),
                control1: CGPoint(x: 10.6, y: 10.4),
                control2: CGPoint(x: 14.8, y: 10.8),
                end: CGPoint(x: 18.8, y: 13.0),
                strokeWidth: 1.95
            )
            drawWave(
                start: CGPoint(x: 6.2, y: 15.2),
                control1: CGPoint(x: 10.8, y: 13.8),
                control2: CGPoint(x: 14.2, y: 14.2),
                end: CGPoint(x: 17.6, y: 16.0),
                strokeWidth: 1.65
            )
        }
        .frame(width: size, height: size)
    }
}

struct SpotifyArtworkView: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat

    init(url: URL?, size: CGFloat = 54, cornerRadius: CGFloat = 8) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SpotifyTrackListRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let track: SpotifyTrackItem
    let isActive: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: isMac ? 16 : 12) {
                SpotifyArtworkView(url: track.artworkURL, size: isMac ? 60 : 48, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(.system(size: isMac ? 17 : 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(track.artistNames)
                        .font(.system(size: isMac ? 14 : 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                    }

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(isActive ? Color(red: 0.11, green: 0.85, blue: 0.45) : .secondary)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isActive ? Color(red: 0.11, green: 0.85, blue: 0.45).opacity(0.5) : (colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.06)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onToggleFavorite()
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
            }
        }
    }
}




#if canImport(UIKit)
private struct PlayerBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: PlayerBackgroundStyle
    let artwork: UIImage?
    var motionURL: URL? = nil
    var paletteHexes: [String] = []

    private var paletteColors: [Color] {
        if paletteHexes.isEmpty {
            return [
                Color(hex: "#38BDF8"),
                Color(hex: "#818CF8"),
                Color(hex: "#C084FC"),
                Color(hex: "#F472B6")
            ]
        }
        return paletteHexes.map { Color(hex: $0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let isLight = colorScheme == .light
            let c0 = paletteColors[0 % paletteColors.count]
            let c1 = paletteColors[1 % paletteColors.count]

            ZStack {
                switch style {
                case .black:
                    isLight ? Color(uiColor: .systemBackground) : Color.black

                case .blurred:
                    ZStack {
                        // 1. Ambient underlay from the album's exact dominant palette
                        LinearGradient(
                            colors: isLight
                                ? [c0.opacity(0.18), Color(uiColor: .systemBackground), c1.opacity(0.12)]
                                : [c0.opacity(0.24), Color(red: 0.05, green: 0.05, blue: 0.07), c1.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        // 2. High-vibrancy blurred artwork (or motion artwork)
                        ZStack {
                            if let artwork {
                                Image(uiImage: artwork)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: size.width, height: size.height)
                                    .scaleEffect(1.30)
                                    .blur(radius: 65)
                                    .saturation(1.15)
                                    .contrast(1.02)
                                    .opacity(isLight ? 0.35 : 0.50)
                                    .clipped()
                            }
                            if let motionURL {
                                MotionArtworkPlayerView(streamURL: motionURL, placeholder: artwork)
                                    .frame(width: size.width, height: size.height)
                                    .scaleEffect(1.30)
                                    .blur(radius: 60)
                                    .saturation(1.15)
                                    .contrast(1.02)
                                    .opacity(isLight ? 0.35 : 0.50)
                                    .clipped()
                            } else if artwork == nil {
                                LinearGradient(
                                    colors: isLight
                                        ? [Color(red: 0.94, green: 0.95, blue: 0.98), Color(uiColor: .systemBackground)]
                                        : [Color(red: 0.08, green: 0.08, blue: 0.12), Color.black],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }
                        }

                        // 3. Apple Music-style contrast scrim that ensures high legibility and rich deep tones
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: isLight
                                        ? [Color.white.opacity(0.40), Color.white.opacity(0.85)]
                                        : [Color.black.opacity(0.38), Color.black.opacity(0.82)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()

                case .gradient:
                    ZStack {
                        LinearGradient(
                            colors: isLight
                                ? [c0.opacity(0.14), c1.opacity(0.08), Color(uiColor: .systemBackground)]
                                : [c0.opacity(0.22), c1.opacity(0.14), Color(red: 0.05, green: 0.05, blue: 0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        if let artwork {
                            Image(uiImage: artwork)
                                .resizable()
                                .scaledToFill()
                                .frame(width: size.width, height: size.height)
                                .scaleEffect(1.25)
                                .blur(radius: 65)
                                .saturation(1.15)
                                .opacity(isLight ? 0.18 : 0.28)
                                .clipped()
                        }

                        Rectangle()
                            .fill(isLight ? Color.white.opacity(0.48) : Color.black.opacity(0.62))
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()

                case .moving:
                    if let motionURL {
                        MotionArtworkBackgroundView(motionURL: motionURL, artwork: artwork, paletteHexes: paletteHexes)
                    } else {
                        AnimatedArtworkBackground(artwork: artwork, paletteHexes: paletteHexes)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

private struct MotionArtworkBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    let motionURL: URL
    let artwork: UIImage?
    var paletteHexes: [String] = []

    private var paletteColors: [Color] {
        if paletteHexes.isEmpty {
            return [Color(hex: "#38BDF8"), Color(hex: "#818CF8")]
        }
        return paletteHexes.map { Color(hex: $0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let isLight = colorScheme == .light
            let c0 = paletteColors[0 % paletteColors.count]
            let c1 = paletteColors[1 % paletteColors.count]

            ZStack {
                // Ambient underlay
                LinearGradient(
                    colors: isLight
                        ? [c0.opacity(0.18), Color(uiColor: .systemBackground), c1.opacity(0.12)]
                        : [c0.opacity(0.24), Color(red: 0.05, green: 0.05, blue: 0.07), c1.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // High-vibrancy motion video with artwork underlay
                ZStack {
                    if let artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .scaleEffect(1.30)
                            .blur(radius: 55)
                            .saturation(1.15)
                            .contrast(1.02)
                            .opacity(isLight ? 0.38 : 0.52)
                            .clipped()
                    }

                    MotionArtworkPlayerView(streamURL: motionURL, placeholder: artwork)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(1.30)
                        .blur(radius: 55)
                        .saturation(1.15)
                        .contrast(1.02)
                        .opacity(isLight ? 0.38 : 0.52)
                        .clipped()
                }

                // Protective scrim
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: isLight
                                ? [Color.white.opacity(0.40), Color.white.opacity(0.85)]
                                : [Color.black.opacity(0.38), Color.black.opacity(0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }
}

private struct AnimatedArtworkBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let artwork: UIImage?
    var paletteHexes: [String] = []

    private var paletteColors: [Color] {
        if paletteHexes.isEmpty {
            return [
                Color(hex: "#38BDF8"),
                Color(hex: "#818CF8"),
                Color(hex: "#C084FC"),
                Color(hex: "#F472B6")
            ]
        }
        return paletteHexes.map { Color(hex: $0) }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { proxy in
                let size = proxy.size
                let time = context.date.timeIntervalSinceReferenceDate
                let isLight = colorScheme == .light
                let c0 = paletteColors[0 % paletteColors.count]
                let c1 = paletteColors[1 % paletteColors.count]
                let c2 = paletteColors[2 % paletteColors.count]
                let c3 = paletteColors[3 % paletteColors.count]

                ZStack {
                    // 1. Deep ambient gradient matching the album art colors
                    LinearGradient(
                        colors: isLight
                            ? [c0.opacity(0.18), Color(uiColor: .systemBackground), c1.opacity(0.12)]
                            : [c0.opacity(0.25), Color(red: 0.05, green: 0.05, blue: 0.07), c1.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // 2. Animated Fluid Artwork Layers: Moving the actual artwork!
                    if let artwork {
                        // Primary artwork drift & gentle breathing pulse
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .scaleEffect(1.32 + 0.05 * sin(time * 0.16))
                            .offset(
                                x: 20 * sin(time * 0.22),
                                y: 16 * cos(time * 0.18)
                            )
                            .rotationEffect(.degrees(3.0 * sin(time * 0.12)))
                            .blur(radius: 65)
                            .saturation(1.15)
                            .contrast(1.02)
                            .opacity(isLight ? 0.35 : 0.48)

                        // Secondary counter-moving artwork layer: rotated/offset to create liquid color mixing
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .scaleEffect(1.42 + 0.06 * cos(time * 0.14))
                            .offset(
                                x: -22 * cos(time * 0.20),
                                y: -18 * sin(time * 0.25)
                            )
                            .rotationEffect(.degrees(-4.0 * cos(time * 0.15) + 180))
                            .blur(radius: 75)
                            .saturation(1.15)
                            .contrast(1.02)
                            .opacity(isLight ? 0.14 : 0.22)
                            .blendMode(isLight ? .softLight : .screen)
                    }

                    // 3. Radiant Floating Color Blooms using the extracted album art palette
                    orb(
                        color: c0,
                        size: min(size.width, size.height) * 0.88,
                        x: size.width * (0.22 + 0.14 * sin(time * 0.26)),
                        y: size.height * (0.24 + 0.12 * cos(time * 0.20)),
                        isLight: isLight,
                        opacity: isLight ? 0.16 : 0.25
                    )

                    orb(
                        color: c1,
                        size: min(size.width, size.height) * 0.78,
                        x: size.width * (0.76 + 0.13 * cos(time * 0.22)),
                        y: size.height * (0.34 + 0.14 * sin(time * 0.28)),
                        isLight: isLight,
                        opacity: isLight ? 0.15 : 0.23
                    )

                    orb(
                        color: c2,
                        size: min(size.width, size.height) * 0.92,
                        x: size.width * (0.50 + 0.15 * sin(time * 0.18 + 1.2)),
                        y: size.height * (0.76 + 0.12 * cos(time * 0.24 + 0.7)),
                        isLight: isLight,
                        opacity: isLight ? 0.15 : 0.23
                    )

                    orb(
                        color: c3,
                        size: min(size.width, size.height) * 0.68,
                        x: size.width * (0.20 + 0.12 * cos(time * 0.30 + 2.0)),
                        y: size.height * (0.62 + 0.14 * sin(time * 0.19 + 1.5)),
                        isLight: isLight,
                        opacity: isLight ? 0.12 : 0.18
                    )

                    // 4. Subtle contrast scrim to ensure text and controls remain razor-sharp
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: isLight
                                    ? [Color.white.opacity(0.40), Color.white.opacity(0.85)]
                                    : [Color.black.opacity(0.38), Color.black.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .drawingGroup()
                .ignoresSafeArea()
            }
        }
    }

    private func orb(color: Color, size: CGFloat, x: CGFloat, y: CGFloat, isLight: Bool, opacity: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .position(x: x, y: y)
            .blur(radius: size * 0.28)
            .opacity(opacity)
            .blendMode(isLight ? .softLight : .screen)
    }
}
#endif


private struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var alignment: Alignment = .leading
    
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var startTime: TimeInterval = Date().timeIntervalSinceReferenceDate
    
    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = trimmed.isEmpty ? " " : text
        let isOverflowing = containerWidth > 0 && textWidth > containerWidth + 2
        let scrollDistance = max(0, textWidth - containerWidth)
        
        ZStack(alignment: isOverflowing ? .leading : alignment) {
            // Base view: Visible initially and whenever not overflowing
            Text(displayText)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment)
                .opacity(isOverflowing ? 0 : 1)
                .background(
                    // Invisible unconstrained text measuring exact natural text width
                    Text(displayText)
                        .font(font)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .hidden()
                        .background(
                            GeometryReader { textGeo in
                                Color.clear
                                    .onAppear {
                                        if textGeo.size.width > 0 {
                                            updateTextWidth(textGeo.size.width)
                                        }
                                    }
                                    .onChange(of: textGeo.size.width) { _, newWidth in
                                        if newWidth > 0 {
                                            updateTextWidth(newWidth)
                                        }
                                    }
                            }
                        )
                        .id(displayText)
                )

            if isOverflowing {
                TimelineView(.animation) { timelineContext in
                    let offset = calculateOffset(
                        currentTime: timelineContext.date.timeIntervalSinceReferenceDate,
                        scrollDistance: scrollDistance,
                        isOverflowing: true
                    )
                    
                    let isLeadingFaded = -offset > 4
                    let isTrailingFaded = -offset < (scrollDistance - 4)
                    
                    Text(displayText)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: offset)
                        .frame(width: containerWidth, alignment: .leading)
                        .clipped()
                        .mask(
                            HStack(spacing: 0) {
                                if isLeadingFaded {
                                    LinearGradient(
                                        colors: [.clear, .black],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: 14)
                                }
                                
                                Rectangle()
                                    .fill(Color.black)
                                
                                if isTrailingFaded {
                                    LinearGradient(
                                        colors: [.black, .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: 14)
                                }
                            }
                            .frame(width: containerWidth)
                        )
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        if geo.size.width > 0 {
                            updateContainerWidth(geo.size.width)
                        }
                    }
                    .onChange(of: geo.size.width) { _, newWidth in
                        if newWidth > 0 {
                            updateContainerWidth(newWidth)
                        }
                    }
            }
        )
        .clipped()
        .onChange(of: text) { _, _ in
            resetStartTime()
        }
        .onAppear {
            resetStartTime()
        }
    }
    
    private func resetStartTime() {
        startTime = Date().timeIntervalSinceReferenceDate
    }
    
    private func updateContainerWidth(_ width: CGFloat) {
        if abs(containerWidth - width) > 0.5 {
            containerWidth = width
        }
    }
    
    private func updateTextWidth(_ width: CGFloat) {
        if abs(textWidth - width) > 0.5 {
            textWidth = width
        }
    }
    
    private func calculateOffset(currentTime: TimeInterval, scrollDistance: CGFloat, isOverflowing: Bool) -> CGFloat {
        guard isOverflowing, scrollDistance > 0 else { return 0 }
        
        let speed: Double = 28.0
        let scrollDuration = Double(scrollDistance) / speed
        let pauseDuration: Double = 2.0
        let singlePassDuration = pauseDuration + scrollDuration
        let totalCycleDuration = singlePassDuration * 2.0
        
        let rawElapsed = currentTime - startTime
        guard rawElapsed >= 0 else { return 0 }
        
        let elapsed = rawElapsed.truncatingRemainder(dividingBy: totalCycleDuration)
        
        if elapsed < pauseDuration {
            return 0
        } else if elapsed < singlePassDuration {
            let progress = (elapsed - pauseDuration) / scrollDuration
            let easedProgress = (1.0 - cos(progress * .pi)) / 2.0
            return -scrollDistance * CGFloat(easedProgress)
        } else if elapsed < singlePassDuration + pauseDuration {
            return -scrollDistance
        } else {
            let progress = (elapsed - (singlePassDuration + pauseDuration)) / scrollDuration
            let easedProgress = (1.0 - cos(progress * .pi)) / 2.0
            return -scrollDistance * CGFloat(1.0 - easedProgress)
        }
    }
}


// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var spicyLyricsKey: String = APIConfig.spicyLyricsApiKey
    @State private var spotifyClientId: String = APIConfig.spotifyClientId
    @State private var spotifyClientSecret: String = APIConfig.spotifyClientSecret
    @State private var isSavedAlertPresented: Bool = false
    @State private var isShowingSpicyConnectSheet: Bool = false

    var body: some View {
        Form {
            Section(
                header: Text("Spotify Connection"),
                footer: Text("Playback stays on the device you were listening to when unpausing.")
            ) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account Status")
                            .font(.system(size: isMac ? 17 : 15, weight: .semibold))
                        if viewModel.spotifyService.sessionNeedsReauth {
                            Text("Session Expired — Reconnect Required")
                                .font(.system(size: isMac ? 15 : 13, weight: .medium))
                                .foregroundStyle(.orange)
                        } else if viewModel.spotifyService.isRateLimited {
                            Text("Rate limited (resuming in \(formatRemainingSeconds(viewModel.spotifyService.rateLimitRetryAfter)))")
                                .font(.system(size: isMac ? 15 : 13, weight: .medium))
                                .foregroundStyle(.yellow)
                        } else {
                            Text(viewModel.spotifyService.isAuthenticated ? "Connected" : "Not Connected")
                                .font(.system(size: isMac ? 15 : 13))
                                .foregroundStyle(viewModel.spotifyService.isAuthenticated ? Color(red: 0.11, green: 0.85, blue: 0.45) : .secondary)
                        }
                    }

                    Spacer()

                    if viewModel.spotifyService.sessionNeedsReauth {
                        Button("Reconnect") {
                            applySpotifyConfig()
                            viewModel.spotifyService.login()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else if viewModel.spotifyService.isAuthenticated {
                        Button("Disconnect", role: .destructive) {
                            viewModel.spotifyService.logout()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Connect") {
                            applySpotifyConfig()
                            viewModel.spotifyService.login()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.11, green: 0.73, blue: 0.33))
                    }
                }

                if viewModel.spotifyService.isAuthenticated && !viewModel.spotifyService.availableDevices.isEmpty {
                    Menu {
                        ForEach(viewModel.spotifyService.availableDevices) { device in
                            Button {
                                if let devId = device.id {
                                    Task {
                                        await viewModel.spotifyService.transferPlayback(to: devId)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(device.name)
                                    if device.name == viewModel.spotifyService.activeDeviceName || (device.id != nil && device.id == viewModel.spotifyService.lastActiveDeviceId) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Label("Device", systemImage: "speaker.wave.2")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(viewModel.spotifyService.activeDeviceName ?? "Active Device")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(
                header: Text("Spicy Lyrics Connection"),
                footer: Text("Connect your Spicy Lyrics Client Key for real-time syllable-level sync and contributor credits.")
            ) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Status")
                            .font(.system(size: isMac ? 17 : 15, weight: .semibold))
                        Text(viewModel.isSpicyLyricsConnected ? "Connected" : "Not Connected")
                            .font(.system(size: isMac ? 15 : 13))
                            .foregroundStyle(viewModel.isSpicyLyricsConnected ? Color(red: 1.0, green: 0.5, blue: 0.1) : .secondary)
                    }

                    Spacer()

                    Button(viewModel.isSpicyLyricsConnected ? "Manage" : "Connect") {
                        isShowingSpicyConnectSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 1.0, green: 0.45, blue: 0.1))
                }
            }

            Section("Appearance") {
                Picker("Background", selection: $viewModel.backgroundStyle) {
                    ForEach(PlayerBackgroundStyle.allCases) { style in
                        Text(style.displayName(for: colorScheme)).tag(style)
                    }
                }
                .pickerStyle(.menu)

                Picker("Font Style", selection: $viewModel.lyricsFontDesign) {
                    ForEach(LyricsFontDesign.allCases) { design in
                        Text(design.rawValue).tag(design)
                    }
                }
                .pickerStyle(.menu)

                Picker("Text Size", selection: $viewModel.lyricsFontSize) {
                    ForEach(LyricsFontSize.allCases) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Active Lyric Glow", isOn: $viewModel.isLyricsGlowEnabled)
                    .tint(Color(red: 0.11, green: 0.73, blue: 0.33))

                Toggle("Lyric Bounce", isOn: $viewModel.isLyricsBounceEnabled)
                    .tint(Color(red: 0.11, green: 0.73, blue: 0.33))

                Toggle("Motion Album Artwork", isOn: $viewModel.isMotionArtworkEnabled)
                    .tint(Color(red: 0.11, green: 0.73, blue: 0.33))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Lyric Color")
                        Spacer()
                        if viewModel.isArtworkColorMode {
                            HStack(spacing: 4) {
                                Image(systemName: "paintpalette.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Album Art")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(viewModel.artworkColor(for: colorScheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.10)))
                        } else if viewModel.isRainbowColorMode {
                            Text("Rainbow")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: LyricColorPreset.rainbowColors,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.10)))
                        }
                        HexColorPicker(
                            hex: Binding(
                                get: {
                                    if viewModel.isRainbowColorMode {
                                        return "#FF4B72"
                                    } else if viewModel.isArtworkColorMode {
                                        return viewModel.artworkHex(for: colorScheme)
                                    }
                                    return viewModel.effectiveLyricsColorHex(for: colorScheme)
                                },
                                set: { viewModel.lyricsColorHex = $0 }
                            ),
                            fallbackHex: colorScheme == .light ? "#000000" : "#FFFFFF"
                        )
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(LyricColorPreset.presets(for: colorScheme)) { preset in
                                let isSelected: Bool = {
                                    if preset.isRainbow {
                                        return viewModel.isRainbowColorMode
                                    }
                                    if preset.isArtwork {
                                        return viewModel.isArtworkColorMode
                                    }
                                    return viewModel.effectiveLyricsColorHex(for: colorScheme).uppercased() == preset.hex.uppercased()
                                }()
                                Button {
                                    viewModel.lyricsColorHex = preset.hex
                                } label: {
                                    presetColorCircle(preset: preset, isSelected: isSelected)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                }

                Toggle("Distinct Colors for Main & Duet", isOn: $viewModel.isMultiVoiceColorsEnabled)
                    .tint(Color(red: 0.11, green: 0.73, blue: 0.33))

                Toggle("Colorize Color Words", isOn: $viewModel.isExactColorEnabled)
                    .tint(Color(red: 0.11, green: 0.73, blue: 0.33))

                if viewModel.isExactColorEnabled {
                    Text("When sung, color words (such as 'red', 'blue', 'green', 'gold') are displayed in their exact named color.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }

                Toggle("Special Word Effects", isOn: $viewModel.isSpecialWordEffectsEnabled)
                    .tint(Color(red: 0.11, green: 0.73, blue: 0.33))

                if viewModel.isSpecialWordEffectsEnabled {
                    Text("Words like 'fire', 'cold', 'summer', 'diamond', 'christmas', 'night', and 'sun' feature dynamic visual styling while singing.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }

                Toggle("Bleep N-Word (****)", isOn: $viewModel.isBleepNWordEnabled)
                    .tint(Color(red: 0.11, green: 0.73, blue: 0.33))

                if viewModel.isBleepNWordEnabled {
                    Text("Replaces occurrences of the n-word in lyrics with 4 stars (****).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }

                if viewModel.isRainbowColorMode {
                    Text("Rainbow preset is active. Each lyric line cycles through a different rainbow color.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } else if viewModel.isArtworkColorMode {
                    Text("Album Art preset is active. Lyric color automatically matches each song's album artwork (and duet uses the secondary artwork tone).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }

                if viewModel.isMultiVoiceColorsEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("VOICE COLORS")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(1.0)

                        voiceColorRow(voiceKey: "v1", voiceLabel: "Main Vocals")
                        voiceColorRow(voiceKey: "v2", voiceLabel: "Duet Vocals")

                        Button("Reset Voice Colors") {
                            viewModel.resetVoiceColorsToDefaults()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("PREVIEW")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(1.0)

                    VStack(alignment: .leading, spacing: 16) {
                        let v1Color = viewModel.colorForLine(index: 0, agent: "v1", colorScheme: colorScheme)
                        let v2Color = viewModel.colorForLine(index: 1, agent: "v2", oppositeAligned: true, colorScheme: colorScheme)

                        // Main Vocals (Leading aligned)
                        VStack(alignment: .leading, spacing: 5) {
                            if viewModel.isMultiVoiceColorsEnabled {
                                Text("Main")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(v1Color.opacity(0.90))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(v1Color.opacity(0.20)))
                            }

                            Text("Cause I'm in a field of dandelions")
                                .font(.system(size: viewModel.lyricsFontSize.leadSize, weight: .heavy, design: viewModel.lyricsFontDesign.fontDesign))
                                .tracking(-0.5)
                                .foregroundStyle(v1Color)
                                .shadow(
                                    color: viewModel.isLyricsGlowEnabled ? v1Color.opacity(0.85) : Color.clear,
                                    radius: viewModel.isLyricsGlowEnabled ? 8 : 0,
                                    x: 0,
                                    y: 0
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 8)

                        // Duet Vocals (Opposite / Trailing aligned)
                        VStack(alignment: .trailing, spacing: 5) {
                            if viewModel.isMultiVoiceColorsEnabled {
                                Text("Duet")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(v2Color.opacity(0.90))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(v2Color.opacity(0.20)))
                            }

                            Text("Wishing on every one that you'd be mine")
                                .font(.system(size: viewModel.lyricsFontSize.leadSize, weight: .heavy, design: viewModel.lyricsFontDesign.fontDesign))
                                .tracking(-0.5)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(v2Color)
                                .shadow(
                                    color: viewModel.isLyricsGlowEnabled ? v2Color.opacity(0.85) : Color.clear,
                                    radius: viewModel.isLyricsGlowEnabled ? 8 : 0,
                                    x: 0,
                                    y: 0
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(colorScheme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
                .padding(.vertical, 4)
            }

            Section("API Configuration") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spicy Lyrics API Key")
                        .font(.system(size: isMac ? 15 : 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    SecureField("Paste your Client Key (sl_pk_...)", text: $spicyLyricsKey)
                        .font(.system(size: isMac ? 14 : 13, design: .monospaced))
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add Liquid Player in the Spicy Lyrics catalog to get your personal Client Key. None of it uses your application slots:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let catalogUrl = URL(string: APIConfig.spicyLyricsCatalogUrl) {
                            Link(destination: catalogUrl) {
                                HStack(spacing: 4) {
                                    Text("Open Catalog Page (developers.spicylyrics.org)")
                                        .fontWeight(.semibold)
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.system(size: 12))
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Spotify Client ID")
                        .font(.system(size: isMac ? 15 : 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Spotify Client ID", text: $spotifyClientId)
                        .font(.system(size: isMac ? 14 : 13, design: .monospaced))
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Spotify Client Secret (Optional)")
                        .font(.system(size: isMac ? 15 : 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    SecureField("Optional (Not needed for PKCE)", text: $spotifyClientSecret)
                        .font(.system(size: isMac ? 14 : 13, design: .monospaced))
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }

                Button("Save Configuration") {
                    let oldClientId = APIConfig.spotifyClientId
                    viewModel.saveSpicyLyricsApiKey(spicyLyricsKey)
                    applySpotifyConfig()
                    if oldClientId != APIConfig.spotifyClientId {
                        // Client ID changed! Reconnect with new Client ID
                        viewModel.spotifyService.login()
                    }
                    isSavedAlertPresented = true
                }
                .font(.system(size: isMac ? 16 : 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.11, green: 0.85, blue: 0.45))

                Button("Reset to Defaults") {
                    viewModel.disconnectSpicyLyrics()
                    APIConfig.resetToDefaults()
                    spicyLyricsKey = APIConfig.spicyLyricsApiKey
                    spotifyClientId = APIConfig.spotifyClientId
                    spotifyClientSecret = APIConfig.spotifyClientSecret
                    viewModel.spotifyService.disconnect()
                    isSavedAlertPresented = true
                }
                .font(.system(size: isMac ? 15 : 13))
                .foregroundStyle(.secondary)
            }

            Section("About Liquid Player") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.1.5") (Beta)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("OAuth Callback")
                    Spacer()
                    Text(APIConfig.spotifyRedirectUri)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .sheet(isPresented: $isShowingSpicyConnectSheet) {
            SpicyLyricsConnectSheet(viewModel: viewModel)
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Settings Saved", isPresented: $isSavedAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your API configuration has been safely updated.")
        }
    }

    private func applySpotifyConfig() {
        let trimmedClientId = spotifyClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClientSecret = spotifyClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = (APIConfig.spotifyClientId != trimmedClientId)
        APIConfig.spotifyClientId = trimmedClientId
        APIConfig.spotifyClientSecret = trimmedClientSecret
        spotifyClientId = APIConfig.spotifyClientId
        spotifyClientSecret = APIConfig.spotifyClientSecret
        if changed {
            viewModel.spotifyService.disconnect()
        }
    }

    private func presetColorCircle(preset: LyricColorPreset, isSelected: Bool) -> some View {
        let isLight = (colorScheme == .light)
        let strokeColor: Color = isSelected
            ? (isLight ? Color.black : Color.white)
            : (isLight ? Color.black.opacity(0.18) : Color.white.opacity(0.20))
        let strokeWidth: CGFloat = isSelected ? 3.0 : 1.0

        let shadowColor: Color
        if isSelected {
            if preset.isRainbow {
                shadowColor = Color.purple.opacity(0.8)
            } else if preset.isArtwork {
                shadowColor = viewModel.artworkColor(for: colorScheme).opacity(0.7)
            } else {
                shadowColor = preset.color.opacity(0.6)
            }
        } else {
            shadowColor = Color.clear
        }

        return ZStack {
            if preset.isRainbow {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: LyricColorPreset.rainbowColors + [LyricColorPreset.rainbowColors[0]],
                            center: .center
                        )
                    )
            } else if preset.isArtwork {
                Circle()
                    .fill(viewModel.artworkColor(for: colorScheme))
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(viewModel.isArtworkColorBright(for: colorScheme) ? Color.black.opacity(0.80) : Color.white.opacity(0.90))
            } else {
                Circle()
                    .fill(preset.color)
            }
        }
        .frame(width: 28, height: 28)
        .overlay(
            Circle()
                .stroke(strokeColor, lineWidth: strokeWidth)
        )
        .shadow(color: shadowColor, radius: 4)
    }

    private func voiceColorRow(voiceKey: String, voiceLabel: String) -> some View {
        let currentColor = viewModel.colorForVoice(voiceKey, colorScheme: colorScheme)
        let defaultHex: String = {
            if voiceKey == "v1" {
                if viewModel.isArtworkColorMode {
                    return viewModel.artworkHex(for: colorScheme)
                }
                return colorScheme == .light ? "#000000" : "#FFFFFF"
            }
            if viewModel.isArtworkColorMode {
                return viewModel.artworkDuetHex(for: colorScheme)
            }
            return "#38BDF8"
        }()
        return HStack {
            Circle()
                .fill(currentColor)
                .frame(width: 14, height: 14)
            Text(voiceLabel)
                .font(.system(size: 14))
            Spacer()
            HexColorPicker(
                hex: Binding(
                    get: {
                        if voiceKey == "v1" && viewModel.isArtworkColorMode {
                            return viewModel.artworkHex(for: colorScheme)
                        }
                        if voiceKey == "v2" && viewModel.isArtworkColorMode {
                            return viewModel.artworkDuetHex(for: colorScheme)
                        }
                        return LyricColorPreset.resolveAdaptiveHex(viewModel.voiceColors[voiceKey] ?? defaultHex, for: colorScheme)
                    },
                    set: { newHex in
                        viewModel.setVoiceColor(newHex, for: voiceKey)
                    }
                ),
                fallbackHex: defaultHex
            )
        }
    }
}

typealias SettingsSheet = SettingsView

private struct MiniPlayerBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.primary.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }
    }
}

private struct LiquidScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct MiniPlayerButtonBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: Circle())
        } else {
            content
                .background(.thinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .fill(Color.primary.opacity(0.02))
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
    }
}

private struct MiniPlayerCapsuleButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: Capsule())
        } else {
            content
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .fill(Color.primary.opacity(0.02))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
    }
}

private struct LibraryFilterContainerGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )
                .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
        }
    }
}

private struct LibraryFilterActiveTabGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.primary.opacity(0.25), Color.primary.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)
        }
    }
}

struct QueueView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .light ? Color(uiColor: .systemGroupedBackground) : Color.black).ignoresSafeArea()

                VStack(spacing: 0) {
                    if viewModel.playbackQueue.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: isMacPlatform ? 56 : 48))
                                .foregroundStyle(.secondary)
                            Text("Queue is Empty")
                                .font(.system(size: isMacPlatform ? 20 : 17, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Search songs on Spotify or play from library to populate upcoming tracks.")
                                .font(.system(size: isMacPlatform ? 15 : 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(viewModel.playbackQueue) { track in
                                HStack(spacing: 12) {
                                    SpotifyArtworkView(url: track.artworkURL, size: isMacPlatform ? 48 : 40, cornerRadius: 8)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.name)
                                            .font(.system(size: isMacPlatform ? 17 : 15, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)

                                        Text(track.artistNames)
                                            .font(.system(size: isMacPlatform ? 14 : 12, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .contentShape(.dragPreview, Rectangle())
                                .listRowBackground(colorScheme == .light ? Color(uiColor: .secondarySystemGroupedBackground) : Color.white.opacity(0.06))
                                .listRowSeparator(.visible)
                                .listRowSeparatorTint(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.08))
                            }
                            .onDelete(perform: viewModel.removeTrackFromQueue(at:))
                            .onMove(perform: viewModel.moveTrackInQueue(from:to:))
                        }
                        .listStyle(.plain)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .environment(\.editMode, .constant(.active))
                    }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.playbackQueue.isEmpty {
                        Button("Clear") {
                            viewModel.clearQueue()
                        }
                        .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                }
            }
            .task {
                await viewModel.prefetchUpcomingLyrics()
            }
        }
    }
}

// MARK: - Library Song Row & TTML Sheet Components

struct LibrarySongRowView: View {
    let song: LibrarySong
    let isCurrent: Bool
    let isUpdating: Bool
    let onPlay: () -> Void
    let onUpdateTTML: () -> Void
    let onViewTTML: () -> Void
    var onUploadTTML: (() -> Void)? = nil
    var onDeleteTTML: (() -> Void)? = nil

    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            ZStack {
                SpotifyArtworkView(url: song.artworkUrl.flatMap(URL.init), size: isMacPlatform ? 56 : 48, cornerRadius: 6)

                if isCurrent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: isMacPlatform ? 16 : 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                }
            }
            .frame(width: isMacPlatform ? 56 : 48, height: isMacPlatform ? 56 : 48)

            // Song Info & Metadata (Apple Music Style)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.name)
                    .font(.system(size: isMacPlatform ? 17 : 15, weight: .medium))
                    .foregroundStyle(isCurrent ? Color(red: 0.11, green: 0.73, blue: 0.33) : .primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(song.artistNames)
                        .lineLimit(1)

                    if song.needsUpdate {
                        Text("•")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: isMacPlatform ? 12 : 10))
                            Text("Update Needed")
                        }
                        .foregroundStyle(Color.orange)
                    } else if song.hasTTML {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("TTML")
                            .foregroundStyle(.secondary)
                    } else if song.isInstrumentalOrNoLyrics {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("No Lyrics")
                            .foregroundStyle(.secondary)
                    }

                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(song.playedAgoDescription)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: isMacPlatform ? 15 : 13))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // Apple standard 3-dot action menu
            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
                    .frame(width: 32, height: 32)
            } else {
                Menu {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                    }

                    if song.hasTTML {
                        Button(action: onViewTTML) {
                            Label("View TTML Lyrics", systemImage: "quote.bubble")
                        }
                    }

                    if onUploadTTML != nil {
                        Button(action: { onUploadTTML?() }) {
                            Label("Upload TTML File", systemImage: "arrow.up.doc")
                        }
                    }

                    Button(action: onUpdateTTML) {
                        Label(song.needsUpdate ? "Update TTML Lyrics" : "Refresh Lyrics", systemImage: "arrow.triangle.2.circlepath")
                    }

                    if song.hasTTML && onDeleteTTML != nil {
                        Divider()
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete Saved TTML", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay()
        }
        .contextMenu {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
            }

            if song.hasTTML {
                Button(action: onViewTTML) {
                    Label("View TTML Lyrics", systemImage: "quote.bubble")
                }
            }

            if onUploadTTML != nil {
                Button(action: { onUploadTTML?() }) {
                    Label("Upload TTML File", systemImage: "arrow.up.doc")
                }
            }

            Button(action: onUpdateTTML) {
                Label(song.needsUpdate ? "Update TTML Lyrics" : "Refresh Lyrics", systemImage: "arrow.triangle.2.circlepath")
            }

            if song.hasTTML && onDeleteTTML != nil {
                Divider()
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete Saved TTML", systemImage: "trash")
                }
            }
        }
        .alert("Delete Saved TTML?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                onDeleteTTML?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete the saved TTML for \"\(song.name)\"? This will remove the cached lyrics file from your device.")
        }
    }
}

struct TTMLViewerSheet: View {
    let song: LibrarySong
    var onUpload: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var showingDeleteAlert = false

    private var effectiveTTML: String? {
        LibraryManager.shared.getValidSavedTTML(for: song.id) ?? song.ttmlContent
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // Track metadata header
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.name)
                        .font(.system(size: isMacPlatform ? 20 : 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(song.artistNames)
                        .font(.system(size: isMacPlatform ? 16 : 14))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(song.isTTMLExpired ? "⚠️ Saved over 30 days ago (Update needed)" : "✓ Saved TTML (\(song.daysUntilTTMLExpires) days remaining)")
                            .font(.system(size: isMacPlatform ? 14 : 12, weight: .semibold))
                            .foregroundStyle(song.isTTMLExpired ? .orange : .green)

                        if let date = song.ttmlSavedAt {
                            Text("• Saved \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: isMacPlatform ? 13 : 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Divider()
                    .overlay(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.12))

                // TTML XML Content
                ScrollView {
                    Text(effectiveTTML ?? "No TTML saved for this song.")
                        .font(.system(size: isMacPlatform ? 14 : 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(colorScheme == .light ? Color(uiColor: .tertiarySystemGroupedBackground) : Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background((colorScheme == .light ? Color(uiColor: .systemGroupedBackground) : Color(red: 0.08, green: 0.08, blue: 0.10)).ignoresSafeArea())
            .navigationTitle("Saved TTML")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 14) {
                        if let onUpload = onUpload {
                            Button {
                                onUpload()
                            } label: {
                                Image(systemName: "arrow.up.doc")
                                    .font(.system(size: isMacPlatform ? 15 : 13, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                            .help("Upload / Replace TTML")
                        }

                        if onDelete != nil {
                            Button(role: .destructive) {
                                showingDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: isMacPlatform ? 15 : 13, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                            .help("Delete Saved TTML")
                        }

                        if let content = effectiveTTML, !content.isEmpty {
                            Button {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = content
                                #elseif canImport(AppKit)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(content, forType: .string)
                                #endif
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copied = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    Text(copied ? "Copied" : "Copy TTML")
                                }
                                .font(.system(size: isMacPlatform ? 16 : 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .alert("Delete Saved TTML?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete the saved TTML for \"\(song.name)\"? This will remove the cached lyrics file from your device.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Stable Hex Color Picker
struct HexColorPicker: View {
    @Binding var hex: String
    var fallbackHex: String = "#FFFFFF"

    @State private var currentColor: Color = .white
    @State private var lastReportedHex: String = ""

    var body: some View {
        ColorPicker(
            "",
            selection: Binding(
                get: { currentColor },
                set: { newColor in
                    currentColor = newColor
                    let newHex = newColor.toHex()
                    if newHex.uppercased() != lastReportedHex.uppercased() {
                        lastReportedHex = newHex
                        hex = newHex
                    }
                }
            ),
            supportsOpacity: false
        )
        .labelsHidden()
        .onAppear {
            syncFromHex()
        }
        .onChange(of: hex) { _, newHex in
            if newHex.uppercased() != lastReportedHex.uppercased() {
                syncFromHex()
            }
        }
    }

    private func syncFromHex() {
        let clean = hex.isEmpty ? fallbackHex : hex
        let parsed = Color(hex: clean)
        currentColor = parsed
        lastReportedHex = parsed.toHex()
    }
}

// MARK: - Dedicated High-Frequency Views (Prevents parent TabView / ContentView redraw thrashing)

private struct TimelineSeekBarView: View {
    @ObservedObject var timeKeeper: PlaybackTimeKeeper
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.colorScheme) private var colorScheme
    var isCompactHorizontal: Bool = false
    @State private var isDraggingSlider = false
    @State private var dragValue: Double = 0.0

    private var current: Double {
        Double(timeKeeper.currentTimeMs)
    }

    var body: some View {
        let duration = Double(viewModel.durationMs)
        let progress = duration > 0 ? current / duration : 0.0

        if isCompactHorizontal {
            HStack(spacing: 8) {
                Text(timecode(Int(isDraggingSlider ? dragValue : current)))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                sliderTrack(duration: duration, progress: progress, height: 6)

                Text(timecode(viewModel.durationMs))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .disabled(viewModel.durationMs == 0)
        } else {
            VStack(spacing: 6) {
                sliderTrack(duration: duration, progress: progress, height: isMac ? 10 : 8)

                HStack {
                    Text(timecode(Int(isDraggingSlider ? dragValue : current)))
                        .font(.system(size: isMac ? 15 : 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(timecode(viewModel.durationMs))
                        .font(.system(size: isMac ? 15 : 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(viewModel.durationMs == 0)
        }
    }

    private func sliderTrack(duration: Double, progress: Double, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let progressWidth = isDraggingSlider
                ? max(0, min(dragValue / max(duration, 1) * trackWidth, trackWidth))
                : max(0, min(progress * trackWidth, trackWidth))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.18))
                    .frame(height: height)

                Capsule()
                    .fill(Color.primary)
                    .frame(width: progressWidth, height: height)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDraggingSlider = true
                        let locationX = gesture.location.x
                        let percentage = max(0, min(locationX / trackWidth, 1.0))
                        dragValue = percentage * max(duration, 1)
                    }
                    .onEnded { gesture in
                        let locationX = gesture.location.x
                        let percentage = max(0, min(locationX / trackWidth, 1.0))
                        let targetTime = percentage * max(duration, 1)
                        viewModel.seek(to: Int(targetTime))

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isDraggingSlider = false
                        }
                    }
            )
        }
        .frame(height: isMac ? 14 : 12)
    }
}

private struct LyricsPanelView: View {
    @ObservedObject var timeKeeper: PlaybackTimeKeeper
    @ObservedObject var viewModel: PlayerViewModel
    let isFullScreen: Bool
    let isFullScreenControlsHidden: Bool
    let isFullScreenNowPlaying: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var isUserScrollingLyrics = false
    @State private var userScrollResumeTask: Task<Void, Never>? = nil
    @State private var isShowingSpicyConnect = false

    private var lyricLines: [LyricLine] {
        viewModel.lines.filter { !$0.isSongwriter }
    }

    private var displayedTimeMs: Int {
        return max(0, timeKeeper.currentTimeMs + viewModel.lyricOffsetMs)
    }

    private var hasRomanization: Bool {
        viewModel.lines.contains { $0.romanization != nil }
    }

    private var hasTranslations: Bool {
        viewModel.lines.contains { $0.translation != nil }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                if !(isFullScreen && isFullScreenControlsHidden) {
                    HStack(spacing: 8) {
                        if hasRomanization {
                            Toggle(isOn: $viewModel.isRomanizationEnabled) {
                                Text("Romaji")
                                    .font(.system(size: isMac ? 15 : 13, weight: .semibold))
                            }
                            .toggleStyle(.button)
                            .tint(colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.18))
                        }

                        if hasTranslations {
                            Toggle(isOn: $viewModel.isTranslationEnabled) {
                                Text("Translation")
                                    .font(.system(size: isMac ? 15 : 13, weight: .semibold))
                            }
                            .toggleStyle(.button)
                            .tint(colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.18))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

                ScrollView(showsIndicators: false) {
                    let activeID = viewModel.activeLineID(for: displayedTimeMs)
                    let activeIndex = lyricLines.firstIndex { $0.id == activeID } ?? -1

                    VStack(spacing: 0) {
                        if viewModel.isLoadingLyrics {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(.primary)
                                Text("Fetching lyrics from Spicy Lyrics...")
                                    .font(.system(size: isMac ? 17 : 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                        } else if viewModel.lines.isEmpty {
                            Spacer(minLength: 0)
                        } else {
                            ForEach(Array(lyricLines.enumerated()), id: \.element.id) { index, line in
                                lyricLineRow(
                                    line: line,
                                    index: index,
                                    activeID: activeID,
                                    activeIndex: activeIndex
                                )
                            }

                            SpicyLyricsAttributionFooterView(
                                source: viewModel.lyricsSource,
                                attribution: viewModel.lyricsAttribution,
                                songwriters: viewModel.lyricsSongwriters,
                                onManageConnection: {
                                    isShowingSpicyConnect = true
                                }
                            )
                            .padding(.top, 36)
                            .padding(.bottom, 64)
                        }
                    }
                    .padding(.top, isFullScreen ? 64 : 52)
                    .padding(.bottom, 36)
                    .animation(viewModel.isPlaying ? .spring(response: 0.52, dampingFraction: 0.88) : nil, value: activeID)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in
                            isUserScrollingLyrics = true
                            userScrollResumeTask?.cancel()
                            userScrollResumeTask = Task {
                                try? await Task.sleep(nanoseconds: 4_500_000_000)
                                if !Task.isCancelled {
                                    await MainActor.run {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                            isUserScrollingLyrics = false
                                        }
                                    }
                                }
                            }
                        }
                )
                .scrollClipDisabled()
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.025),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Group {
                    if !isFullScreen || isMac {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(colorScheme == .light ? Color.black.opacity(0.03) : Color.white.opacity(0.08))
                    }
                }
            )
            .overlay(
                Group {
                    if !isFullScreen || isMac {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
            )
            .overlay(alignment: .bottom) {
                if isUserScrollingLyrics && !viewModel.isCurrentSongUnsynced, let activeID = viewModel.activeLineID(for: displayedTimeMs) {
                    Button {
                        userScrollResumeTask?.cancel()
                        withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                            isUserScrollingLyrics = false
                            proxy.scrollTo(activeID, anchor: lyricsScrollAnchor(for: activeID))
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: isMac ? 15 : 13, weight: .bold))
                            Text("Center")
                                .font(.system(size: isMac ? 14 : 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: Color.black.opacity(colorScheme == .light ? 0.12 : 0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 12)
                }
            }
            .onChange(of: viewModel.activeLineID(for: displayedTimeMs), initial: false) { _, activeID in
                guard let activeID = activeID else {
                    return
                }

                if !isUserScrollingLyrics && viewModel.isPlaying {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                        proxy.scrollTo(activeID, anchor: lyricsScrollAnchor(for: activeID))
                    }
                }
            }
            .onChange(of: viewModel.currentTrackId) { _, _ in
                isUserScrollingLyrics = false
                userScrollResumeTask?.cancel()
                Task { @MainActor in
                    if let targetID = viewModel.activeLineID(for: displayedTimeMs) ?? viewModel.lines.first?.id {
                        proxy.scrollTo(targetID, anchor: lyricsScrollAnchor(for: targetID))
                    }
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    if let targetID = viewModel.activeLineID(for: displayedTimeMs) ?? viewModel.lines.first?.id {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            proxy.scrollTo(targetID, anchor: lyricsScrollAnchor(for: targetID))
                        }
                    }
                }
            }
            .onChange(of: viewModel.lines.map(\.id)) { _, newIds in
                isUserScrollingLyrics = false
                guard !newIds.isEmpty else { return }
                Task { @MainActor in
                    if let targetID = viewModel.activeLineID(for: displayedTimeMs) ?? newIds.first {
                        proxy.scrollTo(targetID, anchor: lyricsScrollAnchor(for: targetID))
                    }
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    if let targetID = viewModel.activeLineID(for: displayedTimeMs) ?? newIds.first {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            proxy.scrollTo(targetID, anchor: lyricsScrollAnchor(for: targetID))
                        }
                    }
                }
            }
            .onAppear {
                isUserScrollingLyrics = false
                Task { @MainActor in
                    if let activeID = viewModel.activeLineID(for: displayedTimeMs) ?? viewModel.lines.first?.id {
                        proxy.scrollTo(activeID, anchor: lyricsScrollAnchor(for: activeID))
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSpicyConnect) {
            SpicyLyricsConnectSheet(viewModel: viewModel)
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func lyricsScrollAnchor(for lineID: UUID?) -> UnitPoint {
        guard let lineID = lineID else { return .center }
        let visibleLines = viewModel.lines.filter { !$0.isSongwriter }
        guard let index = visibleLines.firstIndex(where: { $0.id == lineID }) else {
            return .center
        }
        if index == 0 {
            return UnitPoint(x: 0.5, y: isFullScreenNowPlaying ? 0.28 : 0.24)
        } else if index == 1 {
            return UnitPoint(x: 0.5, y: isFullScreenNowPlaying ? 0.32 : 0.36)
        } else {
            return .center
        }
    }

    @ViewBuilder
    private func lyricLineRow(
        line: LyricLine,
        index: Int,
        activeID: UUID?,
        activeIndex: Int
    ) -> some View {
        let effectiveEnd: Int = max(line.endMs, line.words.last?.endMs ?? line.startMs)
        let isTimeActive: Bool = (line.startMs <= displayedTimeMs && displayedTimeMs <= effectiveEnd)
        let isPast: Bool = (displayedTimeMs > effectiveEnd)
        let isActive: Bool = isTimeActive || (line.id == activeID && !isPast)
        let distance: Int = activeIndex >= 0 ? (index - activeIndex) : 0
        let lineTimeMs: Int = (isActive || line.isInterlude) ? displayedTimeMs : (isPast ? line.endMs : 0)
        let lineColor: Color = viewModel.colorForLine(index: index, agent: line.agent, oppositeAligned: line.oppositeAligned, colorScheme: colorScheme)

        SpicyLyricLineView(
            line: line,
            currentTimeMs: lineTimeMs,
            isLineActive: isActive,
            isLinePast: isPast,
            distance: distance,
            isRomanizationEnabled: viewModel.isRomanizationEnabled,
            isTranslationEnabled: viewModel.isTranslationEnabled,
            isUserScrolling: isUserScrollingLyrics,
            fontDesign: viewModel.lyricsFontDesign.fontDesign,
            fontSize: viewModel.lyricsFontSize.leadSize,
            isGlowEnabled: viewModel.isLyricsGlowEnabled,
            isBounceEnabled: viewModel.isLyricsBounceEnabled,
            activeColor: lineColor,
            isExactColorEnabled: viewModel.isExactColorEnabled,
            isSpecialWordEffectsEnabled: viewModel.isSpecialWordEffectsEnabled,
            isSongUnsynced: viewModel.isCurrentSongUnsynced,
            isPlaying: viewModel.isPlaying,
            onSeek: { seekMs in
                userScrollResumeTask?.cancel()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    isUserScrollingLyrics = false
                }
                viewModel.seek(to: seekMs)
            }
        )
        .equatable()
        .id(line.id)
    }
}

// MARK: - Spicy Lyrics Connect Sheet
struct SpicyLyricsConnectSheet: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyInput: String = ""
    @State private var isKeyVisible: Bool = false
    @State private var showSuccessBadge: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroHeader
                    statusPill
                    catalogGuideCard
                    keyInputCard
                    actionButtons
                }
                .padding(20)
            }
            .navigationTitle("Spicy Lyrics")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                keyInput = APIConfig.spicyLyricsApiKey
            }
        }
    }

    private var heroHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.25), Color(red: 0.95, green: 0.35, blue: 0.15).opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.orange.opacity(0.3), radius: 12, x: 0, y: 6)

                Image(systemName: "flame.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color(red: 0.95, green: 0.35, blue: 0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.top, 8)

            Text("Spicy Lyrics API")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Connect your personal Client Key for rich syllable synchronization and contributor attribution.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isSpicyLyricsConnected ? Color(red: 0.11, green: 0.85, blue: 0.45) : Color.orange)
                .frame(width: 9, height: 9)

            Text(viewModel.isSpicyLyricsConnected ? "Connected & Active" : "Not Connected")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(viewModel.isSpicyLyricsConnected ? Color(red: 0.11, green: 0.85, blue: 0.45) : .orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill((viewModel.isSpicyLyricsConnected ? Color.green : Color.orange).opacity(0.12))
        )
    }

    private var catalogGuideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Color.orange)
                    .font(.system(size: 14, weight: .bold))
                Text("How to get your free key:")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                guideStep(number: "1", text: "Open the Spicy Lyrics catalog page for Liquid Player.")
                guideStep(number: "2", text: "Click \"Add to Library\" (completely free, 0 slots used).")
                guideStep(number: "3", text: "Copy your personal Client Key and paste it below.")
            }

            if let catalogUrl = URL(string: APIConfig.spicyLyricsCatalogUrl) {
                Link(destination: catalogUrl) {
                    HStack {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("Open Catalog Page (developers.spicylyrics.org)")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.orange)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var keyInputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Client Key")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if isKeyVisible {
                    TextField("sl_pk_...", text: $keyInput)
                        .font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled(true)
                } else {
                    SecureField("sl_pk_...", text: $keyInput)
                        .font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled(true)
                }

                if !keyInput.isEmpty {
                    Button {
                        keyInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    isKeyVisible.toggle()
                } label: {
                    Image(systemName: isKeyVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    pasteFromClipboard()
                } label: {
                    Text("Paste")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .light ? Color.white : Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.saveSpicyLyricsApiKey(trimmed)
                withAnimation(.spring()) {
                    showSuccessBadge = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if showSuccessBadge {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .bold))
                        Text("Saved & Connected!")
                            .font(.system(size: 16, weight: .bold))
                    } else {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 17, weight: .bold))
                        Text(viewModel.isSpicyLyricsConnected ? "Save & Update Key" : "Connect Spicy Lyrics")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.45, blue: 0.1), Color(red: 0.95, green: 0.22, blue: 0.12)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .foregroundStyle(.white)
                .shadow(color: Color.orange.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)

            if viewModel.isSpicyLyricsConnected {
                Button("Disconnect & Remove Key", role: .destructive) {
                    viewModel.disconnectSpicyLyrics()
                    keyInput = ""
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.red)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 8)
    }

    private func guideStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.orange))

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func pasteFromClipboard() {
        #if canImport(UIKit)
        if let string = UIPasteboard.general.string {
            keyInput = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #elseif canImport(AppKit)
        if let string = NSPasteboard.general.string(forType: .string) {
            keyInput = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
    }
}



