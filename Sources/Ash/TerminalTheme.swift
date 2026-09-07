import AppKit
import SwiftTerm
import SwiftUI

enum TerminalTheme {
    static func background(for scheme: ColorScheme) -> NSColor {
        scheme == .dark
            ? NSColor(red: 0.115, green: 0.122, blue: 0.12, alpha: 1)
            : color(0xF8F8F6)
    }

    static func apply(_ scheme: ColorScheme, to view: TerminalView) {
        let dark = scheme == .dark
        let background = background(for: scheme)
        let foreground =
            dark
            ? NSColor(red: 0.89, green: 0.9, blue: 0.87, alpha: 1)
            : color(0x303630)
        view.nativeBackgroundColor = background
        view.nativeForegroundColor = foreground
        view.caretColor =
            dark
            ? NSColor(red: 0.88, green: 0.66, blue: 0.38, alpha: 1)
            : color(0x94633F)
        view.caretTextColor = background
        view.selectedTextBackgroundColor = color(dark ? 0x485344 : 0xDCE4D7)
        view.selectedTextForegroundColor = foreground
        // Keep explicit RGB and the standard xterm 256-color cube intact.
        // Darker ANSI accents remain legible on the light terminal surface.
        view.installColors(
            dark
                ? SwiftTerm.Color.terminalAppColors
                : lightANSI.map { value in
                    SwiftTerm.Color(
                        red: UInt16((value >> 16) & 0xFF) * 257,
                        green: UInt16((value >> 8) & 0xFF) * 257,
                        blue: UInt16(value & 0xFF) * 257)
                })
    }

    private static let lightANSI: [UInt32] = [
        0x303630, 0xAE322D, 0x356B38, 0x806000,
        0x315BA8, 0x88478F, 0x176D77, 0xC8CEC6,
        0x626A61, 0xBE3932, 0x427844, 0x8C6900,
        0x3969B5, 0x98519E, 0x207984, 0xFFFFFF,
    ]

    private static func color(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
