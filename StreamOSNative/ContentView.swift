import SwiftUI
import Combine

struct XtreamChannel: Identifiable, Codable, Equatable {
    let id: String
    let streamId: Int
    let name: String
    let category: String
    let streamUrl: String
    let tsUrl: String
}

class IPTVManager: ObservableObject {
    @Published var channels: [XtreamChannel] = []
    @Published var filteredChannels: [XtreamChannel] = []
    @Published var selectedChannel: XtreamChannel?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var searchText: String = "" {
        didSet { filterChannels() }
    }
    @Published var selectedCategory: String = "All" {
        didSet { filterChannels() }
    }
    @Published var categories: [String] = ["All"]

    @AppStorage("xc_server") var serverUrl: String = "http://veotv.info:8880"
    @AppStorage("xc_user") var username: String = "DavidMunoz1"
    @AppStorage("xc_pass") var password: String = ""

    func cleanServerUrl(_ url: String) -> String {
        var cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("/") { cleaned.removeLast() }
        if !cleaned.lowercased().hasPrefix("http://") && !cleaned.lowercased().hasPrefix("https://") {
            cleaned = "http://" + cleaned
        }
        return cleaned
    }

    func fetchChannels() {
        guard !serverUrl.isEmpty, !username.isEmpty, !password.isEmpty else {
            self.errorMessage = "Ingresa servidor, usuario y contraseña"
            return
        }

        let base = cleanServerUrl(serverUrl)
        guard let endpoint = URL(string: "\(base)/player_api.php?username=\(username)&password=\(password)&action=get_live_streams") else {
            self.errorMessage = "URL no válida"
            return
        }

        self.isLoading = true
        self.errorMessage = nil

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 25.0
        request.setValue("IPTVSmartersPro/3.1.5", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let err = error {
                    self?.errorMessage = "Error de conexión: \(err.localizedDescription)"
                    return
                }

                guard let rawData = data else {
                    self?.errorMessage = "Respuesta vacía del servidor"
                    return
                }

                do {
                    if let rawArray = try JSONSerialization.jsonObject(with: rawData) as? [[String: Any]] {
                        var parsed: [XtreamChannel] = []
                        var catsSet = Set<String>()

                        for item in rawArray {
                            guard let sId = item["stream_id"] as? Int,
                                  let sName = item["name"] as? String else { continue }

                            var cat = "General"
                            if let nameMatch = sName.range(of: "^[A-Za-z0-9\\s]{2,10}[|:\\-]", options: .regularExpression) {
                                cat = String(sName[nameMatch].dropLast()).trimmingCharacters(in: .whitespaces)
                            }
                            catsSet.insert(cat)

                            let hlsUrl = "\(base)/live/\(self?.username ?? "")/\(self?.password ?? "")/\(sId).m3u8"
                            let tsUrl = "\(base)/\(self?.username ?? "")/\(self?.password ?? "")/\(sId)"

                            parsed.append(XtreamChannel(
                                id: "xc-\(sId)",
                                streamId: sId,
                                name: sName,
                                category: cat,
                                streamUrl: hlsUrl,
                                tsUrl: tsUrl
                            ))
                        }

                        self?.channels = parsed
                        self?.categories = ["All"] + Array(catsSet).sorted()
                        self?.filterChannels()

                        if let first = self?.filteredChannels.first {
                            self?.selectedChannel = first
                        }
                    } else {
                        self?.errorMessage = "Credenciales incorrectas o servidor ocupado"
                    }
                } catch {
                    self?.errorMessage = "Error al procesar: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    func filterChannels() {
        var result = channels
        if selectedCategory != "All" {
            result = result.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        self.filteredChannels = result
    }
}

#if canImport(MobileVLCKit)
import MobileVLCKit

struct VLCPlayerView: UIViewRepresentable {
    let url: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.mediaPlayer.drawable = view
        playStream(context: context)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if context.coordinator.currentUrl != url {
            playStream(context: context)
        }
    }

    private func playStream(context: Context) {
        guard let streamUrl = URL(string: url) else { return }
        context.coordinator.currentUrl = url
        let media = VLCMedia(url: streamUrl)
        media.addOptions([
            "network-caching": 1500,
            ":network-caching=1500",
            ":clock-jitter=0",
            ":clock-synchro=0"
        ])
        context.coordinator.mediaPlayer.media = media
        context.coordinator.mediaPlayer.play()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        var mediaPlayer: VLCMediaPlayer = VLCMediaPlayer()
        var currentUrl: String = ""
        deinit { mediaPlayer.stop() }
    }
}
#else
struct VLCPlayerView: View {
    let url: String
    var body: some View {
        ZStack {
            Color.black
            VStack {
                Image(systemName: "tv")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                Text("VLC Player Engine")
                    .foregroundColor(.gray)
            }
        }
    }
}
#endif

struct ContentView: View {
    @StateObject private var iptv = IPTVManager()
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack {
                    if let selected = iptv.selectedChannel {
                        VLCPlayerView(url: selected.tsUrl)
                            .aspectRatio(16/9, contentMode: .fit)
                            .background(Color.black)
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay(Text("Selecciona un canal").foregroundColor(.gray))
                    }

                    if iptv.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
                .frame(maxWidth: .infinity)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(iptv.selectedChannel?.name ?? "StreamOS")
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(iptv.selectedChannel?.category ?? "VLC Engine")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: { iptv.fetchChannels() }) {
                        Image(systemName: "arrow.clockwise")
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
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Buscar canal...", text: $iptv.searchText)
                    if !iptv.searchText.isEmpty {
                        Button(action: { iptv.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 4)

                if let err = iptv.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            if iptv.channels.isEmpty {
                iptv.fetchChannels()
            }
        }
    }
}

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
                    SecureField("Contraseña", text: $iptv.password)
                }

                Section {
                    Button(action: {
                        iptv.fetchChannels()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("Conectar y Sincronizar")
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
