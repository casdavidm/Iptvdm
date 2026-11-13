import SwiftUI

// MARK: - Modificadores neumórficos (relieve e inserción) sobre la paleta oscura

/// Superficie en relieve: luz suave arriba-izquierda y sombra profunda abajo-derecha
struct NeumorphicRaised<S: InsettableShape>: ViewModifier {
    let shape: S
    var fill: Color = .appCard
    var shadowRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(
                shape
                    .fill(fill)
                    .shadow(color: Color.black.opacity(0.55), radius: shadowRadius, x: shadowRadius * 0.6, y: shadowRadius * 0.6)
                    .shadow(color: Color.white.opacity(0.06), radius: shadowRadius * 0.8, x: -shadowRadius * 0.4, y: -shadowRadius * 0.4)
            )
            .overlay(shape.strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1))
    }
}

/// Superficie hundida: sombra interior que simula una pista o un plato de dial
struct NeumorphicInset<S: InsettableShape>: ViewModifier {
    let shape: S
    var fill: Color = .appBackground

    func body(content: Content) -> some View {
        content
            .background(
                shape.fill(
                    fill
                        .shadow(.inner(color: Color.black.opacity(0.65), radius: 6, x: 4, y: 4))
                        .shadow(.inner(color: Color.white.opacity(0.05), radius: 6, x: -3, y: -3))
                )
            )
            .overlay(shape.strokeBorder(Color.appBorder.opacity(0.5), lineWidth: 1))
    }
}

extension View {
    func neumorphicRaised<S: InsettableShape>(_ shape: S, fill: Color = .appCard, shadowRadius: CGFloat = 10) -> some View {
        modifier(NeumorphicRaised(shape: shape, fill: fill, shadowRadius: shadowRadius))
    }

    func neumorphicInset<S: InsettableShape>(_ shape: S, fill: Color = .appBackground) -> some View {
        modifier(NeumorphicInset(shape: shape, fill: fill))
    }
}

// MARK: - Botón circular en relieve (cabeceras y acciones rápidas)

struct RetroCircleButton: View {
    let icon: String
    var size: CGFloat = 42
    var iconSize: CGFloat = 16
    var isActive: Bool = false
    var label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(isActive ? Color.appBackground : Color.appTextPrimary)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .neumorphicRaised(Circle(), fill: isActive ? Color.appAccent : Color.appCard, shadowRadius: 7)
        .accessibilityLabel(label)
    }
}

// MARK: - Rejilla de altavoz circular (estados vacíos)

struct SpeakerGrilleView: View {
    var size: CGFloat
    var stripeSpacing: CGFloat = 7
    var stripeHeight: CGFloat = 3

    private var stripeCount: Int {
        max(1, Int(size / (stripeSpacing + stripeHeight)))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.appCard)
                .shadow(color: Color.black.opacity(0.6), radius: 20, x: 12, y: 14)
                .shadow(color: Color.white.opacity(0.05), radius: 14, x: -8, y: -8)

            VStack(spacing: stripeSpacing) {
                ForEach(0..<stripeCount, id: \.self) { _ in
                    Capsule()
                        .fill(Color.appBackground)
                        .frame(height: stripeHeight)
                }
            }
            .frame(width: size * 0.92, height: size * 0.92)
            .clipShape(Circle())

            Circle()
                .strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Píldora de estado "En vivo"

struct LiveBadge: View {
    let isPlaying: Bool
    var isBuffering: Bool = false

    private var label: String {
        if isBuffering { return "Sintonizando" }
        return isPlaying ? "En vivo" : "En pausa"
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(isPlaying ? Color.appAccent.opacity(0.35) : Color.clear)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(isPlaying || isBuffering ? Color.appAccent : Color.appTextSecondary.opacity(0.6))
                    .frame(width: 8, height: 8)
            }

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.appTextPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .neumorphicRaised(Capsule(), shadowRadius: 6)
    }
}

// MARK: - Etiqueta de sección (AHORA SUENA, CATEGORÍAS…)

