import SwiftUI
import AVKit
import Combine

// MARK: - Color Palette & Theme (Navy Blue #111827, Yellow #FFC61A, White #FFFFFF, Card #1F2937)
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum Theme {
    static let navyBg       = Color(hex: 0x111827) // Background principal #111827
    static let cardBg       = Color(hex: 0x1F2937) // Superficies y tarjetas #1F2937
    static let cardHover    = Color(hex: 0x283548) // Estado activo/hover
    static let yellow       = Color(hex: 0xFFC61A) // Acento amarillo #FFC61A
    static let yellowMuted  = Color(hex: 0xFFC61A).opacity(0.18)
    static let textWhite    = Color(hex: 0xFFFFFF) // Texto principal blanco #FFFFFF
    static let textMuted    = Color(hex: 0x9CA3AF) // Texto secundario #9CA3AF
    static let border       = Color.white.opacity(0.08) // Borde sutil
    static let borderYellow = Color(hex: 0xFFC61A).opacity(0.4)
}

// MARK: - Channel Model
struct XtreamChannel: Identifiable, Equatable {
    let id: String
    let streamId: String
    let name: String
    let category: String
    let hlsUrl: String
    let tsUrl: String
    let logoUrl: String?
}

// MARK: - Filter Tabs
enum FilterTab: String, CaseIterable {
    case all = "Todos"
    case favorites = "Favoritos"
    case recent = "Recientes"
}

// MARK: - Network Session
class InsecureSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - IPTV Manager (State, Data, Favorites & History)
class IPTVManager: ObservableObject {
    @Published var channels: [XtreamChannel] = []
    @Published var filteredChannels: [XtreamChannel] = []
    @Published var selectedChannel: XtreamChannel?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var statusMessage: String = "Listo"

    @Published var searchText: String = "" {
        didSet { filterChannels() }
    }
    @Published var selectedCategory: String = "Todas" {
        didSet { filterChannels() }
    }
    @Published var categories: [String] = ["Todas"]

    @Published var activeTab: FilterTab = .all {
        didSet { filterChannels() }
    }
    @Published var isGridView: Bool = UserDefaults.standard.bool(forKey: "xc_grid_view") {
        didSet { UserDefaults.standard.set(isGridView, forKey: "xc_grid_view") }
    }

