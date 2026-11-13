import SwiftUI

/// Pantalla del televisor: reproductor con controles superpuestos.
/// En vertical es una tarjeta redondeada en relieve; en pantalla completa ocupa todo.
struct VideoPlayerCardView: View {
    let channel: XtreamChannel?
    @Binding var isPlaying: Bool
    let isFullScreen: Bool
    let showControls: Bool
    let isLoading: Bool
    let statusMessage: String
    let onToggleControls: () -> Void
    let onTogglePlay: () -> Void
    let onToggleFullScreen: () -> Void
    let onResync: () -> Void

    private var cornerRadius: CGFloat { isFullScreen ? 0 : 24 }

    var body: some View {
        ZStack {
            if let selected = channel {
                #if canImport(MobileVLCKit)
                VLCPlayerView(streamUrl: selected.tsUrl, isPlaying: $isPlaying)
                    .background(Color.black)
                #else
                NativePlayerView(streamUrl: selected.hlsUrl, isPlaying: $isPlaying)
                    .background(Color.black)
                #endif

                // Superficie transparente activa para detectar toques
                Color.black.opacity(showControls ? 0.45 : 0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggleControls)

                if showControls {
                    controlsOverlay(for: selected)
                        .transition(.opacity)
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isFullScreen ? nil : (UIScreen.main.bounds.width - 32) * 9 / 16)
        .frame(maxHeight: isFullScreen ? .infinity : nil)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.appBorder.opacity(isFullScreen ? 0 : 0.8), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isFullScreen ? 0 : 0.6), radius: 18, x: 8, y: 12)
        .shadow(color: Color.white.opacity(isFullScreen ? 0 : 0.05), radius: 12, x: -6, y: -6)
    }

    // MARK: - Controles superpuestos

    private func controlsOverlay(for selected: XtreamChannel) -> some View {
        VStack(spacing: 0) {
            // Barra superior: nombre, estado y pantalla completa
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selected.name)
                        .font(.retro(isFullScreen ? 22 : 17))
                        .foregroundColor(Color.appTextPrimary)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.9), radius: 4)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(isPlaying ? Color.appAccent : Color.appTextSecondary)
                            .frame(width: 7, height: 7)
                        Text(isPlaying ? "EN VIVO" : "EN PAUSA")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundColor(isPlaying ? Color.appAccent : Color.appTextSecondary)
                        Text("·")
                            .foregroundColor(Color.appTextSecondary)
                        Text(selected.category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.appTextPrimary.opacity(0.85))
                            .lineLimit(1)
                    }
                    .shadow(color: .black.opacity(0.9), radius: 4)
                }

                Spacer()

                overlayCircleButton(
                    icon: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    label: isFullScreen ? "Salir de pantalla completa" : "Pantalla completa",
                    action: onToggleFullScreen
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, isFullScreen ? 44 : 14)

            Spacer()

            // Botón central Play / Pausa
            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: isFullScreen ? 32 : 26, weight: .bold))
                    .foregroundColor(Color.appBackground)
                    .offset(x: isPlaying ? 0 : 2)
                    .frame(width: isFullScreen ? 84 : 68, height: isFullScreen ? 84 : 68)
            }
            .buttonStyle(.plain)
            .neumorphicRaised(Circle(), fill: Color.appAccent, shadowRadius: 12)
            .accessibilityLabel(isPlaying ? "Pausar" : "Reproducir")

            Spacer()

            // Barra inferior: sincronizar y pantalla completa
            HStack {
                overlayPill(icon: "arrow.clockwise", text: "Sincronizar en vivo", action: onResync)

                Spacer()

                overlayPill(
                    icon: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "viewfinder",
                    text: isFullScreen ? "Salir" : "Pantalla completa",
                    action: onToggleFullScreen
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, isFullScreen ? 34 : 14)
        }
    }

    private func overlayCircleButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.appTextPrimary)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .neumorphicRaised(Circle(), fill: Color.black.opacity(0.7), shadowRadius: 6)
        .accessibilityLabel(label)
    }

    private func overlayPill(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(text)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(Color.appTextPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .neumorphicRaised(Capsule(), fill: Color.black.opacity(0.7), shadowRadius: 6)
    }

    // MARK: - Sin canal seleccionado

    private var placeholder: some View {
        ZStack {
            Color.black

            VStack(spacing: 14) {
                ZStack {
                    SpeakerGrilleView(size: 84, stripeSpacing: 5, stripeHeight: 2)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.appAccent))
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Color.appBackground))
                            .overlay(Circle().strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1))
                    } else {
                        Image(systemName: "play.tv")
                            .font(.system(size: 20))
                            .foregroundColor(Color.appTextSecondary)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Color.appBackground))
                            .overlay(Circle().strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1))
                    }
                }

                Text(isLoading ? statusMessage : "Selecciona un canal para comenzar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.appTextSecondary)
            }
        }
    }
}
