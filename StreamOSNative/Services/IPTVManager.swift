import SwiftUI
import Combine

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
    @Published var username: String = UserDefaults.standard.string(forKey: "xc_user") ?? "" {
        didSet { UserDefaults.standard.set(username, forKey: "xc_user") }
    }
    @Published var password: String = UserDefaults.standard.string(forKey: "xc_pass") ?? "" {
        didSet { UserDefaults.standard.set(password, forKey: "xc_pass") }
    }

    init() {
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
