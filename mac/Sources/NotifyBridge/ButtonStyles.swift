import SwiftUI

let nbTeal = Color(red: 0.23, green: 0.69, blue: 0.72)
let nbGreen = Color(red: 0.25, green: 0.77, blue: 0.56)

enum NBKind { case primary, secondary, danger }

/// Pill buttons: the main action uses the logo gradient, others are soft capsules, destructive ones are red-tinted.
struct PillButtonStyle: ButtonStyle {
    var kind: NBKind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, compact: compact)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: NBKind
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .lineLimit(1)
                .fixedSize()   // never wrap the label: the button grows instead
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .padding(.horizontal, compact ? 12 : 18).padding(.vertical, compact ? 6 : 10)
                .foregroundColor(kind == .primary ? .white : (kind == .danger ? .red : .primary))
                .background(background)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(kind == .primary ? Color.clear : Color.primary.opacity(hovering ? 0.22 : 0.14), lineWidth: 1))
                .shadow(color: kind == .primary ? nbTeal.opacity(hovering ? 0.55 : 0.4) : .clear, radius: 9, y: 4)
                .brightness(hovering && enabled ? 0.04 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }

        private var background: AnyShapeStyle {
            switch kind {
            case .primary:
                return AnyShapeStyle(LinearGradient(colors: [nbTeal, nbGreen], startPoint: .leading, endPoint: .trailing))
            case .secondary:
                return AnyShapeStyle(Color.primary.opacity(hovering ? 0.10 : 0.06))
            case .danger:
                return AnyShapeStyle(Color.red.opacity(hovering ? 0.16 : 0.10))
            }
        }
    }
}
