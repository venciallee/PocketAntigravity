import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - TextKit Rounded Inline Code Pill Renderer (`RichMarkdownInlineBlockView`)
// Eliminates U+200A hair-space line-wrap orphan boxes, renders crisp rounded pills with
// subtle borders, supports true iOS range selection & clean copy, and routes link taps via `openURL`.

internal struct RichMarkdownInlineBlockView: View {
    let inlines: [MarkdownInline]
    let baseSize: CGFloat
    let baseWeight: Font.Weight
    let defaultColor: Color
    let lineSpacing: CGFloat
    let textAlignment: TextAlignment
    let expandsToProposedWidth: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(
        inlines: [MarkdownInline],
        baseSize: CGFloat,
        baseWeight: Font.Weight,
        defaultColor: Color,
        lineSpacing: CGFloat,
        textAlignment: TextAlignment = .leading,
        expandsToProposedWidth: Bool = true
    ) {
        self.inlines = inlines
        self.baseSize = baseSize
        self.baseWeight = baseWeight
        self.defaultColor = defaultColor
        self.lineSpacing = lineSpacing
        self.textAlignment = textAlignment
        self.expandsToProposedWidth = expandsToProposedWidth
    }

    var body: some View {
        #if canImport(UIKit)
        RichMarkdownTextViewRepresentable(
            inlines: inlines,
            baseSize: baseSize,
            baseWeight: baseWeight,
            defaultColor: defaultColor,
            lineSpacing: lineSpacing,
            textAlignment: textAlignment,
            expandsToProposedWidth: expandsToProposedWidth,
            colorScheme: colorScheme
        )
        #else
        Text(
            MarkdownInlineBuilder.build(
                inlines,
                baseSize: baseSize,
                baseWeight: baseWeight,
                defaultColor: defaultColor
            )
        )
        .multilineTextAlignment(textAlignment)
        .lineSpacing(lineSpacing)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        #endif
    }
}

#if canImport(UIKit)
private extension NSAttributedString.Key {
    static let agyInlinePillStyle = NSAttributedString.Key("dev.antigravity.inlinePillStyle")
}

internal final class InlinePillVisualStyle: NSObject, @unchecked Sendable {
    let fillColor: UIColor
    let borderColor: UIColor
    let cornerRadius: CGFloat
    let leftOutset: CGFloat
    let rightOutset: CGFloat
    let verticalOutset: CGFloat
    let borderWidth: CGFloat

    init(
        fillColor: UIColor,
        borderColor: UIColor,
        cornerRadius: CGFloat = 5.0,
        leftOutset: CGFloat = 2.6,
        rightOutset: CGFloat = 2.6,
        verticalOutset: CGFloat = 0.8,
        borderWidth: CGFloat = 0.75
    ) {
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.leftOutset = leftOutset
        self.rightOutset = rightOutset
        self.verticalOutset = verticalOutset
        self.borderWidth = borderWidth
        super.init()
    }
}

/// Custom `NSLayoutManager` that draws crisp rounded-pill backgrounds strictly around visible
/// non-whitespace glyphs of inline code, `<kbd>` keys, and `<mark>` highlights — mathematically
/// preventing orphaned background rectangles on line wraps without injecting fake space characters.
internal final class InlineCodePillLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }

        let visibleCharRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard visibleCharRange.location != NSNotFound, visibleCharRange.length > 0 else { return }

        let fullString = storage.string as NSString
        storage.enumerateAttribute(.agyInlinePillStyle, in: visibleCharRange, options: []) { value, attrRange, _ in
            guard let pillStyle = value as? InlinePillVisualStyle, attrRange.length > 0 else { return }

            // Trim any leading/trailing whitespace or newlines in the run so wrapped spaces never paint orphan boxes
            var start = attrRange.location
            var end = attrRange.location + attrRange.length
            let wsSet = CharacterSet.whitespacesAndNewlines
            while start < end, let scalar = UnicodeScalar(fullString.character(at: start)), wsSet.contains(scalar) {
                start += 1
            }
            while end > start, let scalar = UnicodeScalar(fullString.character(at: end - 1)), wsSet.contains(scalar) {
                end -= 1
            }
            guard end > start else { return }

            let trimmedCharRange = NSRange(location: start, length: end - start)
            let pillGlyphRange = glyphRange(forCharacterRange: trimmedCharRange, actualCharacterRange: nil)
            guard pillGlyphRange.length > 0 else { return }

            enumerateEnclosingRects(
                forGlyphRange: pillGlyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                guard rect.width > 1.0, rect.height > 1.0 else { return }
                let shifted = rect.offsetBy(dx: origin.x, dy: origin.y)
                let minX = shifted.minX - pillStyle.leftOutset
                let maxX = shifted.maxX + pillStyle.rightOutset
                let pillRect = CGRect(
                    x: minX,
                    y: shifted.minY - pillStyle.verticalOutset,
                    width: max(1.0, maxX - minX),
                    height: shifted.height + pillStyle.verticalOutset * 2.0
                )
                let path = UIBezierPath(roundedRect: pillRect, cornerRadius: pillStyle.cornerRadius)
                pillStyle.fillColor.setFill()
                path.fill()
                if pillStyle.borderWidth > 0 {
                    pillStyle.borderColor.setStroke()
                    path.lineWidth = pillStyle.borderWidth
                    path.stroke()
                }
            }
        }
    }
}

