import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// Pure OLED watchOS design tokens sampled 1:1 from the 8 canonical Apple Watch UE mockups (`W01`..`W08`).
public enum WatchTheme {
    private static func hex(_ value: UInt32, alpha: Double = 1.0) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    // MARK: - OLED Surfaces
    public static let canvas = Color.black
    public static let card = hex(0x1C1C1F)
    public static let cardOffline = hex(0x121214)
    public static let cardSelectedDevice = hex(0x1A2435)
    public static let cardWorthALook = hex(0x1E1A14)
    public static let elevatedButton = hex(0x26262B)
    public static let topChromeCircle = hex(0x292929)
    public static let iconTileBlue = hex(0x1F2735)
    public static let iconTileGreen = hex(0x12261C)
    public static let iconTileRed = hex(0x2C1719)
    public static let countTile = hex(0x2E2E34)

    // MARK: - Brand & Semantic Accents
    public static let accentPeriwinkle = hex(0x8DB8FF)
    public static let inkOnPeriwinkle = hex(0x0A1A33)
    public static let amber = hex(0xF2B866)
    public static let amberHalo = hex(0x473B2D)
    public static let amberSubtitle = hex(0xE3CFA8)
    public static let inkOnAmber = hex(0x2A1A00)
    public static let emerald = hex(0x6FD8A6)
    public static let coralRed = hex(0xF59595)
    public static let ringTrack = hex(0x2A3244)

    // MARK: - Text Hierarchy
    public static let inkPrimary = hex(0xF1F1F3)
    public static let inkBody = hex(0xE2E2E6)
    public static let inkSecondary = hex(0xA0A0AA)
    public static let inkMuted = hex(0x8E8E98)
    public static let inkSubtlePill = hex(0xC2C2CA)

    // MARK: - Geometry Constants (46mm 208×248pt baseline, responsive across 40mm–49mm)
    public static let horizontalInset: CGFloat = 8
    public static let topChromeDiameter: CGFloat = 34
    public static let bottomControlHeight: CGFloat = 38
    public static let cardCornerRadius: CGFloat = 16
}

// MARK: - watchOS Haptics Helper

public enum WatchHaptics {
    public static func click() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    public static func success() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    public static func notification() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }

    public static func failure() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.failure)
        #endif
    }
}

// MARK: - Shared Watch Chrome Components

/// Circular top-bar button (`#292929` dark chrome or `#8DB8FF` periwinkle CTA).
public struct WatchCircleChromeButton: View {
    public let systemName: String
    public var foreground: Color = WatchTheme.inkPrimary
    public var background: Color = WatchTheme.topChromeCircle
    public var diameter: CGFloat = WatchTheme.topChromeDiameter
    public var iconSize: CGFloat = 14
    public var accessibilityId: String? = nil
    public var action: () -> Void

    public var body: some View {
        Button(action: {
            WatchHaptics.click()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(background))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId ?? systemName)
    }
}

/// Top navigation bar with circular `<` back button and aligned bold title (`W03`, `W04`, `W05`, `W06`).
public struct WatchNavigationHeader: View {
    public let title: String
    public var onBack: () -> Void

    public var body: some View {
        HStack(spacing: 10) {
            WatchCircleChromeButton(
                systemName: "chevron.left",
                accessibilityId: "watch.nav.back",
                action: onBack
            )
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WatchTheme.inkPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

/// Animated periwinkle running-arc progress ring used on `W01` running rows and `W03` status line.
public struct WatchRunningArcView: View {
    public var size: CGFloat = 15
    public var lineWidth: CGFloat = 2.2
    public var isAnimated: Bool = true

    public var body: some View {
        if isAnimated {
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                let angle = (context.date.timeIntervalSinceReferenceDate * 260.0)
                    .truncatingRemainder(dividingBy: 360.0)
                ring(degrees: angle - 135.0)
            }
        } else {
            ring(degrees: -135.0)
        }
    }

    private func ring(degrees: Double) -> some View {
        ZStack {
            Circle()
                .stroke(WatchTheme.ringTrack, lineWidth: lineWidth)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0.0, to: 0.34)
                .stroke(
                    WatchTheme.accentPeriwinkle,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(degrees))
        }
    }
}

/// Amber glowing approval dot (`#F2B866` inside `#473B2D` halo) used on waiting rows (`W01`).
public struct WatchAmberHaloDot: View {
    public var body: some View {
        ZStack {
            Circle()
                .fill(WatchTheme.amberHalo)
                .frame(width: 16, height: 16)
            Circle()
                .fill(WatchTheme.amber)
                .frame(width: 8.5, height: 8.5)
        }
    }
}

/// Compact orbit brand mark rendered in `W08` approval notification header (`Agents · now`).
public struct WatchBrandGlyphView: View {
    public var body: some View {
        ZStack {
            Circle()
                .fill(WatchTheme.iconTileBlue)
                .frame(width: 22, height: 22)
            ZStack {
                Ellipse()
                    .stroke(WatchTheme.accentPeriwinkle, lineWidth: 1.5)
                    .frame(width: 12, height: 6.5)
                    .rotationEffect(.degrees(-28))
                Circle()
                    .fill(WatchTheme.inkPrimary)
                    .frame(width: 3, height: 3)
            }
        }
    }
}

/// WatchOS 11+ Double Tap primary action shortcut modifier (safe across watchOS versions).
public struct WatchPrimaryDoubleTapModifier: ViewModifier {
    public var enabled: Bool

    public func body(content: Content) -> some View {
        #if os(watchOS)
        if enabled {
            content.handGestureShortcut(.primaryAction)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

public extension View {
    func watchPrimaryDoubleTap(enabled: Bool = true) -> some View {
        modifier(WatchPrimaryDoubleTapModifier(enabled: enabled))
    }
}
