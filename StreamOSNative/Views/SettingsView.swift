import SwiftUI

/// Ajustes: vista de canales, perfil, credenciales del servidor
struct SettingsView: View {
    @ObservedObject var iptv: IPTVManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPasswordVisible: Bool = false
    @State private var activeAlert: SettingsAlert? = nil

    enum SettingsAlert: Identifiable {
        case clearRecents
        case clearFavorites

        var id: Int {
            switch self {
            case .clearRecents: return 0
            case .clearFavorites: return 1
            }
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Barra superior
                HStack {
                    RetroCircleButton(icon: "chevron.down", label: "Cerrar") {
                        dismissKeyboard()
                        dismiss()
                    }

                    Spacer()

                    Text("AJUSTES")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(3)
                        .foregroundColor(Color.appTextPrimary)

                    Spacer()

                    Color.clear.frame(width: 42, height: 42)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        viewModeCard
                        profileCard
                        serverCard

                        // MARK: - Acción principal
                        Button(action: {
                            hapticTap(.medium)
                            dismissKeyboard()
                            iptv.fetchChannels()
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Guardar y conectar")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.appBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .neumorphicRaised(Capsule(), fill: Color.appAccent, shadowRadius: 8)

                        aboutCard
                    }
                    .padding(20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .clearRecents:
                return Alert(
                    title: Text("Borrar recientes"),
                    message: Text("¿Deseas vaciar la lista de canales vistos recientemente?"),
                    primaryButton: .destructive(Text("Borrar")) { iptv.clearRecents() },
                    secondaryButton: .cancel()
                )
            case .clearFavorites:
                return Alert(
                    title: Text("Borrar favoritos"),
                    message: Text("¿Deseas quitar todos los canales de tus favoritos?"),
                    primaryButton: .destructive(Text("Borrar")) { iptv.clearFavorites() },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    // MARK: - Vista de canales

    private var viewModeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Vista de canales", color: .appAccent)

            HStack(spacing: 12) {
                viewModeButton(icon: "list.bullet", title: "Lista", isSelected: !iptv.isGridView) {
                    iptv.isGridView = false
                }
                viewModeButton(icon: "square.grid.2x2", title: "Cuadrícula", isSelected: iptv.isGridView) {
                    iptv.isGridView = true
                }
            }
        }
        .padding(18)
        .neumorphicRaised(RoundedRectangle(cornerRadius: 26, style: .continuous), shadowRadius: 12)
    }

    private func viewModeButton(icon: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            hapticTap()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(isSelected ? Color.appBackground : Color.appTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .neumorphicRaised(Capsule(), fill: isSelected ? Color.appAccent : Color.appCard, shadowRadius: 6)
    }

    // MARK: - Perfil actual

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Perfil actual", color: .appAccent)

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.appBackground)
                    Text(initials)
                        .font(.retro(16))
                        .foregroundColor(Color.appAccent)
                }
                .frame(width: 46, height: 46)
                .overlay(Circle().strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(iptv.username.isEmpty ? "Usuario IPTV" : iptv.username)
                        .font(.retro(16))
                        .foregroundColor(Color.appTextPrimary)
                        .lineLimit(1)
                    Text(iptv.cleanServerUrl(iptv.serverUrl))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.appTextSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(iptv.channels.isEmpty ? "SIN CANALES" : "ACTIVO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(iptv.channels.isEmpty ? Color.appTextSecondary : Color.appAccent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.appBackground))
                    .overlay(Capsule().strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1))
            }

            HStack(spacing: 12) {
                clearButton(icon: "clock.arrow.circlepath", title: "Borrar recientes", count: iptv.recentIds.count) {
                    activeAlert = .clearRecents
                }
                clearButton(icon: "star.slash", title: "Borrar favoritos", count: iptv.favoriteIds.count) {
                    activeAlert = .clearFavorites
                }
            }
        }
        .padding(18)
        .neumorphicRaised(RoundedRectangle(cornerRadius: 26, style: .continuous), shadowRadius: 12)
    }

    private var initials: String {
        let letters = iptv.username.prefix(2).uppercased()
        return letters.isEmpty ? "TV" : letters
    }

    private func clearButton(icon: String, title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(Color.appTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .neumorphicInset(Capsule())
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
    }

    // MARK: - Servidor

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Configuración de servidor", color: .appAccent)

            Text("Datos de tu cuenta Xtream Codes. Si el API no responde, se intenta la lista M3U automáticamente.")
                .font(.system(size: 13))
                .foregroundColor(Color.appTextSecondary)

            field(label: "URL del servidor", icon: "link") {
                TextField("http://servidor:puerto", text: $iptv.serverUrl)
                    .keyboardType(.URL)
            }

            field(label: "Usuario", icon: "person.fill") {
                TextField("Tu usuario", text: $iptv.username)
            }

            field(label: "Contraseña", icon: "lock.fill") {
                Group {
                    if isPasswordVisible {
                        TextField("Tu contraseña", text: $iptv.password)
                    } else {
                        SecureField("Tu contraseña", text: $iptv.password)
                    }
                }

                Button(action: { isPasswordVisible.toggle() }) {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.appTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña")
            }
        }
        .padding(18)
        .neumorphicRaised(RoundedRectangle(cornerRadius: 26, style: .continuous), shadowRadius: 12)
    }

    private func field<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(Color.appTextSecondary)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.appAccent)

                content()
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextPrimary)
                    .tint(Color.appAccent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .neumorphicInset(Capsule())
        }
    }

    // MARK: - Acerca de

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Acerca de", color: .appAccent)

            AppLogoView(height: 26)

            Text("Reproductor IPTV nativo con soporte Xtream Codes y M3U, favoritos, historial y categorías.")
                .font(.system(size: 13))
                .foregroundColor(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .neumorphicRaised(RoundedRectangle(cornerRadius: 26, style: .continuous), shadowRadius: 12)
    }
}
