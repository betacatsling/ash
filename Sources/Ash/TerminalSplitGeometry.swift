import Foundation

struct TerminalSplitGeometry {
    struct Divider: Identifiable {
        let id: String
        let axis: TerminalSplitAxis
        let frame: CGRect
        let availableLength: CGFloat
        let firstLength: CGFloat
        let minimumFirst: CGFloat
        let minimumSecond: CGFloat

        func fraction(translatedBy distance: CGFloat) -> Double {
            guard availableLength > 0 else { return 0.5 }
            return Double(
                min(availableLength - minimumSecond, max(minimumFirst, firstLength + distance)) / availableLength)
        }
    }

    static let dividerThickness: CGFloat = 1
    static let minimumPaneSize = CGSize(width: 220, height: 120)
    var panes: [String: CGRect] = [:]
    var dividers: [Divider] = []

    static func minimumSize(of layout: TerminalLayout) -> CGSize {
        switch layout {
        case .pane: return minimumPaneSize
        case .split(_, let axis, _, let first, let second):
            let a = minimumSize(of: first)
            let b = minimumSize(of: second)
            return axis == .horizontal
                ? CGSize(width: a.width + b.width + dividerThickness, height: max(a.height, b.height))
                : CGSize(width: max(a.width, b.width), height: a.height + b.height + dividerThickness)
        }
    }

    init(layout: TerminalLayout, size: CGSize, fractions: [String: Double] = [:]) {
        let minimum = Self.minimumSize(of: layout)
        place(
            layout,
            in: CGRect(
                origin: .zero,
                size: CGSize(
                    width: max(size.width, minimum.width),
                    height: max(size.height, minimum.height))), fractions: fractions)
    }

    private mutating func place(_ layout: TerminalLayout, in frame: CGRect, fractions: [String: Double]) {
        switch layout {
        case .pane(let id): panes[id] = frame
        case .split(let id, let axis, let fraction, let first, let second):
            let horizontal = axis == .horizontal
            let a = Self.minimumSize(of: first)
            let b = Self.minimumSize(of: second)
            let minA = horizontal ? a.width : a.height
            let minB = horizontal ? b.width : b.height
            let length = (horizontal ? frame.width : frame.height) - Self.dividerThickness
            let firstLength = min(
                length - minB, max(minA, length * TerminalLayout.clampedFraction(fractions[id] ?? fraction)))
            var firstFrame = frame
            var secondFrame = frame
            var dividerFrame = frame
            if horizontal {
                firstFrame.size.width = firstLength
                dividerFrame.origin.x += firstLength
                dividerFrame.size.width = Self.dividerThickness
                secondFrame.origin.x += firstLength + Self.dividerThickness
                secondFrame.size.width = length - firstLength
            } else {
                firstFrame.size.height = firstLength
                dividerFrame.origin.y += firstLength
                dividerFrame.size.height = Self.dividerThickness
                secondFrame.origin.y += firstLength + Self.dividerThickness
                secondFrame.size.height = length - firstLength
            }
            dividers.append(
                Divider(
                    id: id, axis: axis, frame: dividerFrame, availableLength: length,
                    firstLength: firstLength, minimumFirst: minA, minimumSecond: minB))
            place(first, in: firstFrame, fractions: fractions)
            place(second, in: secondFrame, fractions: fractions)
        }
    }
}