    // Favoritos persistentes
    @Published var favoriteIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "xc_favorites") ?? []) {
        didSet {
            UserDefaults.standard.set(Array(favoriteIds), forKey: "xc_favorites")
            if activeTab == .favorites { filterChannels() }
        }
    }

    // Historial reciente persistente
    @Published var recentIds: [String] = UserDefaults.standard.stringArray(forKey: "xc_recents") ?? [] {
        didSet {
            UserDefaults.standard.set(recentIds, forKey: "xc_recents")
            if activeTab == .recent { filterChannels() }
        }
    }

    @Published var serverUrl: String = UserDefaults.standard.string(forKey: "xc_server") ?? "http://veotv.info:8880" {
        didSet { UserDefaults.standard.set(serverUrl, forKey: "xc_server") }
    }
    @Published var username: String = UserDefaults.standard.string(forKey: "xc_user") ?? "DavidMunoz1" {
        didSet { UserDefaults.standard.set(username, forKey: "xc_user") }
    }
    @Published var password: String = {
        let saved = UserDefaults.standard.string(forKey: "xc_pass") ?? ""
        return saved.isEmpty ? "8kz1MRT1r2" : saved
    }() {
        didSet { UserDefaults.standard.set(password, forKey: "xc_pass") }
    }

    init() {
        if (UserDefaults.standard.string(forKey: "xc_pass") ?? "").isEmpty {
            UserDefaults.standard.set("8kz1MRT1r2", forKey: "xc_pass")
        }
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
    }

    private lazy var customSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 45.0
        config.timeoutIntervalForResource = 60.0
        return URLSession(configuration: config, delegate: InsecureSessionDelegate(), delegateQueue: nil)
    }()

    func isFavorite(_ channel: XtreamChannel) -> Bool {
        let key = channel.streamId.isEmpty ? channel.id : channel.streamId
        return favoriteIds.contains(key) || favoriteIds.contains(channel.id)
    }

    func toggleFavorite(_ channel: XtreamChannel) {
        let key = channel.streamId.isEmpty ? channel.id : channel.streamId
        if isFavorite(channel) {
            favoriteIds.remove(key)
            favoriteIds.remove(channel.streamId)
            favoriteIds.remove(channel.id)
        } else {
            favoriteIds.insert(key)
        }
    }

    func recordWatched(_ channel: XtreamChannel) {
        let key = channel.streamId.isEmpty ? channel.id : channel.streamId
        var recents = recentIds.filter { $0 != key && $0 != channel.id }
        recents.insert(key, at: 0)
        if recents.count > 60 { recents = Array(recents.prefix(60)) }
        recentIds = recents
    }

    func clearRecents() {
        recentIds.removeAll()
    }

    func clearFavorites() {
        favoriteIds.removeAll()
    }

    func count(for category: String) -> Int {
        if category == "Todas" {
            return channels.count
        }
        return channels.filter { $0.category == category }.count
    }

    func cleanServerUrl(_ url: String) -> String {
        var cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("/") { cleaned.removeLast() }
        if !cleaned.lowercased().hasPrefix("http://") && !cleaned.lowercased().hasPrefix("https://") {
            cleaned = "http://" + cleaned
        }
        return cleaned
    }

    func buildUrl(base: String, endpoint: String, queryItems: [URLQueryItem]) -> URL? {
        let baseClean = cleanServerUrl(base)
        guard var components = URLComponents(string: baseClean) else { return nil }
        let currentPath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let cleanEndpoint = endpoint.hasPrefix("/") ? endpoint : "/" + endpoint
        components.path = currentPath + cleanEndpoint
        components.queryItems = queryItems
        return components.url
    }

    func fetchChannels() {
        let cleanPass = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleanServerUrl(serverUrl)

        guard !cleanPass.isEmpty else {
            self.errorMessage = "La contraseña está vacía. Abre Ajustes e ingrésala."
            return
        }

        self.isLoading = true
        self.errorMessage = nil
        self.statusMessage = "Conectando al servidor..."

        let queryItems = [
            URLQueryItem(name: "username", value: cleanUser),
            URLQueryItem(name: "password", value: cleanPass),
            URLQueryItem(name: "action", value: "get_live_streams")
        ]

        guard let apiEndpoint = buildUrl(base: base, endpoint: "player_api.php", queryItems: queryItems) else {
            self.errorMessage = "URL de servidor inválida."
            self.isLoading = false
            return
        }

        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 45.0
        request.setValue("IPTVSmartersPro/3.1.5", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        customSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            if let err = error {
                DispatchQueue.main.async {
                    self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "Error de red: \(err.localizedDescription)")
                }
                return
            }

            guard let rawData = data, !rawData.isEmpty else {
                DispatchQueue.main.async {
                    self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "Respuesta vacía del servidor (Código \(statusCode))")
                }
                return
            }

            if statusCode != 200 && statusCode != 0 {
                DispatchQueue.main.async {
                    self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "Servidor respondió con código \(statusCode)")
                }
                return
            }

            // Caso 1: Array JSON Xtream
            if let rawArray = try? JSONSerialization.jsonObject(with: rawData) as? [[String: Any]], !rawArray.isEmpty {
                var parsed: [XtreamChannel] = []
                var catsSet = Set<String>()

                for item in rawArray {
                    let sName = (item["name"] as? String) ?? "Canal"
                    var streamIdStr = ""
                    if let intId = item["stream_id"] as? Int {
                        streamIdStr = "\(intId)"
                    } else if let strId = item["stream_id"] as? String {
                        streamIdStr = strId
                    } else {
                        continue
                    }

                    var cat = "General"
                    if let catName = item["category_name"] as? String, !catName.trimmingCharacters(in: .whitespaces).isEmpty {
                        cat = catName.trimmingCharacters(in: .whitespaces)
                    } else if let nameMatch = sName.range(of: "^[A-Za-z0-9\\s]{2,10}[|:\\-]", options: .regularExpression) {
                        cat = String(sName[nameMatch].dropLast()).trimmingCharacters(in: .whitespaces)
                    }
                    catsSet.insert(cat)

                    let iconUrl = (item["stream_icon"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanIcon = (iconUrl?.isEmpty == false) ? iconUrl : nil

                    let hls = "\(base)/live/\(cleanUser)/\(cleanPass)/\(streamIdStr).m3u8"
                    let ts = "\(base)/\(cleanUser)/\(cleanPass)/\(streamIdStr)"

                    // Cada fila en la lista debe tener un id único estricto para que SwiftUI LazyVStack no deje 'espacios fantasma' cuando se repite un canal
                    let uniqueRowId = "xc-\(streamIdStr)-\(parsed.count + 1)"

                    parsed.append(XtreamChannel(
                        id: uniqueRowId,
                        streamId: streamIdStr,
                        name: sName,
                        category: cat,
                        hlsUrl: hls,
                        tsUrl: ts,
                        logoUrl: cleanIcon
                    ))
                }

                DispatchQueue.main.async {
                    self.isLoading = false
                    if !parsed.isEmpty {
                        self.channels = parsed
                        self.categories = ["Todas"] + Array(catsSet).sorted()
                        self.filterChannels()
                        if self.selectedChannel == nil {
                            self.selectedChannel = parsed.first
                        }
                        self.statusMessage = "\(parsed.count) canales cargados"
                    } else {
                        self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "La lista de canales en el servidor está vacía")
                    }
                }
                return
            }

            // Caso 2: Objeto JSON informativo o de error
            if let dict = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                if let userInfo = dict["user_info"] as? [String: Any] {
                    let auth = userInfo["auth"] as? Int ?? 1
                    let status = (userInfo["status"] as? String) ?? ""
                    if auth == 0 || status.lowercased() == "disabled" || status.lowercased() == "expired" {
                        DispatchQueue.main.async {
                            self.isLoading = false
                            let estado = status.isEmpty ? "No autorizado" : status
                            self.errorMessage = "Credenciales incorrectas o cuenta vencida (Estado: \(estado)). Abre Ajustes."
                        }
                        return
                    }
                }
                if let message = dict["message"] as? String {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Servidor: \(message). Verifica tus datos en Ajustes."
                    }
                    return
                }
            }

            // Caso 3: Fallback a M3U
            DispatchQueue.main.async {
                self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "El API Xtream no respondió en formato JSON")
            }
        }.resume()
    }

    func fetchM3uFallback(base: String, user: String, pass: String, previousErr: String) {
        self.statusMessage = "Intentando lista M3U alternativa..."

        let queryItems = [
            URLQueryItem(name: "username", value: user),
            URLQueryItem(name: "password", value: pass),
            URLQueryItem(name: "type", value: "m3u_plus"),
            URLQueryItem(name: "output", value: "ts")
        ]

        guard let m3uUrl = buildUrl(base: base, endpoint: "get.php", queryItems: queryItems) else {
            self.isLoading = false
            self.errorMessage = previousErr
            return
        }

        var m3uReq = URLRequest(url: m3uUrl)
        m3uReq.timeoutInterval = 45.0
        m3uReq.setValue("IPTVSmartersPro/3.1.5", forHTTPHeaderField: "User-Agent")

        customSession.dataTask(with: m3uReq) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                if let err = error {
                    self.errorMessage = "Error de conexión: \(err.localizedDescription)"
                    return
                }

                if statusCode == 404 {
                    self.errorMessage = "Error 404: Servidor o credenciales no encontrados. Verifica en Ajustes."
                    return
                } else if statusCode == 401 || statusCode == 403 {
                    self.errorMessage = "Error \(statusCode): Usuario o contraseña denegados. Verifica en Ajustes."
                    return
                } else if statusCode >= 500 {
                    self.errorMessage = "Error \(statusCode): El servidor IPTV tiene problemas internos."
                    return
                }

                guard let rawData = data, let text = String(data: rawData, encoding: .utf8) ?? String(data: rawData, encoding: .isoLatin1) else {
                    self.errorMessage = "El servidor no envió datos legibles (Código \(statusCode))."
                    return
                }

                if text.contains("#EXTM3U") || text.contains("#EXTINF:") {
                    self.parseM3UContent(text, base: base, user: user, pass: pass)
                } else {
                    self.errorMessage = "El servidor devolvió un error (Código \(statusCode)). Verifica servidor, usuario y contraseña en Ajustes."
                }
            }
        }.resume()
    }

    func parseM3UContent(_ content: String, base: String, user: String, pass: String) {
        var parsed: [XtreamChannel] = []
        var catsSet = Set<String>()
        var tempName = ""
        var tempCat = "General"
        var tempLogo: String? = nil

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("#EXTINF:") {
                // Categoría
                if let groupRange = trimmed.range(of: "group-title=\"([^\"]+)\"", options: .regularExpression) {
                    let fullMatch = String(trimmed[groupRange])
                    tempCat = fullMatch.replacingOccurrences(of: "group-title=\"", with: "").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                } else if let groupRange2 = trimmed.range(of: "group-title='([^']+)'", options: .regularExpression) {
                    let fullMatch = String(trimmed[groupRange2])
                    tempCat = fullMatch.replacingOccurrences(of: "group-title='", with: "").replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
                }

                // Logo
                if let logoRange = trimmed.range(of: "tvg-logo=\"([^\"]+)\"", options: .regularExpression) {
                    let fullMatch = String(trimmed[logoRange])
                    tempLogo = fullMatch.replacingOccurrences(of: "tvg-logo=\"", with: "").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                }

                // Nombre
                if let commaIdx = trimmed.lastIndex(of: ",") {
                    tempName = String(trimmed[trimmed.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
                }
            } else if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                let id = "m3u-\(parsed.count + 1)"
                let streamUrl = trimmed
                let hls: String
                let ts: String
                if streamUrl.contains(".m3u8") {
                    hls = streamUrl
                    ts = streamUrl.replacingOccurrences(of: ".m3u8", with: ".ts")
                } else if streamUrl.hasSuffix(".ts") {
                    ts = streamUrl
                    hls = String(streamUrl.dropLast(3)) + ".m3u8"
                } else {
                    ts = streamUrl
                    hls = streamUrl + ".m3u8"
                }

                let finalName = tempName.isEmpty ? "Canal \(parsed.count + 1)" : tempName
                let finalCat = tempCat.isEmpty ? "General" : tempCat

                parsed.append(XtreamChannel(
                    id: id,
                    streamId: "\(parsed.count + 1)",
                    name: finalName,
                    category: finalCat,
                    hlsUrl: hls,
                    tsUrl: ts,
                    logoUrl: tempLogo
                ))
                catsSet.insert(finalCat)
                tempName = ""
                tempCat = "General"
                tempLogo = nil

                if parsed.count >= 2500 { break }
            }
        }

        if !parsed.isEmpty {
            self.channels = parsed
            self.categories = ["Todas"] + Array(catsSet).sorted()
            self.filterChannels()
            if self.selectedChannel == nil {
                self.selectedChannel = parsed.first
            }
            self.statusMessage = "\(parsed.count) canales cargados"
        } else {
            self.errorMessage = "No se encontraron canales válidos en la lista M3U. Verifica tus datos en Ajustes."
        }
    }

    func filterChannels() {
        var result = channels

        // 1. Filtrar por pestaña activa (Todos, Favoritos o Recientes)
        switch activeTab {
        case .all:
            if selectedCategory != "Todas" {
                result = result.filter { $0.category == selectedCategory }
            }
        case .favorites:
            var favList: [XtreamChannel] = []
            var seenKeys = Set<String>()
            for ch in channels {
                if isFavorite(ch) {
                    let key = ch.streamId.isEmpty ? ch.id : ch.streamId
                    if !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        favList.append(ch)
                    }
                }
            }
            result = favList
        case .recent:
            // Conservar el orden cronológico de recientes de forma 100% segura (sin Dictionary fatalError)
            var recentOrdered: [XtreamChannel] = []
            var seenKeys = Set<String>()
            for rId in recentIds {
                if let ch = channels.first(where: { $0.streamId == rId || $0.id == rId }) {
                    let key = ch.streamId.isEmpty ? ch.id : ch.streamId
                    if !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        recentOrdered.append(ch)
                    }
                }
            }
            result = recentOrdered
        }

        // 2. Filtrar por texto de búsqueda
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        self.filteredChannels = result
    }
}

