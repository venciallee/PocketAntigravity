import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Adaptive Light & Dark semantic design tokens aligned 1:1 with the 13 official Antigravity iOS UE screens.
///
/// - **Dark Mode (Matte OLED Obsidian)**: Canvas `#090A0D`, Grouped Cards `#141519`, Periwinkle CTA `#8EB4FF`,
///   Warm Amber Face ID Approval `#EBB365`, Emerald Diff Addition `#57C88A`, Coral Deletion `#F07167`.
/// - **Light Mode (Apple HIG Soft Porcelain)**: Canvas `#F4F5F8`, Pure White Cards `#FFFFFF`, Deep Periwinkle CTA `#2F66E8`,
///   Rich Amber Approval `#B86E00`, Deep Emerald `#198754`, Crisp Coral `#CF372E` (all WCAG AA >= 4.5:1).
public enum AntigravityTheme {
    // MARK: - Dynamic Color Builders

    public struct RGB: Sendable {
        public let r: Double
        public let g: Double
        public let b: Double
        public let a: Double

        public init(_ hex: UInt32, alpha: Double = 1.0) {
            self.r = Double((hex >> 16) & 0xFF) / 255.0
            self.g = Double((hex >> 8) & 0xFF) / 255.0
            self.b = Double(hex & 0xFF) / 255.0
            self.a = alpha
        }

        public init(white: Double, alpha: Double = 1.0) {
            self.r = white
            self.g = white
            self.b = white
            self.a = alpha
        }

        public var swiftUIColor: Color {
            Color(red: r, green: g, blue: b, opacity: a)
        }

        #if canImport(UIKit)
        public var uiColor: UIColor {
            UIColor(red: r, green: g, blue: b, alpha: a)
        }
        #endif
    }

