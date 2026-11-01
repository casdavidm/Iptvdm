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
    @Published var password: String = UserDefaults.standard.string(forKey: "xc_pass") ?? "" {
        didSet { UserDefaults.standard.set(password, forKey: "xc_pass") }
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

// MARK: - Native Player with Resilient Buffer, Global User-Agent & Watchdog
struct NativePlayerView: UIViewControllerRepresentable {
    let streamUrl: String

    class Coordinator: NSObject {
        var currentUrl: String = ""
        weak var player: AVPlayer?
        private var stallObserver: Any?
        private var endObserver: Any?
        private var statusObserver: NSKeyValueObservation?
        private var keepUpObserver: NSKeyValueObservation?
        private var timeControlObserver: NSKeyValueObservation?
        private var timeObserver: Any?
        private var lastTimeSeconds: Double = -1.0
        private var stallCounter: Int = 0

        func setupItem(_ item: AVPlayerItem, for player: AVPlayer) {
            cleanItemObservers()

            // 1. Observer para cuando se atasca por microcorte de red (Stalled)
            stallObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: item,
                queue: .main
            ) { [weak self, weak player] _ in
                player?.currentItem?.seek(to: .positiveInfinity, completionHandler: { _ in
                    player?.play()
                })
            }

            // 2. En streams en vivo, si el reproductor alcanza el fin del buffer de fragmentos
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                player?.currentItem?.seek(to: .positiveInfinity, completionHandler: { _ in
                    player?.play()
                })
            }

            // 3. Observar cuando el buffer vuelve a ser suficiente
            keepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak player] item, _ in
                if item.isPlaybackLikelyToKeepUp {
                    player?.play()
                }
            }

            // 4. Observar cuando el item esté listo
            statusObserver = item.observe(\.status, options: [.new]) { [weak player] item, _ in
                if item.status == .readyToPlay {
                    player?.play()
                }
            }

            // 5. Watchdog de tiempo real: detecta si la imagen se congela a los 27s
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1, preferredTimescale: 2),
                queue: .main
            ) { [weak self, weak player] time in
                guard let self = self, let player = player else { return }
                let currentSec = time.seconds

                // Si el tiempo no avanza pero el player debería estar reproduciendo
                if currentSec > 0 && abs(currentSec - self.lastTimeSeconds) < 0.1 {
                    self.stallCounter += 1
                    // Si lleva más de 2 segundos congelado en la misma posición:
                    if self.stallCounter >= 2 {
                        self.stallCounter = 0
                        player.currentItem?.seek(to: .positiveInfinity, completionHandler: { _ in
                            player.play()
                        })
                    }
                } else {
                    self.stallCounter = 0
                    self.lastTimeSeconds = currentSec
                }
            }
        }

        func cleanItemObservers() {
            if let obs = stallObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
            if let tObs = timeObserver, let p = player {
                p.removeTimeObserver(tObs)
            }
            stallObserver = nil
            endObserver = nil
            timeObserver = nil
            statusObserver?.invalidate()
            statusObserver = nil
            keepUpObserver?.invalidate()
            keepUpObserver = nil
            timeControlObserver?.invalidate()
            timeControlObserver = nil
            lastTimeSeconds = -1.0
            stallCounter = 0
        }

        deinit {
            cleanItemObservers()
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
        if context.coordinator.currentUrl != streamUrl {
            context.coordinator.currentUrl = streamUrl
            
            // 1. IMPORTANTE: Detener completamente el stream anterior para que el servidor
            // Xtream no detecte conexiones concurrentes duplicadas y corte la línea a los 27s
            context.coordinator.player?.pause()
            context.coordinator.player?.replaceCurrentItem(with: nil)
            context.coordinator.cleanItemObservers()
            
            guard let url = URL(string: streamUrl) else { return }
            
            // 2. User-Agent a nivel GLOBAL de la sesión y de los fragmentos HLS:
            // - AVURLAssetHTTPHeaderFieldsKey: usado en la petición inicial
            // - AVURLAssetHTTPUserAgentKey: propaga el User-Agent a CADA segmento .ts y recarga de playlist
            let userAgent = "IPTVSmartersPro/3.1.5"
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent],
                "AVURLAssetHTTPUserAgentKey": userAgent
            ]
            let asset = AVURLAsset(url: url, options: options)
            let item = AVPlayerItem(asset: asset)
            
            // 3. Buffer dinámico continuo sin tope artificial
            item.preferredForwardBufferDuration = 0
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = true
            
            context.coordinator.player = player
            context.coordinator.setupItem(item, for: player)
            
            uiViewController.player = player
            player.play()
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.cleanItemObservers()
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
    }
}

// MARK: - Main User Interface
struct ContentView: View {
    @StateObject private var iptv = IPTVManager()
    @State private var showSettings = false
    @State private var useTsFormat = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                ZStack {
                    if let selected = iptv.selectedChannel {
                        NativePlayerView(streamUrl: useTsFormat ? selected.tsUrl : selected.hlsUrl)
                            .background(Color.black)
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
                    Button(action: { useTsFormat.toggle() }) {
                        Text(useTsFormat ? "TS" : "HLS")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.2))
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