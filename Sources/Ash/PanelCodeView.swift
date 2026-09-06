import AppKit
import SwiftUI

/// Native text selection, horizontal scrolling, and the system Find bar.
struct PanelCodeView: NSViewRepresentable {
    let text: String
    let diff: Bool
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = CodeScrollView()
        scroll.wantsLayer = true
        scroll.layer?.masksToBounds = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let view = NSTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.usesFindBar = true
        view.isAutomaticLinkDetectionEnabled = false
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.minSize = .zero
        view.maxSize = NSSize(width: 1_000_000, height: 10_000_000)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: 1_000_000, height: 10_000_000)
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.backgroundColor = .textBackgroundColor
        scroll.documentView = view
        let ruler = CodeLineRuler(scrollView: scroll, orientation: .verticalRuler)
        ruler.clientView = view
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = !diff
        scroll.rulersVisible = !diff
        updateNSView(scroll, context: context)
        return scroll
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: proposal.height ?? 400)
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text || view.textStorage?.length == 0 else {
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let rendered = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
            ])
        if diff {
            var offset = 0
            for line in text.components(separatedBy: "\n") {
                let length = (line as NSString).length
                let color: NSColor? =
                    line.hasPrefix("+")
                    ? .systemGreen : line.hasPrefix("-") ? .systemRed : line.hasPrefix("@@") ? .systemOrange : nil
                if let color, length > 0 {
                    rendered.addAttributes(
                        [.foregroundColor: color, .backgroundColor: color.withAlphaComponent(0.08)],
                        range: NSRange(location: offset, length: length))
                }
                offset += length + 1
            }
        }
        view.textStorage?.setAttributedString(rendered)
        (scroll as? CodeScrollView)?.sizeDocument()
        scroll.verticalRulerView?.needsDisplay = true
    }
}

final class CodeScrollView: NSScrollView {
    override func layout() {
        super.layout()
        sizeDocument()
    }
    func sizeDocument() {
        guard let view = documentView as? NSTextView, let layout = view.layoutManager,
            let container = view.textContainer
        else { return }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let size = NSSize(
            width: max(contentSize.width, used.width + 2 * view.textContainerInset.width),
            height: max(contentSize.height, used.height + 2 * view.textContainerInset.height))
        if view.frame.size != size { view.setFrameSize(size) }
        verticalRulerView?.needsDisplay = true
    }
}

final class CodeLineRuler: NSRulerView {
    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 48
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        guard let textView = clientView as? NSTextView, let layout = textView.layoutManager,
            let container = textView.textContainer, layout.numberOfGlyphs > 0
        else { return }
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let string = textView.string as NSString
        var lineNumber = 1
        var character = 0
        let firstCharacter = layout.characterIndexForGlyph(at: min(glyphs.location, max(0, layout.numberOfGlyphs - 1)))
        while character < min(firstCharacter, string.length) {
            let range = string.lineRange(for: NSRange(location: character, length: 0))
            if NSMaxRange(range) > firstCharacter { break }
            character = NSMaxRange(range)
            lineNumber += 1
        }
        while character < string.length {
            let glyph = layout.glyphIndexForCharacter(at: character)
            if glyph > NSMaxRange(glyphs) { break }
            let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = line.minY + textView.textContainerInset.height - visible.minY
            let label = "\(lineNumber)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            label.draw(
                at: NSPoint(x: ruleThickness - label.size(withAttributes: attrs).width - 10, y: y + 2),
                withAttributes: attrs)
            character = NSMaxRange(string.lineRange(for: NSRange(location: character, length: 0)))
            lineNumber += 1
        }
    }
}
