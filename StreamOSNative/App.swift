import SwiftUI
import AVFoundation

@main
struct StreamOSApp: App {
    init() {
        // Desactivar caché HTTP persistente para asegurar que los segmentos y manifiestos HLS se descarguen siempre en tiempo real
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio error: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