internal final class RichMarkdownUITextView: UITextView {
    let pillLayoutManager: InlineCodePillLayoutManager

    init() {
        let storage = NSTextStorage()
        let layoutMgr = InlineCodePillLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutMgr.addTextContainer(container)
        storage.addLayoutManager(layoutMgr)
        self.pillLayoutManager = layoutMgr

        super.init(frame: .zero, textContainer: container)

        backgroundColor = .clear
        isOpaque = false
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        clipsToBounds = false
        textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        dataDetectorTypes = []
        adjustsFontForContentSizeCategory = false
        linkTextAttributes = [
            .foregroundColor: AntigravityTheme.accentPeriwinkleUIColor
        ]
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontalInset = textContainerInset.left + textContainerInset.right
        let targetWidth = max(1.0, bounds.width - horizontalInset)
        if abs(textContainer.size.width - targetWidth) > 0.5 {
            textContainer.size = CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
            pillLayoutManager.ensureLayout(for: textContainer)
            setNeedsDisplay()
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let horizontalInset = textContainerInset.left + textContainerInset.right
        let verticalInset = textContainerInset.top + textContainerInset.bottom
        let availableWidth: CGFloat
        if size.width.isFinite && size.width > horizontalInset {
            availableWidth = size.width - horizontalInset
        } else {
            availableWidth = CGFloat.greatestFiniteMagnitude
        }
        let previousSize = textContainer.size
        defer {
            if bounds.width > horizontalInset + 1 {
                textContainer.size = CGSize(width: bounds.width - horizontalInset, height: CGFloat.greatestFiniteMagnitude)
            } else {
                textContainer.size = previousSize
            }
        }
        textContainer.size = CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        pillLayoutManager.ensureLayout(for: textContainer)
        let usedRect = pillLayoutManager.usedRect(for: textContainer)
        let finalWidth = min(availableWidth, ceil(usedRect.width)) + horizontalInset
        let finalHeight = ceil(usedRect.height) + verticalInset
        return CGSize(width: max(1.0, finalWidth), height: max(1.0, finalHeight))
    }
}

internal struct RichMarkdownTextViewRepresentable: UIViewRepresentable {
    let inlines: [MarkdownInline]
    let baseSize: CGFloat
    let baseWeight: Font.Weight
    let defaultColor: Color
    let lineSpacing: CGFloat
    let textAlignment: TextAlignment
    let expandsToProposedWidth: Bool
    let colorScheme: ColorScheme

    @Environment(\.openURL) private var openURL

    struct RenderKey: Equatable {
        let inlines: [MarkdownInline]
        let baseSize: CGFloat
        let weightTag: Int
        let colorHex: UInt32
        let lineSpacing: CGFloat
        let alignmentTag: Int
        let isDarkMode: Bool
    }

    private var resolvedTraitCollection: UITraitCollection {
        UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    }

    private var currentRenderKey: RenderKey {
        let traits = resolvedTraitCollection
        return RenderKey(
            inlines: inlines,
            baseSize: baseSize,
            weightTag: UIKitInlineAttributedBuilder.weightTag(baseWeight),
            colorHex: UIKitInlineAttributedBuilder.colorSignature(defaultColor, traitCollection: traits),
            lineSpacing: lineSpacing,
            alignmentTag: UIKitInlineAttributedBuilder.alignmentTag(textAlignment),
            isDarkMode: colorScheme == .dark
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: { url in
            openURL(url)
        })
    }