// MARK: - VLC Player (MobileVLCKit)
#if canImport(MobileVLCKit)
import MobileVLCKit

struct VLCPlayerView: UIViewRepresentable {
    let streamUrl: String
    @Binding var isPlaying: Bool

    class Coordinator: NSObject, VLCMediaPlayerDelegate {
        var mediaPlayer: VLCMediaPlayer = VLCMediaPlayer()
        var currentUrl: String = ""
        var parent: VLCPlayerView

        init(_ parent: VLCPlayerView) {
            self.parent = parent
            super.init()
            mediaPlayer.delegate = self
        }

        func playStream(url: String) {
            guard !url.isEmpty, let mediaUrl = URL(string: url) else { return }
            currentUrl = url

            if mediaPlayer.isPlaying {
                mediaPlayer.stop()
            }

            let media = VLCMedia(url: mediaUrl)
            media.addOptions([
                "network-caching": 2500,
                ":network-caching": 2500,
                ":clock-jitter": 0,
                ":clock-synchro": 0,
                ":http-user-agent": "IPTVSmartersPro/3.1.5"
            ])
            mediaPlayer.media = media
            mediaPlayer.play()
        }

        func pauseStream() {
            if mediaPlayer.canPause {
                mediaPlayer.pause()
            } else {
                mediaPlayer.stop()
            }
        }

        func resumeStream() {
            if mediaPlayer.state == .paused {
                mediaPlayer.play()
            } else if !currentUrl.isEmpty {
                playStream(url: currentUrl)
            }
        }

