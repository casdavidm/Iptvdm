import SwiftUI

/// Vista principal de DM TV: cabecera, pantalla del reproductor, barra "ahora suena",
/// buscador, categorías, lista de canales y barra de pestañas en cápsula flotante.
struct ContentView: View {
    @StateObject private var iptv = IPTVManager()

    @State private var showSettings = false
    @State private var showDrawer = false
    @State private var isPlaying: Bool = true
    @State private var isFullScreen: Bool = false
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer? = nil
    @State private var isBottomBarVisible: Bool = true
    @State private var lastScrollOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Color.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Cabecera
                if !isFullScreen {
                    RetroHeader(
                        onMenu: {
                            dismissKeyboard()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showDrawer.toggle()
                            }
                        },
                        onSettings: {
                            dismissKeyboard()
                            showSettings = true
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }

                // MARK: - Pantalla del reproductor
                VideoPlayerCardView(
                    channel: iptv.selectedChannel,
                    isPlaying: $isPlaying,
                    isFullScreen: isFullScreen,
                    showControls: showControls,
                    isLoading: iptv.isLoading,
                    statusMessage: iptv.statusMessage,
                    onToggleControls: toggleControls,
                    onTogglePlay: togglePlayback,
                    onToggleFullScreen: toggleFullScreen,
                    onResync: resyncLive
                )
                .padding(.horizontal, isFullScreen ? 0 : 16)

                if !isFullScreen {
                    // MARK: - Ahora suena
                    NowPlayingBarView(
                        channel: iptv.selectedChannel,
                        isPlaying: isPlaying,
                        isLoading: iptv.isLoading,
                        isFavorite: iptv.selectedChannel.map { iptv.isFavorite($0) } ?? false,
                        onTogglePlay: togglePlayback,
                        onToggleFavorite: {
                            if let current = iptv.selectedChannel {
                                hapticTap()
                                iptv.toggleFavorite(current)
                            }
                        },
                        onExpand: toggleFullScreen
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    // MARK: - Buscador y modo de vista
                    HStack(spacing: 12) {
                        searchBarView

                        RetroCircleButton(
                            icon: iptv.isGridView ? "list.bullet" : "square.grid.2x2",
                            size: 44,
                            iconSize: 15,
                            label: iptv.isGridView ? "Ver como lista" : "Ver como cuadrícula"
                        ) {
                            hapticTap()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                iptv.isGridView.toggle()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                    // MARK: - Categorías rápidas
                    categoryChipsView
                        .padding(.top, 4)

                    // MARK: - Lista de canales + barra de pestañas
                    ZStack(alignment: .bottom) {
                        channelContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Desvanecido de la lista bajo la cápsula de pestañas
                        LinearGradient(
                            stops: [
                                .init(color: Color.appBackground.opacity(0), location: 0),
                                .init(color: Color.appBackground.opacity(0.92), location: 0.4),
                                .init(color: Color.appBackground, location: 0.6),
                                .init(color: Color.appBackground, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 150)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                        .opacity(isBottomBarVisible ? 1 : 0)

                        RetroTabBar(selected: $iptv.activeTab, badge: { tab in
                            switch tab {
                            case .favorites: return iptv.favoriteIds.count
                            case .recent: return iptv.recentIds.count
                            case .all: return nil
                            }
                        })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .offset(y: isBottomBarVisible ? 0 : 110)
                        .opacity(isBottomBarVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: isBottomBarVisible)
                    }
                }
            }
            .ignoresSafeArea(edges: isFullScreen ? .all : [])

            // MARK: - Cajón lateral de categorías
            if showDrawer {
                CategoriesDrawerView(iptv: iptv, isPresented: $showDrawer)
                    .transition(.move(edge: .leading))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: iptv.activeTab)
        .statusBar(hidden: isFullScreen)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(iptv: iptv)
        }
        .onChange(of: iptv.activeTab) { _ in
            dismissKeyboard()
            withAnimation(.easeInOut(duration: 0.2)) {
                isBottomBarVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            if orientation.isLandscape && !isFullScreen {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isFullScreen = true
                }
                showControls = true
                resetControlsTimer()
            } else if orientation == .portrait && isFullScreen {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isFullScreen = false
                }
                showControls = true
                resetControlsTimer()
            }
        }
        .onAppear {
            resetControlsTimer()
            if iptv.channels.isEmpty && !iptv.password.isEmpty {
                iptv.fetchChannels()
            }
        }
    }

    // MARK: - Buscador hundido

    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(iptv.searchText.isEmpty ? Color.appTextSecondary : Color.appAccent)

            TextField("Buscar canal…", text: $iptv.searchText)
                .font(.system(size: 14))
                .foregroundColor(Color.appTextPrimary)
                .tint(Color.appAccent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !iptv.searchText.isEmpty {
                Button(action: { iptv.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color.appTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .neumorphicInset(Capsule())
    }

    // MARK: - Chips de categorías

    private var categoryChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(iptv.categories, id: \.self) { cat in
                    let isSelected = (iptv.selectedCategory == cat && iptv.activeTab == .all)

                    Button(action: {
                        hapticTap()
                        dismissKeyboard()
                        iptv.activeTab = .all
                        iptv.selectedCategory = cat
                    }) {
                        Text(cat)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? Color.appBackground : Color.appTextSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .neumorphicRaised(Capsule(), fill: isSelected ? Color.appAccent : Color.appCard, shadowRadius: 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Contenido: lista / cuadrícula / estados

    @ViewBuilder
    private var channelContent: some View {
        if let err = iptv.errorMessage {
            VStack(spacing: 14) {
                EmptyStateView(icon: "wifi.exclamationmark", title: err)

                Button(action: { showSettings = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("Configurar en Ajustes")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.appBackground)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .neumorphicRaised(Capsule(), fill: Color.appAccent, shadowRadius: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if iptv.isLoading && iptv.channels.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.appAccent))
                    .scaleEffect(1.2)
                Text(iptv.statusMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
        } else if iptv.filteredChannels.isEmpty {
            EmptyStateView(icon: emptyIcon, title: emptyTitle, hint: emptyHint)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Tracker invisible de desplazamiento vertical
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("channelScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    if iptv.isGridView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                            ForEach(iptv.filteredChannels, id: \.id) { channel in
                                ChannelGridCard(
                                    channel: channel,
                                    isSelected: isSelected(channel),
                                    isPlaying: isPlaying,
                                    isFavorite: iptv.isFavorite(channel),
                                    onSelect: { select(channel) },
                                    onToggleFavorite: {
                                        hapticTap()
                                        iptv.toggleFavorite(channel)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 110)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(iptv.filteredChannels, id: \.id) { channel in
                                ChannelListRow(
                                    channel: channel,
                                    isSelected: isSelected(channel),
                                    isPlaying: isPlaying,
                                    isFavorite: iptv.isFavorite(channel),
                                    onSelect: { select(channel) },
                                    onPlayTapped: {
                                        if isSelected(channel) {
                                            togglePlayback()
                                        } else {
                                            select(channel)
                                        }
                                    },
                                    onToggleFavorite: {
                                        hapticTap()
                                        iptv.toggleFavorite(channel)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 110)
                    }
                }
            }
            .coordinateSpace(name: "channelScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
                let delta = newOffset - lastScrollOffset
                if delta < -10 {
                    if isBottomBarVisible {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isBottomBarVisible = false
                        }
                    }
                } else if delta > 10 || newOffset > -20 {
                    if !isBottomBarVisible {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isBottomBarVisible = true
                        }
                    }
                }
                lastScrollOffset = newOffset
            }
        }
    }

    private var emptyIcon: String {
        switch iptv.activeTab {
        case .favorites: return "star.slash"
        case .recent: return "clock.arrow.circlepath"
        case .all: return iptv.searchText.isEmpty ? "tv.slash" : "magnifyingglass"
        }
    }

    private var emptyTitle: String {
        switch iptv.activeTab {
        case .favorites: return "No tienes canales favoritos aún."
        case .recent: return "Sin canales recientes."
        case .all: return iptv.searchText.isEmpty ? "No se encontraron canales." : "Ningún canal coincide con \"\(iptv.searchText)\"."
        }
    }

    private var emptyHint: String? {
        switch iptv.activeTab {
        case .favorites: return "Toca la estrella en cualquier canal para agregarlo aquí."
        case .recent: return "Los canales que reproduzcas aparecerán aquí."
        case .all: return nil
        }
    }

    // MARK: - Acciones

    private func isSelected(_ channel: XtreamChannel) -> Bool {
        guard let current = iptv.selectedChannel else { return false }
        return (current.streamId == channel.streamId && !channel.streamId.isEmpty) || current.id == channel.id
    }

    private func select(_ channel: XtreamChannel) {
        hapticTap()
        dismissKeyboard()
        isPlaying = true
        iptv.selectedChannel = channel
        iptv.recordWatched(channel)
        showControls = true
        resetControlsTimer()
    }

    private func togglePlayback() {
        hapticTap(.medium)
        isPlaying.toggle()
        resetControlsTimer()
    }

    private func resyncLive() {
        guard let current = iptv.selectedChannel else { return }
        hapticTap()
        iptv.selectedChannel = nil
        isPlaying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            iptv.selectedChannel = current
        }
        resetControlsTimer()
    }

    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        guard isPlaying else { return }
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = false
            }
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            resetControlsTimer()
        }
    }

    private func toggleFullScreen() {
        hapticTap()
        dismissKeyboard()
        withAnimation(.easeInOut(duration: 0.25)) {
            isFullScreen.toggle()
        }
        showControls = true
        resetControlsTimer()
    }
}