    func makeUIView(context: Context) -> RichMarkdownUITextView {
        let textView = RichMarkdownUITextView()
        textView.delegate = context.coordinator
        let traits = resolvedTraitCollection
        textView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        textView.linkTextAttributes = [
            .foregroundColor: AntigravityTheme.accentPeriwinkleUIColor.resolvedColor(with: traits)
        ]
        let attributed = UIKitInlineAttributedBuilder.build(
            inlines,
            baseSize: baseSize,
            baseWeight: baseWeight,
            defaultColor: defaultColor,
            lineSpacing: lineSpacing,
            textAlignment: textAlignment,
            traitCollection: traits
        )
        textView.attributedText = attributed
        context.coordinator.lastRenderKey = currentRenderKey
        return textView
    }

    func updateUIView(_ uiView: RichMarkdownUITextView, context: Context) {
        context.coordinator.onOpenURL = { url in
            openURL(url)
        }
        let key = currentRenderKey
        if context.coordinator.lastRenderKey != key {
            let traits = resolvedTraitCollection
            uiView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
            uiView.linkTextAttributes = [
                .foregroundColor: AntigravityTheme.accentPeriwinkleUIColor.resolvedColor(with: traits)
            ]
            uiView.attributedText = UIKitInlineAttributedBuilder.build(
                inlines,
                baseSize: baseSize,
                baseWeight: baseWeight,
                defaultColor: defaultColor,
                lineSpacing: lineSpacing,
                textAlignment: textAlignment,
                traitCollection: traits
            )
            context.coordinator.lastRenderKey = key
            uiView.invalidateIntrinsicContentSize()
            uiView.setNeedsDisplay()
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: RichMarkdownUITextView,
        context: Context
    ) -> CGSize? {
        let proposedW = proposal.width
        if let proposedW, proposedW.isFinite && proposedW > 0 {
            let measured = uiView.sizeThatFits(CGSize(width: proposedW, height: CGFloat.greatestFiniteMagnitude))
            let finalW = expandsToProposedWidth ? proposedW : min(proposedW, ceil(measured.width))
            return CGSize(width: finalW, height: ceil(measured.height))
        }
        let measured = uiView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: ceil(measured.width), height: ceil(measured.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: @MainActor (URL) -> Void
        var lastRenderKey: RenderKey?

        init(onOpenURL: @escaping @MainActor (URL) -> Void) {
            self.onOpenURL = onOpenURL
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            if case .link(let url) = textItem.content {
                return UIAction { [weak self] _ in
                    self?.onOpenURL(url)
                }
            }
            return defaultAction
        }
    }
}

internal enum UIKitInlineAttributedBuilder {
    private struct StyleState {
        var isBold: Bool = false
        var isItalic: Bool = false
        var isStrikethrough: Bool = false
        var isUnderline: Bool = false
        var isHighlight: Bool = false
        var isCode: Bool = false
        var isKeyboardKey: Bool = false
        var isMath: Bool = false
        var isSuperscript: Bool = false
        var isSubscript: Bool = false
        var baseWeight: UIFont.Weight = .regular
        var linkDestination: String? = nil

        func resolvedFont(baseSize: CGFloat) -> UIFont {
            if isKeyboardKey {
                return UIFont.monospacedSystemFont(ofSize: max(11.0, baseSize - 2.5), weight: .semibold)
            }
            if isCode {
                let codeSize = max(11.5, baseSize - 1.7)
                let codeWeight: UIFont.Weight = isBold ? .semibold : .medium
                return UIFont.monospacedSystemFont(ofSize: codeSize, weight: codeWeight)
            }
            if isSuperscript || isSubscript {
                return UIFont.systemFont(ofSize: max(10.0, baseSize * 0.72), weight: isBold ? .semibold : .medium)
            }
            if isMath {
                let mathSize = max(12.5, baseSize - 0.5)
                let base = UIFont.systemFont(ofSize: mathSize, weight: isBold ? .semibold : .regular)
                if let serifDesc = base.fontDescriptor.withDesign(.serif),
                   let italicDesc = serifDesc.withSymbolicTraits(.traitItalic) {
                    return UIFont(descriptor: italicDesc, size: mathSize)
                }
                return UIFont.italicSystemFont(ofSize: mathSize)
            }
            let weight: UIFont.Weight = isBold ? .bold : baseWeight
            let base = UIFont.systemFont(ofSize: baseSize, weight: weight)
            if isItalic {
                var traits = base.fontDescriptor.symbolicTraits
                traits.insert(.traitItalic)
                if let italicDesc = base.fontDescriptor.withSymbolicTraits(traits) {
                    return UIFont(descriptor: italicDesc, size: baseSize)
                }
                return UIFont.italicSystemFont(ofSize: baseSize)
            }
            return base
        }

        func resolvedForeground(defaultUI: UIColor, traits: UITraitCollection) -> UIColor {
            if linkDestination != nil {
                return AntigravityTheme.accentPeriwinkleUIColor.resolvedColor(with: traits)
            }
            if isKeyboardKey {
                return AntigravityTheme.inkKbdUIColor.resolvedColor(with: traits)
            }
            if isCode || isMath {
                return AntigravityTheme.inkInlineCodeUIColor.resolvedColor(with: traits)
            }
            if isHighlight {
                return AntigravityTheme.inkMarkHighlightUIColor.resolvedColor(with: traits)
            }
            return defaultUI
        }

        func resolvedPillStyle(tightLeading: Bool, tightTrailing: Bool, traits: UITraitCollection) -> InlinePillVisualStyle? {
            if isKeyboardKey {
                return InlinePillVisualStyle(
                    fillColor: AntigravityTheme.surfaceKbdUIColor.resolvedColor(with: traits),
                    borderColor: AntigravityTheme.subtleBorderUIColor.resolvedColor(with: traits),
                    cornerRadius: 5.0,
                    leftOutset: tightLeading ? 2.0 : 3.2,
                    rightOutset: tightTrailing ? 2.0 : 3.2,
                    verticalOutset: 1.0,
                    borderWidth: 1.0
                )
            }
            if isCode {
                if linkDestination != nil {
                    let accent = AntigravityTheme.accentPeriwinkleUIColor.resolvedColor(with: traits)
                    return InlinePillVisualStyle(
                        fillColor: accent.withAlphaComponent(0.14),
                        borderColor: accent.withAlphaComponent(0.26),
                        cornerRadius: 5.0,
                        leftOutset: tightLeading ? 1.8 : 2.6,
                        rightOutset: tightTrailing ? 1.8 : 2.6,
                        verticalOutset: 0.8,
                        borderWidth: 0.75
                    )
                }
                return InlinePillVisualStyle(
                    fillColor: AntigravityTheme.surfaceInlineCodeUIColor.resolvedColor(with: traits),
                    borderColor: AntigravityTheme.subtleBorderUIColor.resolvedColor(with: traits),
                    cornerRadius: 5.0,
                    leftOutset: tightLeading ? 1.8 : 2.6,
                    rightOutset: tightTrailing ? 1.8 : 2.6,
                    verticalOutset: 0.8,
                    borderWidth: 0.75
                )
            }
            if isHighlight {
                return InlinePillVisualStyle(
                    fillColor: AntigravityTheme.surfaceMarkHighlightUIColor.resolvedColor(with: traits),
                    borderColor: AntigravityTheme.statusWaitingUIColor.resolvedColor(with: traits).withAlphaComponent(0.32),
                    cornerRadius: 4.0,
                    leftOutset: 1.6,
                    rightOutset: 1.6,
                    verticalOutset: 0.5,
                    borderWidth: 0.0
                )
            }
            return nil
        }
    }

    static func build(
        _ nodes: [MarkdownInline],
        baseSize: CGFloat,
        baseWeight: Font.Weight,
        defaultColor: Color,
        lineSpacing: CGFloat,
        textAlignment: TextAlignment,
        traitCollection: UITraitCollection
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let defaultUI = UIColor(defaultColor).resolvedColor(with: traitCollection)
        let initial = StyleState(baseWeight: uiFontWeight(baseWeight))
        appendNodes(
            nodes,
            style: initial,
            baseSize: baseSize,
            defaultUI: defaultUI,
            traits: traitCollection,
            into: output
        )

        // Apply subtle kerning before tight inline code/kbd pills so adjacent CJK/Latin never collides with pill outset
        applyTightPillSpacingKerns(on: output)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = nsAlignment(textAlignment)
        if output.length > 0 {
            output.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: output.length))
        }
        return output
    }

