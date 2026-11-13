import SwiftUI

/// Barra "ahora suena" invertida en amarillo, bajo la pantalla del reproductor
struct NowPlayingBarView: View {
    let channel: XtreamChannel?
    let isPlaying: Bool
    let isLoading: Bool
    let isFavorite: Bool
    let onTogglePlay: () -> Void
    let onToggleFavorite: () -> Void
    let onExpand: () -> Void

    private var statusText: String {
        guard let channel = channel else {
            return isLoading ? "Cargando canales…" : "Elige un canal para empezar"
        }
        return isPlaying ? "En vivo · \(channel.category)" : "En pausa · \(channel.category)"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.appBackground)
                    .shadow(color: Color.black.opacity(0.35), radius: 6, x: 3, y: 3)

                if let logo = channel?.logoUrl, let url = URL(string: logo) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                        default:
                            placeholderIcon
                        }
                    }
                } else {
                    placeholderIcon
                }
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(channel?.name ?? "DM TV")
                    .font(.retro(17))
                    .foregroundColor(Color.appBackground)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.appBackground.opacity(isPlaying && channel != nil ? 1 : 0.4))
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.appBackground.opacity(0.75))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if channel != nil {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.appBackground.opacity(isFavorite ? 1 : 0.6))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Quitar de favoritos" : "Añadir a favoritos")

                Button(action: onTogglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(Color.appAccent)
                        .offset(x: isPlaying ? 0 : 1.5)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .background(
                    Circle()
                        .fill(Color.appBackground)
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 3, y: 3)
                )
                .accessibilityLabel(isPlaying ? "Pausar" : "Reproducir")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appAccent)
                .shadow(color: Color.black.opacity(0.6), radius: 14, x: 0, y: 8)
                .shadow(color: Color.appAccent.opacity(0.25), radius: 18, x: 0, y: 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if channel != nil { onExpand() }
        }
        .accessibilityHint("Abre el canal a pantalla completa")
    }

    private var placeholderIcon: some View {
        Image(systemName: "tv")
            .font(.system(size: 17))
            .foregroundColor(Color.appAccent)
    }
}
