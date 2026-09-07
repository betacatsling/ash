import AppKit
import SwiftUI

enum TerminalShortcutAction: String, CaseIterable, Identifiable {
    case terminal1, terminal2, terminal3, terminal4, terminal5, terminal6, terminal7, terminal8, terminal9
    case previous, next

    var id: String { rawValue }
    // One settings row controls the entire numbered family.
    static var settingsActions: [Self] { [.terminal1, .previous, .next] }
    var settingsTitle: String { index == nil ? title : "按编号切换终端" }
    var index: Int? { Int(rawValue.replacingOccurrences(of: "terminal", with: "")).map { $0 - 1 } }
    var title: String {
        if let index { return "选中第 \(index + 1) 个终端" }
        return self == .previous ? "切换到左侧终端" : "切换到右侧终端"
    }
    var defaultShortcut: TerminalShortcut {
        if let index { return TerminalShortcut(key: String(index + 1)) }
        return TerminalShortcut(key: self == .previous ? "left" : "right", option: true)
    }
}

struct TerminalShortcut: Codable, Equatable {
    var key: String
    var command = true
    var option = false
    var control = false
    var shift = false

    func withKey(_ key: String) -> Self {
        var result = self
        result.key = key
        return result
    }
    var numberedLabel: String { withKey("1").label + "–9" }
    static func migratePreferences(_ saved: [String: Self]) -> [String: Self] {
        var result = saved.filter { ["previous", "next"].contains($0.key) }
        // Old individually recorded nonnumeric keys cannot represent a numbered family.
        let candidate = saved["numbered"] ?? saved["terminal1"] ?? .init(key: "1")
        let numbered =
            candidate.isValid && (1...9).contains(Int(candidate.key) ?? 0)
            ? candidate.withKey("1") : .init(key: "1")
        result["numbered"] = numbered
        for action in [TerminalShortcutAction.previous, .next] {
            if let shortcut = result[action.rawValue],
                !shortcut.isValid || shortcut.reservedAction != nil
                    || (1...9).contains(where: { numbered.withKey(String($0)) == shortcut })
            {
                result[action.rawValue] = nil
            }
        }
        let previous = result["previous"] ?? TerminalShortcutAction.previous.defaultShortcut
        let next = result["next"] ?? TerminalShortcutAction.next.defaultShortcut
        if previous == next {
            result["previous"] = nil
            result["next"] = nil
        }
        return result
    }

    var equivalent: KeyEquivalent {
        switch key {
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "up": return .upArrow
        case "down": return .downArrow
        default: return KeyEquivalent(key.first ?? " ")
        }
    }
    var modifiers: EventModifiers {
        var result: EventModifiers = []
        if command { result.insert(.command) }
        if option { result.insert(.option) }
        if control { result.insert(.control) }
        if shift { result.insert(.shift) }
        return result
    }
    var label: String {
        let symbol = ["left": "←", "right": "→", "up": "↑", "down": "↓"][key] ?? key.uppercased()
        return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + symbol
    }
    var isValid: Bool {
        (command || control)
            && (["left", "right", "up", "down"].contains(key)
                || (key.count == 1 && key.unicodeScalars.allSatisfy { (33...126).contains($0.value) }))
    }
    static func from(_ event: NSEvent) -> TerminalShortcut? {
        let arrows: [UInt16: String] = [123: "left", 124: "right", 125: "down", 126: "up"]
        // Strip Option and Shift so symbols such as ⌥2 and ⇧1 use the same key as the menu.
        guard let key = arrows[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.lowercased() else {
            return nil
        }
        let flags = event.modifierFlags
        let shortcut = TerminalShortcut(
            key: key, command: flags.contains(.command), option: flags.contains(.option),
            control: flags.contains(.control), shift: flags.contains(.shift))
        return shortcut.isValid ? shortcut : nil
    }

    var reservedAction: String? {
        let reserved: [(TerminalShortcut, String)] = [
            (.init(key: "o"), "打开文件夹"), (.init(key: "n", shift: true), "新建工作区"),
            (.init(key: "t"), "新建终端"), (.init(key: "n"), "新建 Agent 任务"),
            (.init(key: ","), "设置"), (.init(key: "f"), "查找终端内容"),
            (.init(key: "d"), "分屏"), (.init(key: "i", option: true), "右边栏"),
            (.init(key: "h", shift: true), "管理主机"), (.init(key: "+"), "放大字体"),
            (.init(key: "=", shift: true), "放大字体"), (.init(key: "-"), "缩小字体"),
            (.init(key: "q"), "退出"), (.init(key: "w"), "关闭当前标签页"),
            (.init(key: "m"), "最小化"), (.init(key: "h"), "隐藏应用"),
            (.init(key: "h", option: true), "隐藏其他应用"),
            (.init(key: "c"), "复制"), (.init(key: "v"), "粘贴"), (.init(key: "x"), "剪切"),
            (.init(key: "a"), "全选"), (.init(key: "z"), "撤销"), (.init(key: "z", shift: true), "重做"),
            (.init(key: "`"), "切换窗口"), (.init(key: "`", shift: true), "切换窗口"),
        ]
        return reserved.first { $0.0 == self }?.1
    }
}