        deinit {
            mediaPlayer.stop()
            mediaPlayer.drawable = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.mediaPlayer.drawable = view
        if isPlaying {
            context.coordinator.playStream(url: streamUrl)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if context.coordinator.currentUrl != streamUrl {
            context.coordinator.playStream(url: streamUrl)
        } else {
            if isPlaying {
                if !context.coordinator.mediaPlayer.isPlaying {
                    context.coordinator.resumeStream()
                }
            } else {
                if context.coordinator.mediaPlayer.isPlaying {
                    context.coordinator.pauseStream()
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.mediaPlayer.stop()
        coordinator.mediaPlayer.drawable = nil
    }
}
#endif

// MARK: - Native Player (AVPlayer fallback)
struct NativePlayerView: UIViewControllerRepresentable {
    let streamUrl: String
    @Binding var isPlaying: Bool

    class Coordinator: NSObject {
        var currentUrl: String = ""
        weak var player: AVPlayer?
        private var watchdogTimer: Timer?
        private var stallSeconds: Double = 0
        private var lastObservedTime: Double = -1.0
        private var stallObserver: Any?
        private var endObserver: Any?

        func setup(player: AVPlayer, streamUrl: String) {
            self.player = player
            self.currentUrl = streamUrl
            self.lastObservedTime = -1.0
            self.stallSeconds = 0

            cleanObservers()

            stallObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                p.playImmediately(atRate: 1.0)
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                p.playImmediately(atRate: 1.0)
            }

            startWatchdog(for: player)
        }

        func startWatchdog(for player: AVPlayer) {
            stopWatchdog()

            watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self, weak player] _ in
                guard let self = self, let player = player else { return }

                if player.timeControlStatus == .paused || player.rate == 0 {
                    self.stallSeconds = 0
                    return
                }

                let currentItemTime = player.currentTime().seconds
                let isWaiting = (player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                let isFrozen = (currentItemTime > 0 && abs(currentItemTime - self.lastObservedTime) < 0.05)

                if isWaiting || isFrozen {
                    self.stallSeconds += 2.0
                    if self.stallSeconds >= 6.0 && self.stallSeconds < 14.0 {
                        self.smoothRecoverLiveEdge(player: player)
                    } else if self.stallSeconds >= 14.0 {
                        self.stallSeconds = 0
                        self.hardReconnect(player: player)
                    }
                } else {
                    self.stallSeconds = 0
                    self.lastObservedTime = currentItemTime
                }
            }
        }

        func smoothRecoverLiveEdge(player: AVPlayer) {
            guard player.timeControlStatus != .paused && player.rate != 0 else { return }
            player.playImmediately(atRate: 1.0)
        }

        func hardReconnect(player: AVPlayer) {
            guard !currentUrl.isEmpty, let url = URL(string: currentUrl) else { return }
            guard player.timeControlStatus != .paused && player.rate != 0 else { return }

            let userAgent = "IPTVSmartersPro/3.1.5"
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent],
                "AVURLAssetHTTPUserAgentKey": userAgent
            ]
            let asset = AVURLAsset(url: url, options: options)
            let newItem = AVPlayerItem(asset: asset)
            newItem.preferredForwardBufferDuration = 10.0
            newItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            cleanObservers()
            player.replaceCurrentItem(with: newItem)

            stallObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: newItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                p.playImmediately(atRate: 1.0)
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                p.playImmediately(atRate: 1.0)
            }

            player.play()
        }

        func cleanObservers() {
            if let obs = stallObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
            stallObserver = nil
            endObserver = nil
        }

        func stopWatchdog() {
            watchdogTimer?.invalidate()
            watchdogTimer = nil
            stallSeconds = 0
            lastObservedTime = -1.0
        }

        deinit {
            stopWatchdog()
            cleanObservers()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        var targetUrl = streamUrl
        if targetUrl.hasSuffix(".ts") {
            targetUrl = String(targetUrl.dropLast(3)) + ".m3u8"
        }

        if context.coordinator.currentUrl != targetUrl {
            context.coordinator.currentUrl = targetUrl
            context.coordinator.stopWatchdog()
            context.coordinator.cleanObservers()
            context.coordinator.player?.pause()
            context.coordinator.player?.replaceCurrentItem(with: nil)

            guard let url = URL(string: targetUrl) else { return }

            let userAgent = "IPTVSmartersPro/3.1.5"
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent],
                "AVURLAssetHTTPUserAgentKey": userAgent
            ]
            let asset = AVURLAsset(url: url, options: options)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 10.0
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = true

            context.coordinator.setup(player: player, streamUrl: targetUrl)
            uiViewController.player = player
            if isPlaying {
                player.play()
            }
        } else {
            if isPlaying && (context.coordinator.player?.timeControlStatus == .paused || context.coordinator.player?.rate == 0) {
                context.coordinator.player?.playImmediately(atRate: 1.0)
            } else if !isPlaying && (context.coordinator.player?.timeControlStatus != .paused && context.coordinator.player?.rate != 0) {
                context.coordinator.player?.pause()
            }
        }
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stopWatchdog()
        coordinator.cleanObservers()
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
    }
}

// MARK: - App Logo View (DMTV)
struct AppLogoView: View {
    var height: CGFloat = 26

    var body: some View {
        Group {
            if let image = UIImage(named: "AppLogo") ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "logo", ofType: "png") ?? "") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
            } else {
                HStack(spacing: 4) {
                    Text("DM")
                        .font(.system(size: height * 0.72, weight: .black))
                        .foregroundColor(Theme.yellow)
                    Rectangle()
                        .fill(Theme.yellow)
                        .frame(width: 2, height: height * 0.7)
                    Text("TV")
                        .font(.system(size: height * 0.72, weight: .black))
                        .foregroundColor(Theme.textWhite)
                }
            }
        }
    }
}

// MARK: - Tab Icon View (Custom Icons: Layers, Star, Clock)
struct TabIconView: View {
    let tab: FilterTab
    let isSelected: Bool
    var size: CGFloat = 22

