import AppKit
import SwiftUI

/// Quiet, shared surfaces for both native appearances. Terminal ANSI colors stay independent.
enum AshStyle {
    static let accent = adaptive("accent", light: 0x94633F, dark: 0xC99B73)
    static let canvas = adaptive("canvas", light: 0xF8F8F6, dark: 0x232624)
    static let sidebar = adaptive("sidebar", light: 0xEFF0ED, dark: 0x1E211F)
    static let surface = adaptive("surface", light: 0xFFFFFF, dark: 0x2B2E2B)
    static let chrome = adaptive("chrome", light: 0xF2F3F0, dark: 0x202320)
    static let selection = adaptive("selection", light: 0xE5E7E1, dark: 0x383D36)
    static let hover = Color.primary.opacity(0.045)
    static let line = Color.primary.opacity(0.09)
    static let success = adaptive("success", light: 0x58725A, dark: 0x91AD8C)
    static let toolbarHeight: CGFloat = 32
    static let statusHeight: CGFloat = 28
    static let radius: CGFloat = 8

    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: NSColor.Name("Ash.\(name)")) { appearance in
                let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255, alpha: 1)
            })
    }
}

let ashAccent = AshStyle.accent

struct AshHairline: View {
    var body: some View { Rectangle().fill(AshStyle.line).frame(height: 1).accessibilityHidden(true) }
}

struct AshKeycap: View {
    let key: String
    var body: some View {
        Text(key).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary).padding(.horizontal, 6).frame(height: 22)
            .background(AshStyle.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(AshStyle.line))
    }
}

private struct AshHover: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    let selected: Bool
    var selectionOpacity: Double = 1
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: AshStyle.radius)
                .fill(
                    selected
                        ? AshStyle.selection.opacity(selectionOpacity) : hovering && enabled ? AshStyle.hover : .clear)
        }.onHover { hovering = $0 }
    }
}

extension View {
    func ashHover(selected: Bool = false) -> some View { modifier(AshHover(selected: selected)) }
    func ashField() -> some View {
        background(AshStyle.surface, in: RoundedRectangle(cornerRadius: AshStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: AshStyle.radius).strokeBorder(AshStyle.line))
    }
    func ashTab(selected: Bool) -> some View {
        modifier(AshHover(selected: selected, selectionOpacity: 0.55))
            .overlay(alignment: .bottom) {
                Capsule().fill(selected ? ashAccent.opacity(0.8) : .clear).frame(height: 1).padding(.horizontal, 12)
            }
    }
}

struct AshIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary).opacity(enabled ? 1 : 0.4)
            .background(
                configuration.isPressed ? AshStyle.selection : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .ashHover()
    }
}