    private static func appendNodes(
        _ nodes: [MarkdownInline],
        style: StyleState,
        baseSize: CGFloat,
        defaultUI: UIColor,
        traits: UITraitCollection,
        into output: NSMutableAttributedString
    ) {
        for (idx, node) in nodes.enumerated() {
            switch node {
            case .text(let s):
                output.append(makeSegment(s, style: style, baseSize: baseSize, defaultUI: defaultUI, traits: traits, tightLeading: false, tightTrailing: false))

            case .softBreak:
                output.append(makeSegment("\n", style: style, baseSize: baseSize, defaultUI: defaultUI, traits: traits, tightLeading: false, tightTrailing: false))

            case .code(let codeText):
                guard !codeText.isEmpty else { continue }
                var codeStyle = style
                codeStyle.isCode = true
                let prevChar = lastCharacter(of: output)
                let nextChar = firstCharacter(of: idx + 1 < nodes.count ? nodes[idx + 1] : nil)
                let tightLead = prevChar.map { !$0.isWhitespace } ?? false
                let tightTrail = nextChar.map { !$0.isWhitespace } ?? false
                // Pure code text — ZERO injected U+200A padding spaces!
                output.append(makeSegment(codeText, style: codeStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, tightLeading: tightLead, tightTrailing: tightTrail))

            case .keyboardKey(let keyText):
                guard !keyText.isEmpty else { continue }
                var kbdStyle = style
                kbdStyle.isKeyboardKey = true
                let prevChar = lastCharacter(of: output)
                let nextChar = firstCharacter(of: idx + 1 < nodes.count ? nodes[idx + 1] : nil)
                let tightLead = prevChar.map { !$0.isWhitespace } ?? false
                let tightTrail = nextChar.map { !$0.isWhitespace } ?? false
                output.append(makeSegment(keyText, style: kbdStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, tightLeading: tightLead, tightTrailing: tightTrail))

            case .strong(let children):
                var boldStyle = style
                boldStyle.isBold = true
                appendNodes(children, style: boldStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, into: output)

            case .emphasis(let children):
                var italicStyle = style
                italicStyle.isItalic = true
                appendNodes(children, style: italicStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, into: output)

            case .strikethrough(let children):
                var strikeStyle = style
                strikeStyle.isStrikethrough = true
                appendNodes(children, style: strikeStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, into: output)

            case .underline(let children):
                var underStyle = style
                underStyle.isUnderline = true
                appendNodes(children, style: underStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, into: output)

            case .highlight(let children):
                var hiStyle = style
                hiStyle.isHighlight = true
                appendNodes(children, style: hiStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, into: output)

            case .superscript(let text):
                var supStyle = style
                supStyle.isSuperscript = true
                output.append(makeSegment(text, style: supStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, tightLeading: false, tightTrailing: false))

            case .subscriptText(let text):
                var subStyle = style
                subStyle.isSubscript = true
                output.append(makeSegment(text, style: subStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, tightLeading: false, tightTrailing: false))

            case .link(let labelNodes, let destination):
                var linkStyle = style
                linkStyle.linkDestination = destination
                appendNodes(labelNodes, style: linkStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, into: output)

            case .inlineMath(let latex):
                var mathStyle = style
                mathStyle.isMath = true
                let rendered = MarkdownMathNormalizer.prettify(latex)
                output.append(makeSegment(rendered, style: mathStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, tightLeading: false, tightTrailing: false))

            case .inlineImage(let alt, let src):
                var linkStyle = style
                linkStyle.linkDestination = src
                linkStyle.isCode = true
                let label = alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? MarkdownLinkFormatting.shortFileBadge(src)
                    : alt
                output.append(makeSegment("🖼 \(label)", style: linkStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, tightLeading: false, tightTrailing: false))

            case .footnoteRef(let label):
                var fnStyle = style
                fnStyle.isSuperscript = true
                var attrs = makeAttributes(style: fnStyle, baseSize: baseSize, defaultUI: defaultUI, traits: traits, tightLeading: false, tightTrailing: false)
                attrs[.foregroundColor] = AntigravityTheme.accentPeriwinkleUIColor.resolvedColor(with: traits)
                output.append(NSAttributedString(string: "[\(label)]", attributes: attrs))
            }
        }
    }