    var body: some View {
        Group {
            let assetName: String = {
                switch tab {
                case .all: return "tab_all"
                case .favorites: return "tab_favorites"
                case .recent: return "tab_recent"
                }
            }()

            if let uiImage = UIImage(named: assetName) ?? UIImage(contentsOfFile: Bundle.main.path(forResource: assetName, ofType: "png") ?? "") {
                Image(uiImage: uiImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundColor(isSelected ? Theme.yellow : Theme.textMuted)
            } else {
                Image(systemName: fallbackSymbol(for: tab))
                    .font(.system(size: size * 0.9, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? Theme.yellow : Theme.textMuted)
            }
        }
    }

    private func fallbackSymbol(for tab: FilterTab) -> String {
        switch tab {
        case .all: return "square.stack.3d.up.fill"
        case .favorites: return "star.fill"
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Scroll Offset Tracker for Auto-Hiding Bottom Bar
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Slide-out Categories Drawer
struct CategoriesDrawerView: View {
    @ObservedObject var iptv: IPTVManager
    @Binding var isPresented: Bool
    @State private var categoryFilter: String = ""

    var filteredCategories: [String] {
        if categoryFilter.isEmpty {
            return iptv.categories
        }
        return iptv.categories.filter { $0.localizedCaseInsensitiveContains(categoryFilter) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Header del Drawer
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        AppLogoView(height: 28)
                        Text("iptv player")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                    }

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.textWhite)
                            .frame(width: 32, height: 32)
                            .background(Theme.cardBg)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 54)
                .padding(.bottom, 16)

                // Título de sección y buscador interno
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Categorías")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.textWhite)
                        Spacer()
                        Text("\(iptv.categories.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.yellowMuted)
                            .cornerRadius(10)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                        TextField("Buscar categoría...", text: $categoryFilter)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textWhite)
                        if !categoryFilter.isEmpty {
                            Button(action: { categoryFilter = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.cardBg)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                Divider()
                    .background(Theme.border)

                // Lista de Categorías
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredCategories, id: \.self) { cat in
                            let isSelected = (iptv.selectedCategory == cat && iptv.activeTab == .all)
                            let count = iptv.count(for: cat)

                            Button(action: {
                                iptv.activeTab = .all
                                iptv.selectedCategory = cat
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isPresented = false
                                }
                            }) {
                                HStack(spacing: 12) {
                                    // Barra indicadora izquierda amarilla
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(isSelected ? Theme.yellow : Color.clear)
                                        .frame(width: 4, height: 26)

                                    Text(cat)
                                        .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? Theme.yellow : Theme.textWhite)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("\(count)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isSelected ? Theme.yellow : Theme.textMuted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(isSelected ? Theme.yellowMuted : Theme.cardBg)
                                        .cornerRadius(8)
                                }
                                .padding(.trailing, 16)
                                .padding(.vertical, 8)
                                .background(isSelected ? Theme.yellowMuted.opacity(0.35) : Color.clear)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }

                Spacer()
            }
            .frame(width: 290)
            .background(Theme.navyBg)
            .overlay(
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1),
                alignment: .trailing
            )

            // Fondo semitransparente que descarta al tocar
            Color.black.opacity(0.6)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isPresented = false
                    }
                }
        }
        .edgesIgnoringSafeArea(.vertical)
    }
}

// MARK: - Channel Card (List View)
struct ChannelListRow: View {
    let channel: XtreamChannel
    let isSelected: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icono / Logo del canal
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Theme.yellowMuted : Theme.cardBg)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Theme.yellow : Theme.border, lineWidth: 1)
                        )

                    if let logo = channel.logoUrl, let url = URL(string: logo) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                            default:
                                fallbackChannelIcon
                            }
                        }
                    } else {
                        fallbackChannelIcon
                    }
                }

                // Nombre y Categoría
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                        .foregroundColor(isSelected ? Theme.yellow : Theme.textWhite)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("Categoría:")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Theme.textMuted)
                        Text(channel.category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textMuted.opacity(0.9))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Indicador de reproducción activa
                if isSelected {
                    Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.slash.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.yellow)
                        .padding(.trailing, 4)
                }

                // Botón de Favorito
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundColor(isFavorite ? Theme.yellow : Theme.textMuted.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.cardHover : Theme.cardBg)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.borderYellow : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var fallbackChannelIcon: some View {
        Image(systemName: "tv")
            .font(.system(size: 18))
            .foregroundColor(isSelected ? Theme.yellow : Theme.textWhite.opacity(0.7))
    }
}

// MARK: - Channel Card (Grid View)
struct ChannelGridCard: View {
    let channel: XtreamChannel
    let isSelected: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Header de la tarjeta con Logo y Estrella
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Theme.yellowMuted : Theme.navyBg)
                            .frame(width: 38, height: 38)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Theme.yellow : Theme.border, lineWidth: 1)
                            )

                        if let logo = channel.logoUrl, let url = URL(string: logo) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                default:
                                    Image(systemName: "tv")
                                        .font(.system(size: 15))
                                        .foregroundColor(isSelected ? Theme.yellow : Theme.textWhite.opacity(0.7))
                                }
                            }
                        } else {
                            Image(systemName: "tv")
                                .font(.system(size: 15))
                                .foregroundColor(isSelected ? Theme.yellow : Theme.textWhite.opacity(0.7))
                        }
                    }

                    Spacer()

                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 15))
                            .foregroundColor(isFavorite ? Theme.yellow : Theme.textMuted.opacity(0.6))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }

                // Nombre y Categoría
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                        .foregroundColor(isSelected ? Theme.yellow : Theme.textWhite)
                        .lineLimit(2)
                        .frame(height: 34, alignment: .topLeading)

                    HStack {
                        Text(channel.category)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                        Spacer()
                        if isSelected {
                            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.yellow)
                        }
                    }
                }
            }
            .padding(12)
            .background(isSelected ? Theme.cardHover : Theme.cardBg)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.borderYellow : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Main User Interface (Minimalist & Organized)
struct ContentView: View {
    @StateObject private var iptv = IPTVManager()
    @State private var showSettings = false
    @State private var showDrawer = false
    @State private var showSearch = false
    @State private var isPlaying: Bool = true
    @State private var isFullScreen: Bool = false
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer? = nil
    @State private var isBottomBarVisible: Bool = true
    @State private var lastScrollOffset: CGFloat = 0

