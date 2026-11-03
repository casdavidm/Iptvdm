import SwiftUI
import AVKit
import Combine

struct XtreamChannel: Identifiable, Equatable {
    let id: String
    let streamId: String
    let name: String
    let category: String
    let hlsUrl: String
    let tsUrl: String
}

class InsecureSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

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
        // Desactivar caché para forzar a descargar listas frescas sin congelarse
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
    }

    private lazy var customSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 45.0
        config.timeoutIntervalForResource = 60.0
        return URLSession(configuration: config, delegate: InsecureSessionDelegate(), delegateQueue: nil)
    }()

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

            // Si el servidor devolvió un error HTTP (ej: 401, 403, 404, 500)
            if statusCode != 200 && statusCode != 0 {
                DispatchQueue.main.async {
                    self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "Servidor respondió con código \(statusCode)")
                }
                return
            }

            // Caso 1: Array JSON con canales de Xtream
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
                    if let nameMatch = sName.range(of: "^[A-Za-z0-9\\s]{2,10}[|:\\-]", options: .regularExpression) {
                        cat = String(sName[nameMatch].dropLast()).trimmingCharacters(in: .whitespaces)
                    }
                    catsSet.insert(cat)

                    let hls = "\(base)/live/\(cleanUser)/\(cleanPass)/\(streamIdStr).m3u8"
                    let ts = "\(base)/\(cleanUser)/\(cleanPass)/\(streamIdStr)"

                    parsed.append(XtreamChannel(
                        id: "xc-\(streamIdStr)",
                        streamId: streamIdStr,
                        name: sName,
                        category: cat,
                        hlsUrl: hls,
                        tsUrl: ts
                    ))
                }

                DispatchQueue.main.async {
                    self.isLoading = false
                    if !parsed.isEmpty {
                        self.channels = parsed
                        self.categories = ["Todas"] + Array(catsSet).sorted()
                        self.filterChannels()
                        self.selectedChannel = parsed.first
                        self.statusMessage = "\(parsed.count) canales cargados"
                    } else {
                        self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "La lista de canales en el servidor está vacía")
                    }
                }
                return
            }

            // Caso 2: Objeto JSON devuelto por Xtream con información de error o autenticación
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
                    self.errorMessage = "Error 404: Servidor o credenciales no encontrados. Verifica Servidor, Usuario y Contraseña en Ajustes."
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

                // Exigir formato M3U real (debe contener #EXTM3U o #EXTINF), NO solo 'http'
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

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("#EXTINF:") {
                // Extraer categoría (group-title)
                if let groupRange = trimmed.range(of: "group-title=\"([^\"]+)\"", options: .regularExpression) {
                    let fullMatch = String(trimmed[groupRange])
                    tempCat = fullMatch.replacingOccurrences(of: "group-title=\"", with: "").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                } else if let groupRange2 = trimmed.range(of: "group-title='([^']+)'", options: .regularExpression) {
                    let fullMatch = String(trimmed[groupRange2])
                    tempCat = fullMatch.replacingOccurrences(of: "group-title='", with: "").replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
                }

                // Extraer nombre del canal
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
                    tsUrl: ts
                ))
                catsSet.insert(finalCat)
                tempName = ""
                tempCat = "General"

                if parsed.count >= 2500 { break }
            }
        }

        if !parsed.isEmpty {
            self.channels = parsed
            self.categories = ["Todas"] + Array(catsSet).sorted()
            self.filterChannels()
            self.selectedChannel = parsed.first
            self.statusMessage = "\(parsed.count) canales cargados"
        } else {
            self.errorMessage = "No se encontraron canales válidos en la lista M3U. Verifica tus datos en Ajustes."
        }
    }

    func filterChannels() {
        var result = channels
        if selectedCategory != "Todas" {
            result = result.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        self.filteredChannels = result
    }
}

