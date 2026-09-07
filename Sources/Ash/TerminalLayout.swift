import Foundation

enum TerminalSplitAxis: String, Codable, Hashable {
    case horizontal, vertical
}

enum TerminalDropSide: CaseIterable {
    case left, right, top, bottom

    var axis: TerminalSplitAxis { self == .left || self == .right ? .horizontal : .vertical }
    var insertsFirst: Bool { self == .left || self == .top }
    var label: String {
        switch self {
        case .left: return "放到左侧"
        case .right: return "放到右侧"
        case .top: return "放到上方"
        case .bottom: return "放到下方"
        }
    }
    var symbol: String { axis == .horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2" }

    /// The point and frame use a top-left origin, matching the layout geometry.
    static func nearest(to point: CGPoint, in frame: CGRect) -> Self? {
        guard frame.width > 0, frame.height > 0, frame.contains(point) else { return nil }
        let x = (point.x - frame.minX) / frame.width
        let y = (point.y - frame.minY) / frame.height
        return [(Self.left, x), (.right, 1 - x), (.top, y), (.bottom, 1 - y)]
            .min { $0.1 < $1.1 }?.0
    }
}

/// Kept in local client state. Older runtimes continue receiving the flat pane order.
indirect enum TerminalLayout: Codable, Hashable {
    case pane(String)
    case split(id: String, axis: TerminalSplitAxis, fraction: Double, first: TerminalLayout, second: TerminalLayout)

    var runIDs: [String] {
        switch self {
        case .pane(let id): return [id]
        case .split(_, _, _, let first, let second): return first.runIDs + second.runIDs
        }
    }

    static func horizontal(_ ids: [String]) -> Self? {
        guard let first = ids.first else { return nil }
        guard let rest = horizontal(Array(ids.dropFirst())) else { return .pane(first) }
        return .split(
            id: "legacy-\(first)", axis: .horizontal, fraction: 1 / Double(ids.count),
            first: .pane(first), second: rest)
    }

    static func arranged(_ ids: [String], axis: TerminalSplitAxis) -> Self? {
        guard let first = ids.first else { return nil }
        guard let rest = arranged(Array(ids.dropFirst()), axis: axis) else { return .pane(first) }
        return .split(
            id: UUID().uuidString, axis: axis, fraction: 1 / Double(ids.count), first: .pane(first), second: rest)
    }

    func keeping(_ ids: Set<String>) -> Self? {
        switch self {
        case .pane(let id): return ids.contains(id) ? self : nil
        case .split(let id, let axis, let fraction, let first, let second):
            switch (first.keeping(ids), second.keeping(ids)) {
            case (let a?, let b?): return .split(id: id, axis: axis, fraction: fraction, first: a, second: b)
            case (let a?, nil): return a
            case (nil, let b?): return b
            case (nil, nil): return nil
            }
        }
    }

    func replacing(_ target: String, with replacement: Self) -> Self {
        switch self {
        case .pane(let id): return id == target ? replacement : self
        case .split(let id, let axis, let fraction, let first, let second):
            return .split(
                id: id, axis: axis, fraction: fraction,
                first: first.replacing(target, with: replacement),
                second: second.replacing(target, with: replacement))
        }
    }

    func settingFraction(_ value: Double, for target: String) -> Self {
        switch self {
        case .pane: return self
        case .split(let id, let axis, let fraction, let first, let second):
            return .split(
                id: id, axis: axis, fraction: id == target ? Self.clampedFraction(value) : fraction,
                first: first.settingFraction(value, for: target),
                second: second.settingFraction(value, for: target))
        }
    }

    static func clampedFraction(_ value: Double) -> Double {
        value.isFinite ? min(0.95, max(0.05, value)) : 0.5
    }
}