    func resetControlsTimer() {
        controlsTimer?.invalidate()
        guard isPlaying else { return }
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = false
            }
        }
    }

    func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            resetControlsTimer()
        }
    }

    func toggleFullScreen() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isFullScreen.toggle()
        }
        showControls = true
        resetControlsTimer()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.navyBg
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // 1. Barra de Navegación Superior Minimalista
                if !isFullScreen {
                    HStack(spacing: 12) {
                        // Botón Hamburguesa / Drawer
                        Button(action: {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showDrawer.toggle()
                            }
                        }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Theme.textWhite)
                                .frame(width: 38, height: 38)
                                .background(Theme.cardBg)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                        }

                        // Logo DM TV
                        AppLogoView(height: 26)

                        Spacer()

                        // Botón de Buscar
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSearch.toggle()
                                if !showSearch {
                                    iptv.searchText = ""
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                            }
                        }) {
                            Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(showSearch ? Theme.yellow : Theme.textWhite)
                                .frame(width: 38, height: 38)
                                .background(Theme.cardBg)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(showSearch ? Theme.borderYellow : Theme.border, lineWidth: 1))
                        }

                        // Botón de Ajustes
                        Button(action: {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Theme.textWhite)
                                .frame(width: 38, height: 38)
                                .background(Theme.cardBg)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .background(Theme.navyBg)

                    // Campo de búsqueda colapsable
                    if showSearch {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.yellow)
                            TextField("Buscar canal por nombre...", text: $iptv.searchText)
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textWhite)
                            if !iptv.searchText.isEmpty {
                                Button(action: {
                                    iptv.searchText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.textMuted)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.cardBg)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderYellow, lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                // 2. Contenedor del Reproductor de Video
                ZStack {
                    if let selected = iptv.selectedChannel {
                        #if canImport(MobileVLCKit)
                        VLCPlayerView(streamUrl: selected.tsUrl, isPlaying: $isPlaying)
                            .background(Color.black)
                        #else
                        NativePlayerView(streamUrl: selected.hlsUrl, isPlaying: $isPlaying)
                            .background(Color.black)
                        #endif

                        // Superficie transparente activa para detectar toques
                        Color.black.opacity(showControls ? 0.45 : 0.001)
                            .edgesIgnoringSafeArea(.all)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleControls()
                            }

                        // Capa de Controles Overlay
                        if showControls {
                            VStack(spacing: 0) {
                                // Barra superior del reproductor
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(selected.name)
                                            .font(.system(size: isFullScreen ? 18 : 15, weight: .bold))
                                            .foregroundColor(Theme.textWhite)
                                            .lineLimit(1)
                                            .shadow(color: .black.opacity(0.9), radius: 4)

                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(isPlaying ? Theme.yellow : Color.orange)
                                                .frame(width: 7, height: 7)
                                            Text(isPlaying ? "EN VIVO" : "PAUSADO")
                                                .font(.system(size: 10, weight: .black))
                                                .foregroundColor(isPlaying ? Theme.yellow : Color.orange)
                                            Text("•")
                                                .font(.caption2)
                                                .foregroundColor(Theme.textMuted)
                                            Text(selected.category)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(Theme.textWhite.opacity(0.85))
                                        }
                                        .shadow(color: .black.opacity(0.9), radius: 4)
                                    }

                                    Spacer()

                                    // Botón de pantalla completa superior
                                    Button(action: {
                                        toggleFullScreen()
                                    }) {
                                        Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(Theme.textWhite)
                                            .frame(width: 36, height: 36)
                                            .background(Color.black.opacity(0.75))
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, isFullScreen ? 44 : 12)

                                Spacer()

                                // Botón Central de Play / Pausa
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        isPlaying.toggle()
                                        resetControlsTimer()
                                    }) {
                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: isFullScreen ? 38 : 30, weight: .bold))
                                            .foregroundColor(Theme.yellow)
                                            .frame(width: isFullScreen ? 78 : 64, height: isFullScreen ? 78 : 64)
                                            .background(Color.black.opacity(0.75))
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle()
                                                    .stroke(Theme.yellow, lineWidth: 2)
                                            )
                                            .shadow(color: Theme.yellow.opacity(0.3), radius: 10)
                                    }
                                    Spacer()
                                }

                                Spacer()

                                // Barra inferior del reproductor
                                HStack {
                                    // Sincronizar en vivo
                                    Button(action: {
                                        if let current = iptv.selectedChannel {
                                            iptv.selectedChannel = nil
                                            isPlaying = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                iptv.selectedChannel = current
                                            }
                                        }
                                        resetControlsTimer()
                                    }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 11, weight: .bold))
                                            Text("Sincronizar En Vivo")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundColor(Theme.textWhite)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.black.opacity(0.75))
                                        .cornerRadius(12)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    }

                                    Spacer()

                                    // Botón de pantalla completa inferior
                                    Button(action: {
                                        toggleFullScreen()
                                    }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "viewfinder")
                                                .font(.system(size: 11, weight: .bold))
                                            Text(isFullScreen ? "Salir" : "Pantalla Completa")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundColor(Theme.textWhite)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.black.opacity(0.75))
                                        .cornerRadius(12)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, isFullScreen ? 34 : 12)
                            }
                            .transition(.opacity)
                        }
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .overlay(
                                VStack(spacing: 8) {
                                    if iptv.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.yellow))
                                        Text(iptv.statusMessage)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Theme.textMuted)
                                    } else {
                                        Image(systemName: "play.tv")
                                            .font(.system(size: 32))
                                            .foregroundColor(Theme.textMuted)
                                        Text("Selecciona un canal para comenzar")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Theme.textMuted)
                                    }
                                }
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: isFullScreen ? nil : (UIScreen.main.bounds.width * 9 / 16))
                .frame(maxHeight: isFullScreen ? .infinity : nil)
                .background(Color.black)

                // 3. Contenido en Modo Vertical (Now Playing Bar, Categorías y Lista)
                if !isFullScreen {
                    // Barra Now Playing directa y limpia
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(iptv.selectedChannel?.name ?? "DM TV")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Theme.textWhite)
                                .lineLimit(1)
                            Text(iptv.selectedChannel?.category ?? "En vivo")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.textMuted)
                        }

                        Spacer()

                        // Botón de Play / Pausa tipo píldora (Amarillo #FFC61A con texto #111827)
                        Button(action: {
                            isPlaying.toggle()
                            resetControlsTimer()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 12, weight: .black))
                                Text(isPlaying ? "Pausa" : "Play")
                                    .font(.system(size: 12, weight: .black))
                            }
                            .foregroundColor(Theme.navyBg)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.yellow)
                            .cornerRadius(20)
                            .shadow(color: Theme.yellow.opacity(0.3), radius: 6)
                        }

                        // Botón de Favorito rápido para el canal actual
                        if let current = iptv.selectedChannel {
                            Button(action: {
                                iptv.toggleFavorite(current)
                            }) {
                                Image(systemName: iptv.isFavorite(current) ? "star.fill" : "star")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(iptv.isFavorite(current) ? Theme.yellow : Theme.textWhite)
                                    .frame(width: 34, height: 34)
                                    .background(Theme.cardBg)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                            }
                        }

                        // Botón directo de Pantalla Completa
                        Button(action: {
                            toggleFullScreen()
                        }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.textWhite)
                                .frame(width: 34, height: 34)
                                .background(Theme.cardBg)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.cardBg)
                    .overlay(
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1),
                        alignment: .bottom
                    )

                    // Carrusel horizontal de Categorías Rápidas
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(iptv.categories, id: \.self) { cat in
                                let isSelected = (iptv.selectedCategory == cat && iptv.activeTab == .all)
                                Button(action: {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    iptv.activeTab = .all
                                    iptv.selectedCategory = cat
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isBottomBarVisible = true
                                    }
                                }) {
                                    Text(cat)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(isSelected ? Theme.yellow : Theme.cardBg)
                                        .foregroundColor(isSelected ? Theme.navyBg : Theme.textWhite)
                                        .cornerRadius(18)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18)
                                                .stroke(isSelected ? Theme.yellow : Theme.border, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    // Contenido Principal: Lista / Cuadrícula de Canales + Píldora Flotante Inferior
                    ZStack(alignment: .bottom) {
                        if let err = iptv.errorMessage {
                            VStack(spacing: 14) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Theme.yellow)
                                    .font(.system(size: 40))
                                Text(err)
                                    .font(.system(size: 14, weight: .medium))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(Theme.textMuted)
                                    .padding(.horizontal, 24)

                                Button(action: { showSettings = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "gearshape")
                                        Text("Configurar en Ajustes")
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Theme.navyBg)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(Theme.yellow)
                                    .cornerRadius(20)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if iptv.filteredChannels.isEmpty && !iptv.isLoading {
                            VStack(spacing: 10) {
                                Image(systemName: iptv.activeTab == .favorites ? "star" : "magnifyingglass")
                                    .font(.system(size: 36))
                                    .foregroundColor(Theme.textMuted.opacity(0.6))
                                Text(iptv.activeTab == .favorites ? "No tienes canales favoritos aún" : (iptv.activeTab == .recent ? "Sin canales recientes" : "No se encontraron canales"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.textMuted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                        // Vista Cuadrícula
                                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                            ForEach(iptv.filteredChannels, id: \.id) { channel in
                                                let isChannelSelected = (iptv.selectedChannel?.streamId == channel.streamId && !channel.streamId.isEmpty) || (iptv.selectedChannel?.id == channel.id)
                                                ChannelGridCard(
                                                    channel: channel,
                                                    isSelected: isChannelSelected,
                                                    isPlaying: isPlaying,
                                                    isFavorite: iptv.isFavorite(channel),
                                                    onSelect: {
                                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                                        isPlaying = true
                                                        iptv.selectedChannel = channel
                                                        iptv.recordWatched(channel)
                                                    },
                                                    onToggleFavorite: {
                                                        iptv.toggleFavorite(channel)
                                                    }
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.top, 8)
                                        .padding(.bottom, 78) // Espacio para que el último canal nunca quede tapado
                                    } else {
                                        // Vista Lista
                                        LazyVStack(spacing: 8) {
                                            ForEach(iptv.filteredChannels, id: \.id) { channel in
                                                let isChannelSelected = (iptv.selectedChannel?.streamId == channel.streamId && !channel.streamId.isEmpty) || (iptv.selectedChannel?.id == channel.id)
                                                ChannelListRow(
                                                    channel: channel,
                                                    isSelected: isChannelSelected,
                                                    isPlaying: isPlaying,
                                                    isFavorite: iptv.isFavorite(channel),
                                                    onSelect: {
                                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                                        isPlaying = true
                                                        iptv.selectedChannel = channel
                                                        iptv.recordWatched(channel)
                                                    },
                                                    onToggleFavorite: {
                                                        iptv.toggleFavorite(channel)
                                                    }
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.top, 8)
                                        .padding(.bottom, 78) // Espacio para que el último canal nunca quede tapado
                                    }
                                }
                            }
                            .coordinateSpace(name: "channelScroll")
                            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { newOffset in
                                let delta = newOffset - lastScrollOffset
                                if delta < -10 {
                                    // Scroll hacia abajo: ocultar el menú suavemente estilo YouTube
                                    if isBottomBarVisible {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            isBottomBarVisible = false
                                        }
                                    }
                                } else if delta > 10 || newOffset > -20 {
                                    // Scroll hacia arriba o cerca del inicio: volver a mostrar el menú
                                    if !isBottomBarVisible {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            isBottomBarVisible = true
                                        }
                                    }
                                }
                                lastScrollOffset = newOffset
                            }
                        }

                        // 4. Barra Inferior Estilo YouTube con Separación y Auto-Hide en Scroll
                        VStack(spacing: 0) {
                            // Línea divisoria superior que separa claramente el menú del fondo y tarjetas
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 1)

                            HStack(alignment: .center, spacing: 0) {
                                ForEach(FilterTab.allCases, id: \.self) { tab in
                                    let isTabActive = (iptv.activeTab == tab)
                                    let badgeCount: Int? = {
                                        if tab == .favorites { return iptv.favoriteIds.count }
                                        if tab == .recent { return iptv.recentIds.count }
                                        return nil
                                    }()

                                    Button(action: {
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            iptv.activeTab = tab
                                            isBottomBarVisible = true
                                        }
                                    }) {
                                        VStack(spacing: 4) {
                                            ZStack(alignment: .topTrailing) {
                                                TabIconView(tab: tab, isSelected: isTabActive, size: 24)
                                                    .padding(.top, 4)

                                                if let count = badgeCount, count > 0 {
                                                    Text("\(count)")
                                                        .font(.system(size: 9, weight: .black))
                                                        .foregroundColor(isTabActive ? Theme.navyBg : Theme.textWhite)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(isTabActive ? Theme.yellow : Theme.cardHover)
                                                        .clipShape(Capsule())
                                                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                                                        .offset(x: 14, y: -2)
                                                }
                                            }
                                            .frame(height: 26)

                                            Text(tab.rawValue)
                                                .font(.system(size: 10, weight: isTabActive ? .bold : .medium))
                                                .foregroundColor(isTabActive ? Theme.yellow : Theme.textMuted)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 6)
                        }
                        .background(
                            Theme.cardBg
                                .shadow(color: Color.black.opacity(0.55), radius: 8, y: -3)
                        )
                        .offset(y: isBottomBarVisible ? 0 : 85)
                        .opacity(isBottomBarVisible ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.25), value: isBottomBarVisible)
                    }
                }
            }
            .edgesIgnoringSafeArea(isFullScreen ? .all : [])

            // 5. Drawer Lateral de Categorías
            if showDrawer {
                CategoriesDrawerView(iptv: iptv, isPresented: $showDrawer)
                    .transition(.move(edge: .leading))
                    .zIndex(100)
            }
        }
        .statusBar(hidden: isFullScreen)
        .sheet(isPresented: $showSettings) {
            SettingsView(iptv: iptv)
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
}

