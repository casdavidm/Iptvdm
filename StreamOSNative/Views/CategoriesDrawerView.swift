import SwiftUI

/// Cajón lateral de categorías con el lenguaje visual retro-moderno
struct CategoriesDrawerView: View {
    @ObservedObject var iptv: IPTVManager
    @Binding var isPresented: Bool
    @State private var categoryFilter: String = ""

    private var filteredCategories: [String] {
        if categoryFilter.isEmpty {
            return iptv.categories
        }
        return iptv.categories.filter { $0.localizedCaseInsensitiveContains(categoryFilter) }
    }

    private func close() {
        dismissKeyboard()
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Cabecera
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        AppLogoView(height: 26)
                        Text("IPTV PLAYER")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(Color.appTextSecondary)
                    }

                    Spacer()

                    RetroCircleButton(icon: "xmark", size: 38, iconSize: 14, label: "Cerrar", action: close)
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 20)

                // MARK: - Título y buscador hundido
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel(text: "Categorías")
                        Spacer()
                        Text("\(iptv.categories.count)")
                            .font(.retro(14))
                            .foregroundColor(Color.appAccent)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(categoryFilter.isEmpty ? Color.appTextSecondary : Color.appAccent)

                        TextField("Buscar categoría…", text: $categoryFilter)
                            .font(.system(size: 13))
                            .foregroundColor(Color.appTextPrimary)
                            .tint(Color.appAccent)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if !categoryFilter.isEmpty {
                            Button(action: { categoryFilter = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.appTextSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Borrar búsqueda")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .neumorphicInset(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                // MARK: - Lista de categorías
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredCategories, id: \.self) { cat in
                            let isSelected = (iptv.selectedCategory == cat && iptv.activeTab == .all)
                            let count = iptv.count(for: cat)

                            Button(action: {
                                hapticTap()
                                iptv.activeTab = .all
                                iptv.selectedCategory = cat
                                close()
                            }) {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(isSelected ? Color.appAccent : Color.clear)
                                        .frame(width: 4, height: 24)

                                    Text(cat)
                                        .font(.retro(15, weight: isSelected ? .bold : .semibold))
                                        .foregroundColor(isSelected ? Color.appAccent : Color.appTextPrimary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("\(count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(isSelected ? Color.appBackground : Color.appTextSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(isSelected ? Color.appAccent : Color.appBackground))
                                        .overlay(Capsule().strokeBorder(Color.appBorder.opacity(isSelected ? 0 : 0.6), lineWidth: 1))
                                }
                                .padding(.leading, 8)
                                .padding(.trailing, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isSelected ? Color.appCard : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .padding(.bottom, 30)
                }
            }
            .frame(width: 290)
            .background(Color.appBackground)
            .overlay(
                Rectangle()
                    .fill(Color.appBorder.opacity(0.6))
                    .frame(width: 1),
                alignment: .trailing
            )
            .shadow(color: Color.black.opacity(0.6), radius: 24, x: 8, y: 0)

            // Fondo semitransparente que descarta al tocar
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
        }
        .ignoresSafeArea(edges: .vertical)
    }
}