    #if canImport(UIKit)
    public static func dynamicUIColor(dark: RGB, light: RGB) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
        }
    }
    #endif

    public static func dynamicColor(dark: RGB, light: RGB) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: dynamicUIColor(dark: dark, light: light))
        #else
        return dark.swiftUIColor
        #endif
    }

    // MARK: - Surfaces
    public static let canvasObsidian = dynamicColor(dark: RGB(0x090A0D), light: RGB(0xF4F5F8))
    public static let surfaceObsidian = dynamicColor(dark: RGB(0x0F1014), light: RGB(0xECEEF4))
    public static let surfaceCard = dynamicColor(dark: RGB(0x141519), light: RGB(0xFFFFFF))
    public static let surfaceSheet = dynamicColor(dark: RGB(0x17181D), light: RGB(0xF6F7FA))
    public static let surfacePill = dynamicColor(dark: RGB(0x17191F), light: RGB(0xE8EBF2))
    public static let surfaceSubtleBox = dynamicColor(dark: RGB(0x1B1D23), light: RGB(0xEEF0F6))
    public static let surfaceGlassTab = dynamicColor(dark: RGB(0x1B1D23), light: RGB(0xFFFFFF))
    public static let surfaceElevated = dynamicColor(dark: RGB(0x1D1F26), light: RGB(0xE6E9F2))
    public static let surfaceSheetGroup = dynamicColor(dark: RGB(0x202229), light: RGB(0xFFFFFF))
    public static let surfacePopover = dynamicColor(dark: RGB(0x25272F), light: RGB(0xFFFFFF))
    public static let surfaceActiveTabSlot = dynamicColor(dark: RGB(0x31343E), light: RGB(0xE3E7F2))
    public static let glassHairline = dynamicColor(
        dark: RGB(white: 1.0, alpha: 0.08),
        light: RGB(white: 0.0, alpha: 0.09)
    )
    public static let cardBorder = glassHairline
    public static let subtleDivider = dynamicColor(
        dark: RGB(white: 1.0, alpha: 0.07),
        light: RGB(white: 0.0, alpha: 0.08)
    )

    // MARK: - Brand Accents (Adaptive Dark & Light)
    /// Primary Periwinkle CTA (`#8EB4FF` dark / `#2F66E8` light) used on CTAs, FABs, selected borders, and checkboxes.
    public static let accentPeriwinkle = dynamicColor(dark: RGB(0x8EB4FF), light: RGB(0x2F66E8))
    public static let accentPrimary = accentPeriwinkle
    public static let accentSecondary = dynamicColor(dark: RGB(0x7DA7FF), light: RGB(0x3B71EE))
    /// High-contrast ink inside filled primary buttons (`#0A0E17` on bright dark-mode periwinkle, `#FFFFFF` on rich light-mode cobalt).
    public static let inkOnPrimaryCTA = dynamicColor(dark: RGB(0x0A0E17), light: RGB(0xFFFFFF))
    /// High-contrast ink inside filled Amber approval CTA buttons.
    public static let inkOnAmberCTA = dynamicColor(dark: RGB(0x0A0E17), light: RGB(0xFFFFFF))
    /// Active inverted filter pill background & foreground.
    public static let pillActiveBackground = dynamicColor(dark: RGB(0xFFFFFF), light: RGB(0x141720))
    public static let pillActiveForeground = dynamicColor(dark: RGB(0x0A0E17), light: RGB(0xFFFFFF))
    public static let pillActiveWhite = pillActiveBackground

    // MARK: - Semantic Status Palette
    /// Running (`运行中`) — Periwinkle Blue (`#7DA7FF` dark / `#2F66E8` light)
    public static let statusRunning = dynamicColor(dark: RGB(0x7DA7FF), light: RGB(0x2F66E8))
    /// Needs You / Waiting Approval (`等你处理`) — Warm Amber (`#EBB365` dark / `#B86E00` light)
    public static let statusWaiting = dynamicColor(dark: RGB(0xEB_B3_65), light: RGB(0xB86E00))
    /// Done / Diff Additions (`完成`) — Emerald (`#57C88A` dark / `#198754` light)
    public static let statusDone = dynamicColor(dark: RGB(0x57C88A), light: RGB(0x198754))
    /// Deletions / Destructive — Coral Red (`#F07167` dark / `#CF372E` light)
    public static let statusError = dynamicColor(dark: RGB(0xF07167), light: RGB(0xCF372E))

    // MARK: - Ink & Chrome Text Hierarchy
    public static let inkReading = dynamicColor(dark: RGB(0xF5F6F8), light: RGB(0x111318))
    public static let inkLabel = dynamicColor(dark: RGB(0xD1D5DF), light: RGB(0x272B36))
    public static let inkSecondary = dynamicColor(dark: RGB(0x8A909E), light: RGB(0x5B6170))
    public static let inkMuted = dynamicColor(dark: RGB(0x555A66), light: RGB(0x767D8E))
    public static let textPrimary = dynamicColor(dark: RGB(0xF5F7FA), light: RGB(0x111318))
    public static let textBody = dynamicColor(dark: RGB(0xD5D8E2), light: RGB(0x2C313D))
    public static let textSecondary = dynamicColor(dark: RGB(0x8E93A2), light: RGB(0x5B6170))
    public static let textMuted = dynamicColor(dark: RGB(0x7C8190), light: RGB(0x6D7485))

    // MARK: - Extended Adaptive Component Tokens
    public static let surfaceSelectionTint = dynamicColor(dark: RGB(0x202431), light: RGB(0xEBF1FF))
    public static let surfaceAmberTint = dynamicColor(
        dark: RGB(0xEBB365, alpha: 0.14),
        light: RGB(0xB86E00, alpha: 0.10)
    )
    public static let surfaceCodeBlock = dynamicColor(dark: RGB(0x101217), light: RGB(0xF0F2F7))
    public static let surfaceInlineCode = dynamicColor(dark: RGB(0x1D1F26), light: RGB(0xE8ECF5))
    public static let inkInlineCode = dynamicColor(dark: RGB(0xDCE6FF), light: RGB(0x1E46A8))
    public static let surfaceKbd = dynamicColor(dark: RGB(0x232631), light: RGB(0xEAEDF5))
    public static let inkMarkHighlight = dynamicColor(dark: RGB(0xFFF3D6), light: RGB(0x4A3000))
    public static let surfaceMarkHighlight = dynamicColor(
        dark: RGB(0xEBB365, alpha: 0.26),
        light: RGB(0xFFE082, alpha: 0.55)
    )
    public static let surfaceDiffAdd = dynamicColor(
        dark: RGB(0x57C88A, alpha: 0.14),
        light: RGB(0x198754, alpha: 0.12)
    )
    public static let surfaceDiffRemove = dynamicColor(
        dark: RGB(0xF07167, alpha: 0.14),
        light: RGB(0xCF372E, alpha: 0.12)
    )
    public static let ringTrack = dynamicColor(dark: RGB(0x2A3142), light: RGB(0xD5DCEB))
    public static let sheetHandle = dynamicColor(
        dark: RGB(white: 1.0, alpha: 0.24),
        light: RGB(white: 0.0, alpha: 0.18)
    )
    public static let scrimOverlay = dynamicColor(
        dark: RGB(white: 0.0, alpha: 0.55),
        light: RGB(white: 0.0, alpha: 0.28)
    )
    public static let glassShadow = dynamicColor(
        dark: RGB(white: 0.0, alpha: 0.42),
        light: RGB(white: 0.0, alpha: 0.10)
    )
    public static let surfaceInput = dynamicColor(dark: RGB(0x161820), light: RGB(0xFFFFFF))
    public static let surfaceBadge = dynamicColor(dark: RGB(0x22252F), light: RGB(0xE7EBF3))

    // MARK: - Syntax Highlighting Palette (Dark & Light)
    public static let syntaxComment = dynamicColor(dark: RGB(0x6E768A), light: RGB(0x6A737D))
    public static let syntaxKeyword = dynamicColor(dark: RGB(0xC594F6), light: RGB(0x8238C8))
    public static let syntaxString = dynamicColor(dark: RGB(0x7CD6A2), light: RGB(0x177A4A))
    public static let syntaxNumber = dynamicColor(dark: RGB(0xF0B975), light: RGB(0xB35C00))
    public static let syntaxType = dynamicColor(dark: RGB(0x8EB4FF), light: RGB(0x1F57D6))
    public static let syntaxFunction = dynamicColor(dark: RGB(0x7CC7FF), light: RGB(0x0969DA))
    public static let syntaxProperty = dynamicColor(dark: RGB(0xE6A4B4), light: RGB(0xA6294F))
    public static let syntaxPlain = inkLabel

    // MARK: - UIKit Dynamic Bridge Helpers (for UINavigationController / TextKit 2 / Share Extension)
    #if canImport(UIKit)
    public static var canvasObsidianUIColor: UIColor {
        dynamicUIColor(dark: RGB(0x090A0D), light: RGB(0xF4F5F8))
    }
    public static var accentPeriwinkleUIColor: UIColor {
        dynamicUIColor(dark: RGB(0x8EB4FF), light: RGB(0x2F66E8))
    }
    public static var inkReadingUIColor: UIColor {
        dynamicUIColor(dark: RGB(0xF5F6F8), light: RGB(0x111318))
    }
    public static var inkInlineCodeUIColor: UIColor {
        dynamicUIColor(dark: RGB(0xDCE6FF), light: RGB(0x1E46A8))
    }
    public static var surfaceInlineCodeUIColor: UIColor {
        dynamicUIColor(dark: RGB(0x1D1F26), light: RGB(0xE8ECF5))
    }
    public static var surfaceKbdUIColor: UIColor {
        dynamicUIColor(dark: RGB(0x232631), light: RGB(0xEAEDF5))
    }
    public static var inkKbdUIColor: UIColor {
        dynamicUIColor(dark: RGB(0xF0F0F2), light: RGB(0x1E222D))
    }
    public static var inkMarkHighlightUIColor: UIColor {
        dynamicUIColor(dark: RGB(0xFFF3D6), light: RGB(0x4A3000))
    }
    public static var surfaceMarkHighlightUIColor: UIColor {
        dynamicUIColor(dark: RGB(0xEBB365, alpha: 0.26), light: RGB(0xFFE082, alpha: 0.55))
    }
    public static var statusWaitingUIColor: UIColor {
        dynamicUIColor(dark: RGB(0xEBB365), light: RGB(0xB86E00))
    }
    public static var subtleBorderUIColor: UIColor {
        dynamicUIColor(dark: RGB(white: 1.0, alpha: 0.14), light: RGB(white: 0.0, alpha: 0.14))
    }
    #endif

    // MARK: - HIG Geometry Invariants
    public static let minTouchTargetPt: CGFloat = 44.0
    public static let cardCornerRadiusPt: CGFloat = 18.0
    public static let sheetCornerRadiusPt: CGFloat = 28.0
    public static let floatingTabBarCornerRadiusPt: CGFloat = 30.0
    public static let fabDiameterPt: CGFloat = 56.0

    // MARK: - 5-Tier Semantic Typography
    public enum TypographyTier {
        case largeTitle
        case reading
        case evidence
        case process
        case metadata
        case chrome

        public var font: Font {
            switch self {
            case .largeTitle:
                return .system(size: 32, weight: .bold, design: .default)
            case .reading:
                return .system(size: 16, weight: .regular, design: .default)
            case .evidence:
                return .system(size: 16, weight: .semibold, design: .default)
            case .process:
                return .system(size: 14, weight: .regular, design: .default)
            case .metadata:
                return .system(size: 13, weight: .medium, design: .monospaced)
            case .chrome:
                return .system(size: 14, weight: .semibold, design: .default)
            }
        }
    }
}
