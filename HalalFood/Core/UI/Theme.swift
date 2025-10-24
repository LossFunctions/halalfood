import SwiftUI

// Centralized theme so brand, neutrals, and halal status colors are consistent.
enum Theme {
    enum Colors {
        // Brand and neutrals
        static let accent = Color(named: "BrandAccent", bundle: nil, fallback: Color.teal)
        static let background = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let text = Color.primary
        static let textSecondary = Color.secondary
        static let outline = Color.black.opacity(0.06)
        static let shadow = Color.black
        static let imagePlaceholder = Color.gray.opacity(0.3)

        // Halal status (reserved for badges/indicators only)
        static let halalFull = Color(hex: 0x2E7D32)      // green
        static let halalPartial = Color(hex: 0xE67E22)   // orange
    }
}

// MARK: - Halal status types
enum HalalStatus { case full, partial }

struct StatusBadge: View {
    let status: HalalStatus
    var body: some View {
        let (label, fg, bg) = switch status {
        case .full: ("HALAL", Theme.Colors.halalFull, Theme.Colors.halalFull.opacity(0.12))
        case .partial: ("PARTIAL", Theme.Colors.halalPartial, Theme.Colors.halalPartial.opacity(0.12))
        }
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .overlay(
                Capsule().stroke(fg.opacity(0.4), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

// MARK: - Utilities
extension Color {
    /// Fallback-friendly color asset loader. If the asset does not exist, uses `default`.
    init(named name: String, bundle: Bundle? = nil, fallback: Color) {
        if UIColor(named: name, in: bundle, compatibleWith: nil) != nil {
            self = Color(name, bundle: bundle)
        } else {
            self = fallback
        }
    }

    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }
}