// MARK: - VLC Player (MobileVLCKit) - Motor Profesional para MPEG-TS sin Cortes
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
            // Buffer y sincronización continua para streams en vivo MPEG-TS
            media.addOptions([
                "network-caching": 2500,
                ":network-caching": 2500,
                ":clock-jitter": 0,
                ":clock-synchro": 0,
                ":http-user-agent": "IPTVSmartersPro/3.1.5"
            ])
            mediaPlayer.media = media
            mediaPlayer.play()

            DispatchQueue.main.async {
                self.parent.isPlaying = true
            }
        }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            DispatchQueue.main.async {
                self.parent.isPlaying = self.mediaPlayer.isPlaying
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
        context.coordinator.playStream(url: streamUrl)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if context.coordinator.currentUrl != streamUrl {
            context.coordinator.playStream(url: streamUrl)
        } else {
            if isPlaying && !context.coordinator.mediaPlayer.isPlaying {
                context.coordinator.mediaPlayer.play()
            } else if !isPlaying && context.coordinator.mediaPlayer.isPlaying {
                context.coordinator.mediaPlayer.pause()
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.mediaPlayer.stop()
        coordinator.mediaPlayer.drawable = nil
    }
}
#endif

// MARK: - Native Player with Respected Pause & Smooth Continuous Playback
struct NativePlayerView: UIViewControllerRepresentable {
    let streamUrl: String

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

            // 1. Manejador de microcortes de red: reanuda inmediatamente si el usuario no pausó
            stallObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                p.playImmediately(atRate: 1.0)
            }

            // 2. Si el reproductor alcanza el fin del buffer de fragmentos disponibles
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                guard let p = player else { return }
                if p.timeControlStatus == .paused || p.rate == 0 { return }
                // Reanudación inmediata sin seek para no purgar el decodificador ni causar pantalla negra
                p.playImmediately(atRate: 1.0)
            }

            startWatchdog(for: player)
        }

        func startWatchdog(for player: AVPlayer) {
            stopWatchdog()

            watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self, weak player] _ in
                guard let self = self, let player = player else { return }

                // REGLA FUNDAMENTAL: Si el usuario pausó la reproducción, se respeta al 100%
                if player.timeControlStatus == .paused || player.rate == 0 {
                    self.stallSeconds = 0
                    return
                }

                let currentItemTime = player.currentTime().seconds
                let isWaiting = (player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                let isFrozen = (currentItemTime > 0 && abs(currentItemTime - self.lastObservedTime) < 0.05)

                if isWaiting || isFrozen {
                    self.stallSeconds += 2.0

                    // Nivel 1: A los 6 segundos de congelamiento, avance suave sin pantalla negra
                    if self.stallSeconds >= 6.0 && self.stallSeconds < 14.0 {
                        self.smoothRecoverLiveEdge(player: player)
                    } else if self.stallSeconds >= 14.0 {
                        // Nivel 2: Solo si el stream estuvo muerto por más de 14s, reconexión de seguridad
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
            // Reanudación inmediata en el pipeline actual sin destruir la vista
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
        return Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Asegurar que use siempre formato HLS compatible con iOS
        var targetUrl = streamUrl
        if targetUrl.hasSuffix(".ts") {
            targetUrl = String(targetUrl.dropLast(3)) + ".m3u8"
        }

        if context.coordinator.currentUrl != targetUrl {
            context.coordinator.currentUrl = targetUrl

            // 1. Detener por completo el stream y observadores anteriores
            context.coordinator.stopWatchdog()
            context.coordinator.cleanObservers()
            context.coordinator.player?.pause()
            context.coordinator.player?.replaceCurrentItem(with: nil)

            guard let url = URL(string: targetUrl) else { return }

            // 2. User-Agent a nivel de conexión y fragmentos:
            let userAgent = "IPTVSmartersPro/3.1.5"
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent],
                "AVURLAssetHTTPUserAgentKey": userAgent
            ]
            let asset = AVURLAsset(url: url, options: options)
            let item = AVPlayerItem(asset: asset)
            // Buffer adelantado de 10s: absorbe microcortes y evita pausas entre fragmentos
            item.preferredForwardBufferDuration = 10.0
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = true

            context.coordinator.setup(player: player, streamUrl: targetUrl)

            uiViewController.player = player
            player.play()
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

// MARK: - Main User Interface
struct ContentView: View {
    @StateObject private var iptv = IPTVManager()
    @State private var showSettings = false
    @State private var isPlaying: Bool = true
    @State private var showControls: Bool = false
    @State private var controlsTimer: Timer? = nil

    func resetControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = false
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                ZStack {
                    if let selected = iptv.selectedChannel {
                        #if canImport(MobileVLCKit)
                        // Con MobileVLCKit transmitimos directo el flujo MPEG-TS sin cortes
                        VLCPlayerView(streamUrl: selected.tsUrl, isPlaying: $isPlaying)
                            .background(Color.black)
                        #else
                        NativePlayerView(streamUrl: selected.hlsUrl)
                            .background(Color.black)
                        #endif

                        // Overlay de controles táctiles: tap para mostrar/ocultar Play/Pause
                        ZStack {
                            if showControls {
                                Color.black.opacity(0.35)
                                    .transition(.opacity)

                                Button(action: {
                                    isPlaying.toggle()
                                    resetControlsTimer()
                                }) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white)
                                        .shadow(radius: 8)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                            if showControls {
                                resetControlsTimer()
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .overlay(
                                VStack(spacing: 6) {
                                    if iptv.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        Text(iptv.statusMessage)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    } else {
                                        Text("Selecciona un canal")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                }
                            )
                    }
                }
                .frame(height: UIScreen.main.bounds.width * 9 / 16)
                .frame(maxWidth: .infinity)
                .background(Color.black)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(iptv.selectedChannel?.name ?? "StreamOS")
                            .font(.headline)
                            .lineLimit(1)
                        Text(iptv.selectedChannel?.category ?? "En vivo")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: {
                        // Re-sincronizar el canal actual con el borde en vivo
                        if let current = iptv.selectedChannel {
                            iptv.selectedChannel = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                iptv.selectedChannel = current
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                            Text("EN VIVO")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.18))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                    }
                    Button(action: { iptv.fetchChannels() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(iptv.categories, id: \.self) { cat in
                            Button(action: { iptv.selectedCategory = cat }) {
                                Text(cat)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(iptv.selectedCategory == cat ? Color.red : Color(.secondarySystemBackground))
                                    .foregroundColor(iptv.selectedCategory == cat ? .white : .primary)
                                    .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Buscar canal...", text: $iptv.searchText)
                        .font(.subheadline)
                    if !iptv.searchText.isEmpty {
                        Button(action: { iptv.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 4)

                if let err = iptv.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.largeTitle)
                        Text(err)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Button("Abrir Ajustes") {
                            showSettings = true
                        }
                        .font(.caption.bold())
                        .foregroundColor(.red)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(iptv.filteredChannels) { channel in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name)
                                    .font(.subheadline)
                                    .foregroundColor(iptv.selectedChannel?.id == channel.id ? .red : .primary)
                                    .lineLimit(1)
                                Text(channel.category)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if iptv.selectedChannel?.id == channel.id {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            iptv.selectedChannel = channel
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationBarTitle("StreamOS", displayMode: .inline)
            .navigationBarItems(trailing: Button(action: { showSettings = true }) {
                Image(systemName: "gear")
            })
            .sheet(isPresented: $showSettings) {
                SettingsView(iptv: iptv)
            }
        }
        .onAppear {
            if iptv.channels.isEmpty && !iptv.password.isEmpty {
                iptv.fetchChannels()
            }
        }
    }
}

// MARK: - Settings Screen
struct SettingsView: View {
    @ObservedObject var iptv: IPTVManager
    @Environment(\.presentationMode) var presentationMode
    @State private var isPasswordVisible: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("Servidor Xtream"),
                    footer: Text("Asegúrate de incluir el protocolo (http://) y el puerto (:8880 u otro) si tu proveedor lo requiere.")
                ) {
                    TextField("Servidor (ej: http://veotv.info:8880)", text: $iptv.serverUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)

                    TextField("Usuario", text: $iptv.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    HStack {
                        if isPasswordVisible {
                            TextField("Contraseña", text: $iptv.password)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("Contraseña", text: $iptv.password)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }

                        Button(action: { isPasswordVisible.toggle() }) {
                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }

                Section {
                    Button(action: {
                        iptv.fetchChannels()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("Guardar y Sincronizar")
                                .bold()
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationBarTitle("Ajustes", displayMode: .inline)
            .navigationBarItems(trailing: Button("Cerrar") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}