    private static func makeSegment(
        _ string: String,
        style: StyleState,
        baseSize: CGFloat,
        defaultUI: UIColor,
        traits: UITraitCollection,
        tightLeading: Bool,
        tightTrailing: Bool
    ) -> NSAttributedString {
        let attrs = makeAttributes(
            style: style,
            baseSize: baseSize,
            defaultUI: defaultUI,
            traits: traits,
            tightLeading: tightLeading,
            tightTrailing: tightTrailing
        )
        return NSAttributedString(string: string, attributes: attrs)
    }

    private static func makeAttributes(
        style: StyleState,
        baseSize: CGFloat,
        defaultUI: UIColor,
        traits: UITraitCollection,
        tightLeading: Bool,
        tightTrailing: Bool
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: style.resolvedFont(baseSize: baseSize),
            .foregroundColor: style.resolvedForeground(defaultUI: defaultUI, traits: traits)
        ]
        if style.isStrikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.isUnderline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.isSuperscript {
            attrs[.baselineOffset] = baseSize * 0.28
        } else if style.isSubscript {
            attrs[.baselineOffset] = -(baseSize * 0.16)
        }
        if let pill = style.resolvedPillStyle(tightLeading: tightLeading, tightTrailing: tightTrailing, traits: traits) {
            attrs[.agyInlinePillStyle] = pill
        }
        if let dest = style.linkDestination,
           let url = MarkdownLinkFormatting.resolvedActionURL(for: dest) {
            attrs[.link] = url
        }
        return attrs
    }

