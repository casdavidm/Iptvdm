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

    @AppStorage("xc_server") var serverUrl: String = "http://veotv.info:8880"
    @AppStorage("xc_user") var username: String = "DavidMunoz1"
    @AppStorage("xc_pass") var password: String = ""

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

        let apiEndpointStr = "\(base)/player_api.php?username=\(cleanUser)&password=\(cleanPass)&action=get_live_streams"
        guard let apiEndpoint = URL(string: apiEndpointStr) else {
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

            if let err = error {
                DispatchQueue.main.async {
                    self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: err.localizedDescription)
                }
                return
            }

            guard let rawData = data, !rawData.isEmpty else {
                DispatchQueue.main.async {
                    self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "Respuesta vacía")
                }
                return
            }

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
                        self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "Credenciales erróneas o cuenta vencida")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.fetchM3uFallback(base: base, user: cleanUser, pass: cleanPass, previousErr: "El servidor no respondió en formato JSON")
                }
            }
        }.resume()
    }

    func fetchM3uFallback(base: String, user: String, pass: String, previousErr: String) {
        self.statusMessage = "Descargando lista de canales..."

        let m3uUrlStr = "\(base)/get.php?username=\(user)&password=\(pass)&type=m3u_plus&output=ts"
        guard let m3uUrl = URL(string: m3uUrlStr) else {
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

                if let err = error {
                    self.errorMessage = "Error del servidor: \(err.localizedDescription)"
                    return
                }

                guard let rawData = data, let text = String(data: rawData, encoding: .utf8) ?? String(data: rawData, encoding: .isoLatin1) else {
                    self.errorMessage = "El servidor no envió datos válidos."
                    return
                }

                if text.contains("#EXTM3U") || text.contains("http") {
                    self.parseM3UContent(text, base: base, user: user, pass: pass)
                } else {
                    self.errorMessage = "Credenciales incorrectas o cuenta inactiva."
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
            if trimmed.hasPrefix("#EXTINF:") {
                if let groupRange = trimmed.range(of: "group-title=\"([^\"]+)\"", options: .regularExpression) {
                    let fullMatch = String(trimmed[groupRange])
                    tempCat = fullMatch.replacingOccurrences(of: "group-title=\"", with: "").replacingOccurrences(of: "\"", with: "")
                }
                if let commaIdx = trimmed.lastIndex(of: ",") {
                    tempName = String(trimmed[trimmed.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
                }
            } else if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                let id = "m3u-\(parsed.count + 1)"
                let streamUrl = trimmed
                let hls = streamUrl.contains(".m3u8") ? streamUrl : streamUrl.replacingOccurrences(of: ".ts", with: ".m3u8")
                let ts = streamUrl.contains(".m3u8") ? streamUrl.replacingOccurrences(of: ".m3u8", with: "") : streamUrl

                parsed.append(XtreamChannel(
                    id: id,
                    streamId: "\(parsed.count + 1)",
                    name: tempName.isEmpty ? "Canal \(parsed.count + 1)" : tempName,
                    category: tempCat,
                    hlsUrl: hls,
                    tsUrl: ts
                ))
                catsSet.insert(tempCat)
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
            self.errorMessage = "La lista recibida no contenía canales válidos."
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

// MARK: - Native Player with Coordinator (Solves the 20s Stop Issue)
struct NativePlayerView: UIViewControllerRepresentable {
    let streamUrl: String

    class Coordinator {
        var currentUrl: String = ""
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
        // Solo recrea el reproductor si la URL realmente cambió por petición del usuario
        if context.coordinator.currentUrl != streamUrl {
            context.coordinator.currentUrl = streamUrl
            if let url = URL(string: streamUrl) {
                let player = AVPlayer(url: url)
                uiViewController.player = player
                player.play()
            }
        }
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
                
                // Zona del reproductor (Soluciona el problema de tamaño)
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
                .frame(height: UIScreen.main.bounds.width * 9 / 16) // Mantiene la proporción perfecta 16:9 basado en el ancho
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

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Servidor Xtream")) {
                    TextField("Servidor", text: $iptv.serverUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Usuario", text: $iptv.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("Contraseña", text: $iptv.password)
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
