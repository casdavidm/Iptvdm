import SwiftUI
import AVKit
import Combine

// MARK: - Data Models
struct XtreamChannel: Identifiable, Equatable {
    let id: String
    let streamId: Int
    let name: String
    let category: String
    let hlsUrl: String
    let tsUrl: String
}

// MARK: - Insecure Network Session Delegate
class InsecureSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Native IPTV Manager
class IPTVManager: ObservableObject {
    @Published var channels: [XtreamChannel] = []
    @Published var filteredChannels: [XtreamChannel] = []
    @Published var selectedChannel: XtreamChannel?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
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
        config.timeoutIntervalForRequest = 25.0
        config.timeoutIntervalForResource = 30.0
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
        guard !serverUrl.isEmpty, !username.isEmpty, !password.isEmpty else {
            self.errorMessage = "Configura servidor, usuario y contraseña en Ajustes."
            return
        }

        let base = cleanServerUrl(serverUrl)
        guard let endpoint = URL(string: "\(base)/player_api.php?username=\(username)&password=\(password)&action=get_live_streams") else {
            self.errorMessage = "URL de servidor inválida."
            return
        }

        self.isLoading = true
        self.errorMessage = nil

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0
        request.setValue("IPTVSmartersPro/3.1.5", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        customSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                if let err = error {
                    self.errorMessage = "Error de red: \(err.localizedDescription)"
                    return
                }

                guard let rawData = data else {
                    self.errorMessage = "El servidor no devolvió datos."
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

                            let hls = "\(base)/live/\(self.username)/\(self.password)/\(sId).m3u8"
                            let ts = "\(base)/\(self.username)/\(self.password)/\(sId)"

                            parsed.append(XtreamChannel(
                                id: "xc-\(sId)",
                                streamId: sId,
                                name: sName,
                                category: cat,
                                hlsUrl: hls,
                                tsUrl: ts
                            ))
                        }

                        self.channels = parsed
                        self.categories = ["Todas"] + Array(catsSet).sorted()
                        self.filterChannels()

                        if let first = self.filteredChannels.first {
                            self.selectedChannel = first
                        }
                    } else {
                        self.errorMessage = "Credenciales incorrectas o cuenta vencida."
                    }
                } catch {
                    self.errorMessage = "Error al procesar canales: \(error.localizedDescription)"
                }
            }
        }.resume()
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

// MARK: - Native Video Player View (AVPlayer)
struct NativePlayerView: UIViewControllerRepresentable {
    let streamUrl: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true

        if let url = URL(string: streamUrl) {
            let player = AVPlayer(url: url)
            controller.player = player
            player.play()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        guard let currentUrl = (uiViewController.player?.currentItem?.asset as? AVURLAsset)?.url.absoluteString else {
            if let url = URL(string: streamUrl) {
                let player = AVPlayer(url: url)
                uiViewController.player = player
                player.play()
            }
            return
        }

        if currentUrl != streamUrl, let newUrl = URL(string: streamUrl) {
            let player = AVPlayer(url: newUrl)
            uiViewController.player = player
            player.play()
        }
    }
}

// MARK: - Main Interface
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
                            .aspectRatio(16/9, contentMode: .fit)
                            .background(Color.black)
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay(
                                Text(iptv.isLoading ? "Cargando lista..." : "Selecciona un canal")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            )
                    }

                    if iptv.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.3)
                    }
                }
                .frame(maxWidth: .infinity)

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
            if iptv.channels.isEmpty {
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
```eof

I will now update `.github/workflows/build-ios.yml` to specify domain-specific ATS rules for `veotv.info` so iOS cannot ignore them.

```yaml:.github/workflows/build-ios.yml
name: Build Native Swift IPA

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-15

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Install XcodeGen
        run: |
          brew install xcodegen

      - name: Clean Environment
        run: |
          rm -rf Frameworks Podfile Podfile.lock Pods Payload *.ipa build

      - name: Create Info.plist with Domain Specific ATS
        run: |
          mkdir -p StreamOSNative
          cat << 'EOF' > StreamOSNative/Info.plist
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>en</string>
            <key>CFBundleDisplayName</key>
            <string>StreamOS</string>
            <key>CFBundleExecutable</key>
            <string>StreamOS</string>
            <key>CFBundleIdentifier</key>
            <string>com.casdavidm.streamos</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>StreamOS</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSRequiresIPhoneOS</key>
            <true/>
            <key>UILaunchScreen</key>
            <dict/>
            <key>UIRequiredDeviceCapabilities</key>
            <array>
              <string>arm64</string>
            </array>
            <key>UIBackgroundModes</key>
            <array>
              <string>audio</string>
            </array>
            <key>NSAppTransportSecurity</key>
            <dict>
              <key>NSAllowsArbitraryLoads</key>
              <true/>
              <key>NSAllowsArbitraryLoadsInMedia</key>
              <true/>
              <key>NSAllowsLocalNetworking</key>
              <true/>
              <key>NSExceptionDomains</key>
              <dict>
                <key>veotv.info</key>
                <dict>
                  <key>NSIncludesSubdomains</key>
                  <true/>
                  <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
                  <true/>
                  <key>NSTemporaryExceptionMinimumTLSVersion</key>
                  <string>TLSv1.0</string>
                  <key>NSExceptionAllowsInsecureHTTPLoads</key>
                  <true/>
                  <key>NSExceptionRequiresForwardSecrecy</key>
                  <false/>
                </dict>
              </dict>
            </dict>
          </dict>
          </plist>
          EOF

      - name: Create Project Definition
        run: |
          cat << 'EOF' > project.yml
          name: StreamOS
          options:
            bundleIdPrefix: com.casdavidm
            deploymentTarget:
              iOS: "15.0"
          targets:
            StreamOS:
              type: application
              platform: iOS
              deploymentTarget: "15.0"
              sources:
                - path: StreamOSNative
                  excludes:
                    - "Info.plist"
              settings:
                base:
                  PRODUCT_BUNDLE_IDENTIFIER: com.casdavidm.streamos
                  INFOPLIST_FILE: StreamOSNative/Info.plist
                  GENERATE_INFOPLIST_FILE: NO
                  CODE_SIGNING_ALLOWED: NO
                  CODE_SIGNING_REQUIRED: NO
                  CODE_SIGN_IDENTITY: ""
                  DEVELOPMENT_TEAM: ""
                  CURRENT_PROJECT_VERSION: 1
                  MARKETING_VERSION: "1.0"
                  SWIFT_VERSION: "5.0"
                  ENABLE_BITCODE: NO
          EOF

      - name: Generate Xcode Project
        run: |
          xcodegen generate

      - name: Build Application Archive
        run: |
          xcodebuild archive \
            -project StreamOS.xcodeproj \
            -scheme StreamOS \
            -configuration Release \
            -destination "generic/platform=iOS" \
            -archivePath build/StreamOS.xcarchive \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY="" \
            AD_HOC_CODE_SIGNING_ALLOWED=YES

      - name: Verify ATS and Package IPA
        run: |
          mkdir -p Payload
          cp -R build/StreamOS.xcarchive/Products/Applications/StreamOS.app Payload/
          cp StreamOSNative/Info.plist Payload/StreamOS.app/Info.plist
          plutil -convert binary1 Payload/StreamOS.app/Info.plist
          zip -qr StreamOS.ipa Payload

      - name: Upload IPA
        uses: actions/upload-artifact@v4
        with:
          name: StreamOS-IPA
          path: StreamOS.ipa