    /// Adds a tiny non-breaking `.kern` on the character immediately preceding a tight pill
    /// (zero extra characters inserted into text storage -> clipboard stays 100% pure).
    private static func applyTightPillSpacingKerns(on attributed: NSMutableAttributedString) {
        let nsStr = attributed.string as NSString
        guard nsStr.length > 1 else { return }
        let fullRange = NSRange(location: 0, length: nsStr.length)
        let wsSet = CharacterSet.whitespacesAndNewlines

        attributed.enumerateAttribute(.agyInlinePillStyle, in: fullRange, options: []) { value, range, _ in
            guard value is InlinePillVisualStyle else { return }
            if range.location > 0 {
                let prevIdx = range.location - 1
                let prevUnit = nsStr.character(at: prevIdx)
                if let scalar = UnicodeScalar(prevUnit), !wsSet.contains(scalar) {
                    let existingPill = attributed.attribute(.agyInlinePillStyle, at: prevIdx, effectiveRange: nil)
                    if existingPill == nil {
                        attributed.addAttribute(.kern, value: CGFloat(2.5), range: NSRange(location: prevIdx, length: 1))
                    }
                }
            }
        }
    }

    private static func lastCharacter(of attributed: NSMutableAttributedString) -> Character? {
        attributed.string.last
    }

    private static func firstCharacter(of node: MarkdownInline?) -> Character? {
        guard let node else { return nil }
        return node.plainText.first
    }

    static func uiFontWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    static func weightTag(_ weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight: return 1
        case .thin: return 2
        case .light: return 3
        case .medium: return 5
        case .semibold: return 6
        case .bold: return 7
        case .heavy: return 8
        case .black: return 9
        default: return 4
        }
    }

    static func nsAlignment(_ alignment: TextAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    static func alignmentTag(_ alignment: TextAlignment) -> Int {
        switch alignment {
        case .leading: return 0
        case .center: return 1
        case .trailing: return 2
        }
    }

    static func colorSignature(_ color: Color, traitCollection: UITraitCollection) -> UInt32 {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(color).resolvedColor(with: traitCollection).getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32(max(0, min(255, Int(r * 255))))
        let gi = UInt32(max(0, min(255, Int(g * 255))))
        let bi = UInt32(max(0, min(255, Int(b * 255))))
        let ai = UInt32(max(0, min(255, Int(a * 255))))
        return (ri << 24) | (gi << 16) | (bi << 8) | ai
    }
}
#endif
