import SwiftUI

// MARK: - Tarjeta de canal (lista), estilo retro-moderno

struct ChannelListRow: View {
    let channel: XtreamChannel
    let isSelected: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    /// Toca la tarjeta: selecciona el canal
    let onSelect: () -> Void
    /// Toca el botón circular: reproduce o pausa el canal actual, o selecciona otro
    let onPlayTapped: () -> Void
    let onToggleFavorite: () -> Void

    private var isActive: Bool { isSelected && isPlaying }

    var body: some View {
        HStack(spacing: 14) {
            ChannelLogoView(logoUrl: channel.logoUrl, size: 56, isSelected: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.retro(17))
                    .foregroundColor(isSelected ? Color.appAccent : Color.appTextPrimary)
                    .lineLimit(1)

                Text(channel.category)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.appTextSecondary)
                    .lineLimit(1)

                if isSelected {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isPlaying ? Color.appAccent : Color.appTextSecondary)
                            .frame(width: 6, height: 6)
                        Text(isPlaying ? "EN VIVO" : "EN PAUSA")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundColor(isPlaying ? Color.appAccent : Color.appTextSecondary)
                    }
                }
            }

            Spacer(minLength: 4)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundColor(isFavorite ? Color.appAccent : Color.appTextSecondary.opacity(0.7))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Quitar de favoritos" : "Añadir a favoritos")

            Button(action: onPlayTapped) {
                Image(systemName: isActive ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isActive ? Color.appBackground : Color.appAccent)
                    .offset(x: isActive ? 0 : 1)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .neumorphicRaised(Circle(), fill: isActive ? Color.appAccent : Color.appCard, shadowRadius: 6)
            .accessibilityLabel(isActive ? "Pausar" : "Reproducir")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .neumorphicRaised(RoundedRectangle(cornerRadius: 22, style: .continuous), shadowRadius: 9)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.appAccent.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Tarjeta de canal (cuadrícula)

struct ChannelGridCard: View {
    let channel: XtreamChannel
    let isSelected: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ChannelLogoView(logoUrl: channel.logoUrl, size: 46, isSelected: isSelected)

                Spacer()

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(isFavorite ? Color.appAccent : Color.appTextSecondary.opacity(0.7))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Quitar de favoritos" : "Añadir a favoritos")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.retro(15))
                    .foregroundColor(isSelected ? Color.appAccent : Color.appTextPrimary)
                    .lineLimit(2)
                    .frame(height: 36, alignment: .topLeading)

                HStack(spacing: 6) {
                    Text(channel.category)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.appTextSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if isSelected {
                        Circle()
                            .fill(isPlaying ? Color.appAccent : Color.appTextSecondary)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(14)
        .neumorphicRaised(RoundedRectangle(cornerRadius: 22, style: .continuous), shadowRadius: 9)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.appAccent.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