// MARK: - Settings Screen (Dark Navy #111827 & Yellow #FFC61A Minimalist Design)
struct SettingsView: View {
    @ObservedObject var iptv: IPTVManager
    @Environment(\.presentationMode) var presentationMode
    @State private var isPasswordVisible: Bool = false
    @State private var showConfirmClearRecents: Bool = false
    @State private var showConfirmClearFavorites: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                Theme.navyBg
                    .edgesIgnoringSafeArea(.all)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Sección: Modo de Vista (Lista vs Cuadrícula)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("VISTA DE CANALES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.textMuted)
                                .padding(.horizontal, 4)

                            HStack(spacing: 12) {
                                Button(action: { iptv.isGridView = false }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "list.bullet")
                                            .font(.system(size: 14, weight: .bold))
                                        Text("Lista")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(!iptv.isGridView ? Theme.yellow : Theme.cardBg)
                                    .foregroundColor(!iptv.isGridView ? Theme.navyBg : Theme.textWhite)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(!iptv.isGridView ? Theme.yellow : Theme.border, lineWidth: 1)
                                    )
                                }

                                Button(action: { iptv.isGridView = true }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "square.grid.2x2")
                                            .font(.system(size: 14, weight: .bold))
                                        Text("Cuadrícula")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(iptv.isGridView ? Theme.yellow : Theme.cardBg)
                                    .foregroundColor(iptv.isGridView ? Theme.navyBg : Theme.textWhite)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(iptv.isGridView ? Theme.yellow : Theme.border, lineWidth: 1)
                                    )
                                }
                            }
                        }

                        // Sección: Perfil Actual
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PERFIL ACTUAL")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.textMuted)
                                .padding(.horizontal, 4)

                            VStack(spacing: 14) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(Theme.yellowMuted)
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(Theme.yellow)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(iptv.username.isEmpty ? "Usuario IPTV" : iptv.username)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(Theme.textWhite)
                                        Text(iptv.cleanServerUrl(iptv.serverUrl))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Theme.textMuted)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text("ACTIVO")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(Theme.navyBg)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Theme.yellow)
                                        .cornerRadius(8)
                                }

                                Divider()
                                    .background(Theme.border)

                                HStack(spacing: 12) {
                                    Button(action: { showConfirmClearRecents = true }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.system(size: 12))
                                            Text("Borrar Recientes")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .foregroundColor(Theme.textMuted)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Theme.navyBg)
                                        .cornerRadius(8)
                                    }

                                    Button(action: { showConfirmClearFavorites = true }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "star.slash")
                                                .font(.system(size: 12))
                                            Text("Borrar Favoritos")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .foregroundColor(Theme.textMuted)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Theme.navyBg)
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(16)
                            .background(Theme.cardBg)
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
                        }

                        // Sección: Credenciales del Servidor
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CONFIGURACIÓN DE SERVIDOR")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.textMuted)
                                .padding(.horizontal, 4)

                            VStack(spacing: 12) {
                                // Campo Servidor
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("URL del Servidor")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Theme.textMuted)
                                    HStack(spacing: 10) {
                                        Image(systemName: "link")
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.yellow)
                                        TextField("http://servidor:puerto", text: $iptv.serverUrl)
                                            .font(.system(size: 14))
                                            .foregroundColor(Theme.textWhite)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .keyboardType(.URL)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Theme.navyBg)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                                }

                                // Campo Usuario
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Usuario")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Theme.textMuted)
                                    HStack(spacing: 10) {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.yellow)
                                        TextField("Tu usuario", text: $iptv.username)
                                            .font(.system(size: 14))
                                            .foregroundColor(Theme.textWhite)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Theme.navyBg)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                                }

                                // Campo Contraseña
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Contraseña")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Theme.textMuted)
                                    HStack(spacing: 10) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.yellow)
                                        if isPasswordVisible {
                                            TextField("Tu contraseña", text: $iptv.password)
                                                .font(.system(size: 14))
                                                .foregroundColor(Theme.textWhite)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                        } else {
                                            SecureField("Tu contraseña", text: $iptv.password)
                                                .font(.system(size: 14))
                                                .foregroundColor(Theme.textWhite)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                        }

                                        Button(action: { isPasswordVisible.toggle() }) {
                                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(Theme.textMuted)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Theme.navyBg)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                                }
                            }
                            .padding(16)
                            .background(Theme.cardBg)
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
                        }

                        // Botón de Acción Principal (Amarillo #FFC61A)
                        Button(action: {
                            iptv.fetchChannels()
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14, weight: .black))
                                Text("Guardar y Conectar")
                                    .font(.system(size: 15, weight: .black))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.yellow)
                            .foregroundColor(Theme.navyBg)
                            .cornerRadius(14)
                            .shadow(color: Theme.yellow.opacity(0.35), radius: 10, y: 4)
                        }
                        .padding(.top, 6)

                        Spacer(minLength: 24)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitle("Ajustes", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.textWhite)
                },
                trailing: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Listo")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.yellow)
                }
            )
        }
        .alert(isPresented: $showConfirmClearRecents) {
            Alert(
                title: Text("Borrar Recientes"),
                message: Text("¿Deseas vaciar la lista de canales vistos recientemente?"),
                primaryButton: .destructive(Text("Borrar")) { iptv.clearRecents() },
                secondaryButton: .cancel()
            )
        }
    }
}