struct SectionLabel: View {
    let text: String
    var color: Color = .appTextSecondary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(2)
            .foregroundColor(color)
    }
}

// MARK: - Cabecera: menú · logo · ajustes

struct RetroHeader: View {
    let onMenu: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack {
            RetroCircleButton(icon: "line.3.horizontal", iconSize: 17, label: "Categorías", action: onMenu)

            Spacer()

            AppLogoView(height: 24)

            Spacer()

            RetroCircleButton(icon: "gearshape", iconSize: 15, label: "Ajustes", action: onSettings)
        }
    }
}

// MARK: - Barra de pestañas inferior en cápsula flotante

struct RetroTabBar: View {
    @Binding var selected: FilterTab
    var badge: (FilterTab) -> Int? = { _ in nil }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FilterTab.allCases, id: \.self) { tab in
                let isSelected = selected == tab
                let count = badge(tab) ?? 0

                Button(action: {
                    hapticTap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selected = tab
                    }
                }) {
                    VStack(spacing: 7) {
                        ZStack(alignment: .topTrailing) {
                            TabIconView(tab: tab, isSelected: isSelected, size: 22)

                            if count > 0 {
                                Text(count > 99 ? "99+" : "\(count)")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(Color.appBackground)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.appAccent))
                                    .offset(x: 12, y: -6)
                            }
                        }
                        .frame(height: 24)

                        Circle()
                            .fill(Color.appAccent)
                            .frame(width: 5, height: 5)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 10)
        .padding(.horizontal, 24)
        .background(
            Capsule(style: .continuous)
                .fill(Color.appCard)
                .shadow(color: Color.black.opacity(0.55), radius: 16, x: 0, y: 8)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1)
        )
    }
}

// MARK: - Logo DMTV

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
                        .font(.retro(height * 0.8, weight: .black))
                        .foregroundColor(Color.appAccent)
                    Rectangle()
                        .fill(Color.appAccent)
                        .frame(width: 2, height: height * 0.7)
                    Text("TV")
                        .font(.retro(height * 0.8, weight: .black))
                        .foregroundColor(Color.appTextPrimary)
                }
            }
        }
        .accessibilityLabel("DM TV")
    }
}

// MARK: - Iconos personalizados de pestañas

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
                    .foregroundColor(isSelected ? Color.appAccent : Color.appTextSecondary)
            } else {
                Image(systemName: fallbackSymbol(for: tab))
                    .font(.system(size: size * 0.9, weight: .regular))
                    .foregroundColor(isSelected ? Color.appAccent : Color.appTextSecondary)
            }
        }
    }

    private func fallbackSymbol(for tab: FilterTab) -> String {
        switch tab {
        case .all: return "square.stack.3d.up"
        case .favorites: return "star"
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Logo de canal en plato hundido

struct ChannelLogoView: View {
    let logoUrl: String?
    var size: CGFloat = 56
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    Color.appBackground
                        .shadow(.inner(color: Color.black.opacity(0.65), radius: 5, x: 3, y: 3))
                        .shadow(.inner(color: Color.white.opacity(0.05), radius: 4, x: -2, y: -2))
                )

            if let logo = logoUrl, let url = URL(string: logo) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: size * 0.6, height: size * 0.6)
                    default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(isSelected ? Color.appAccent.opacity(0.7) : Color.appBorder.opacity(0.6), lineWidth: 1)
        )
    }

    private var fallbackIcon: some View {
        Image(systemName: "tv")
            .font(.system(size: size * 0.32))
            .foregroundColor(isSelected ? Color.appAccent : Color.appTextSecondary)
    }
}

// MARK: - Estado vacío con rejilla

struct EmptyStateView: View {
    let icon: String
    let title: String
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                SpeakerGrilleView(size: 96, stripeSpacing: 5, stripeHeight: 2)
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(Color.appTextSecondary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.appBackground))
                    .overlay(Circle().strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1))
            }

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let hint = hint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextSecondary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Seguimiento de desplazamiento para ocultar la barra inferior

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
