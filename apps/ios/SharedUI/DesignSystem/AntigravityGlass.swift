import SwiftUI

/// Liquid Glass container & Amber Approval card modifiers matching the 13 official iOS UE screens.
public struct AntigravityGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var cornerRadius: CGFloat
    public var isHighlighted: Bool
    public var isAmberWarning: Bool

    public init(cornerRadius: CGFloat = 24, isHighlighted: Bool = false, isAmberWarning: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isHighlighted = isHighlighted
        self.isAmberWarning = isAmberWarning
    }

    public func body(content: Content) -> some View {
        let strokeColor: Color = {
            if isAmberWarning {
                return AntigravityTheme.statusWaiting.opacity(colorScheme == .dark ? 0.36 : 0.45)
            } else if isHighlighted {
                return AntigravityTheme.accentPeriwinkle.opacity(colorScheme == .dark ? 0.45 : 0.55)
            } else {
                return AntigravityTheme.glassHairline
            }
        }()

        let fillOverlay: Color = isAmberWarning
            ? AntigravityTheme.statusWaiting.opacity(colorScheme == .dark ? 0.07 : 0.08)
            : Color.clear

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AntigravityTheme.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(fillOverlay)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .light ? AntigravityTheme.glassShadow : .clear,
                radius: colorScheme == .light ? 8 : 0,
                x: 0,
                y: colorScheme == .light ? 2 : 0
            )
    }
}

public extension View {
    func antigravityGlass(
        cornerRadius: CGFloat = 24,
        isHighlighted: Bool = false,
        isAmberWarning: Bool = false
    ) -> some View {
        modifier(
            AntigravityGlassModifier(
                cornerRadius: cornerRadius,
                isHighlighted: isHighlighted,
                isAmberWarning: isAmberWarning
            )
        )
    }
}

/// Authentic Antigravity Desktop 2×2 four-dot pulsing loading indicator (`::`) shown on active/running
/// conversation rows and streaming status bars.
public struct AntigravityFourDotLoadingView: View {
    public var isAnimated: Bool
    public var dotSize: CGFloat
    public var spacing: CGFloat
    public var tint: Color

    private static let phaseOpacities: [[Double]] = [
        [0.36, 0.64, 0.28, 0.92],
        [0.92, 0.36, 0.64, 0.28],
        [0.28, 0.92, 0.36, 0.64],
        [0.64, 0.28, 0.92, 0.36]
    ]

    public init(
        isAnimated: Bool = true,
        dotSize: CGFloat = 4.5,
        spacing: CGFloat = 3.5,
        tint: Color = AntigravityTheme.inkReading
    ) {
        self.isAnimated = isAnimated
        self.dotSize = dotSize
        self.spacing = spacing
        self.tint = tint
    }

    public var body: some View {
        if isAnimated {
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                let t = context.date.timeIntervalSinceReferenceDate * 5.2
                // Clockwise 2x2 order: top-left (0), top-right (1), bottom-right (3), bottom-left (2)
                let phaseOffsets: [Double] = [0.0, .pi * 0.5, .pi * 1.5, .pi]
                let waves = phaseOffsets.map { offset in
                    0.5 + 0.5 * sin(t - offset)
                }
                let opacities = waves.map { 0.18 + 0.82 * $0 }
                let scales = waves.map { CGFloat(0.80 + 0.36 * $0) }
                fourDotGrid(opacities: opacities, scales: scales)
            }
        } else {
            fourDotGrid(opacities: Self.phaseOpacities[0], scales: [1.0, 1.0, 1.0, 1.0])
        }
    }

    private func fourDotGrid(opacities: [Double], scales: [CGFloat]) -> some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                Circle()
                    .fill(tint.opacity(opacities[0]))
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(scales[0])
                Circle()
                    .fill(tint.opacity(opacities[1]))
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(scales[1])
            }
            HStack(spacing: spacing) {
                Circle()
                    .fill(tint.opacity(opacities[2]))
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(scales[2])
                Circle()
                    .fill(tint.opacity(opacities[3]))
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(scales[3])
            }
        }
        .frame(width: dotSize * 2 + spacing + 2, height: dotSize * 2 + spacing + 2)
    }
}

/// Leading periwinkle running-arc indicator with live rotation when connected to Antigravity Desktop.
public struct AntigravityRunningArcIndicatorView: View {
    public var isAnimated: Bool

    public init(isAnimated: Bool = false) {
        self.isAnimated = isAnimated
    }

    public var body: some View {
        if isAnimated {
            TimelineView(.periodic(from: .now, by: 0.033)) { context in
                let angle = (context.date.timeIntervalSinceReferenceDate * 270.0)
                    .truncatingRemainder(dividingBy: 360.0)
                arcRing(angleDegrees: angle - 85.0)
            }
        } else {
            arcRing(angleDegrees: -85.0)
        }
    }

    private func arcRing(angleDegrees: Double) -> some View {
        ZStack {
            Circle()
                .stroke(AntigravityTheme.ringTrack, lineWidth: 2)
                .frame(width: 15, height: 15)
            Circle()
                .trim(from: 0.0, to: 0.32)
                .stroke(
                    AntigravityTheme.statusRunning,
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .frame(width: 15, height: 15)
                .rotationEffect(.degrees(angleDegrees))
        }
    }
}

/// Minimal open-arc rotating spinner matching the official Antigravity mobile history loading pill.
public struct AntigravityThinSpinnerView: View {
    public var isAnimated: Bool
    public var size: CGFloat
    public var lineWidth: CGFloat
    public var tint: Color

    public init(
        isAnimated: Bool = true,
        size: CGFloat = 13.5,
        lineWidth: CGFloat = 1.6,
        tint: Color = AntigravityTheme.inkSecondary
    ) {
        self.isAnimated = isAnimated
        self.size = size
        self.lineWidth = lineWidth
        self.tint = tint
    }

    public var body: some View {
        if isAnimated {
            TimelineView(.periodic(from: .now, by: 0.025)) { context in
                let angle = (context.date.timeIntervalSinceReferenceDate * 380.0)
                    .truncatingRemainder(dividingBy: 360.0)
                spinnerArc(angleDegrees: angle - 90.0)
            }
        } else {
            spinnerArc(angleDegrees: -90.0)
        }
    }

    private func spinnerArc(angleDegrees: Double) -> some View {
        Circle()
            .trim(from: 0.0, to: 0.68)
            .stroke(
                tint,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angleDegrees))
    }
}

/// Floating top-center capsule pill overlaid over the chat viewport while loading historical or older messages.
public struct AntigravityFloatingLoadingPill: View {
    @Environment(\.colorScheme) private var colorScheme
    public var title: String
    public var isAnimated: Bool

    public init(
        title: String,
        isAnimated: Bool = true
    ) {
        self.title = title
        self.isAnimated = isAnimated
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let fill = colorScheme == .dark
            ? AntigravityTheme.surfacePill.opacity(0.96)
            : AntigravityTheme.surfaceCard.opacity(0.97)
        let stroke = colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.10)
        let shadowColor = colorScheme == .dark
            ? Color.black.opacity(0.36)
            : Color.black.opacity(0.10)

        HStack(spacing: 8) {
            AntigravityThinSpinnerView(
                isAnimated: isAnimated,
                size: 13.5,
                lineWidth: 1.6,
                tint: AntigravityTheme.inkSecondary
            )
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(AntigravityTheme.inkLabel.opacity(0.86))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(stroke, lineWidth: 1))
        .shadow(
            color: shadowColor,
            radius: colorScheme == .dark ? 10 : 8,
            x: 0,
            y: colorScheme == .dark ? 4 : 3
        )
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}


