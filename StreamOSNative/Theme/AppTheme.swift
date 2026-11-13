import SwiftUI
import UIKit

// MARK: - Paleta de colores estricta (compartida con DM/FM Radio)

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// Fondo principal: Azul oscuro #111827
    static let appBackground = Color(hex: 0x111827)

    /// Contenedores y tarjetas: #1F2937
    static let appCard = Color(hex: 0x1F2937)

    /// Borde sutil para tarjetas y divisores: #374151
    static let appBorder = Color(hex: 0x374151)

    /// Acento y elementos activos: Amarillo #ffc61a
    static let appAccent = Color(hex: 0xFFC61A)

    /// Tipografía principal: Blanco #ffffff
    static let appTextPrimary = Color.white

    /// Tipografía secundaria y diales: Gris #9CA3AF
    static let appTextSecondary = Color(hex: 0x9CA3AF)
}

// MARK: - Tipografía retro-moderna

extension Font {
    /// Tipografía condensada estilo dial de radio clásica
    static func retro(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight).width(.condensed)
    }
}

// MARK: - Formas auxiliares

/// Triángulo apuntando hacia arriba (aguja del dial)
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Feedback háptico

func hapticTap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    let generator = UIImpactFeedbackGenerator(style: style)
    generator.prepare()
    generator.impactOccurred()
}

/// Oculta el teclado desde cualquier vista
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
