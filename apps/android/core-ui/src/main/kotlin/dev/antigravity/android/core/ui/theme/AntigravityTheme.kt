package dev.antigravity.android.core.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.shared.model.AppThemePreset

/**
 * Extended Antigravity semantic design tokens providing 1:1 color & status parity across
 * Matte OLED Obsidian, Nord, Everforest Dark, and Everforest Light presets in both Dark
 * and Light themes, while locking semantic status hues even when Material You Dynamic Color
 * is enabled on Android 12+.
 */
@Immutable
data class AntigravityExtendedColors(
    val isDark: Boolean,
    // Surfaces & Borders
    val canvasObsidian: Color,
    val surfaceObsidian: Color,
    val surfaceCard: Color,
    val surfaceSheet: Color,
    val surfacePill: Color,
    val surfaceSubtleBox: Color,
    val surfaceElevated: Color,
    val surfaceSheetGroup: Color,
    val surfacePopover: Color,
    val surfaceActiveTab: Color,
    val cardBorder: Color,
    val subtleDivider: Color,
    // Brand Accents & CTAs
    val accentPeriwinkle: Color,
    val accentSecondary: Color,
    val inkOnPrimaryCta: Color,
    val inkOnAmberCta: Color,
    val pillActiveBackground: Color,
    val pillActiveForeground: Color,
    // Locked Semantic Status Palette (Cross-Platform Invariant)
    val statusRunning: Color,
    val statusWaiting: Color,
    val statusDone: Color,
    val statusError: Color,
    // Ink & Text Hierarchy
    val inkReading: Color,
    val inkLabel: Color,
    val inkSecondary: Color,
    val inkMuted: Color,
    // Extended Component Tokens
    val surfaceSelectionTint: Color,
    val surfaceAmberTint: Color,
    val surfaceCodeBlock: Color,
    val surfaceInlineCode: Color,
    val inkInlineCode: Color,
    val surfaceDiffAdd: Color,
    val surfaceDiffRemove: Color,
    val ringTrack: Color,
    // Syntax Highlighting Palette
    val syntaxComment: Color,
    val syntaxKeyword: Color,
    val syntaxString: Color,
    val syntaxNumber: Color,
    val syntaxType: Color,
    val syntaxFunction: Color,
    val syntaxProperty: Color,
    // Additional Rich Markdown & Chrome Tokens
    val surfaceKbd: Color = if (isDark) Color(0xFF232631) else Color(0xFFEAEDF5),
    val inkKbd: Color = if (isDark) Color(0xFFF0F0F2) else Color(0xFF1E222D),
    val surfaceMarkHighlight: Color = if (isDark) Color(0xFFEBB365).copy(alpha = 0.26f) else Color(0xFFFFE082).copy(alpha = 0.55f),
    val inkMarkHighlight: Color = if (isDark) Color(0xFFFFF3D6) else Color(0xFF4A3000),
    val surfaceInput: Color = if (isDark) Color(0xFF161820) else Color(0xFFFFFFFF),
    val surfaceBadge: Color = if (isDark) Color(0xFF22252F) else Color(0xFFE7EBF3),
    val sheetHandle: Color = if (isDark) Color.White.copy(alpha = 0.24f) else Color.Black.copy(alpha = 0.18f),
) {
    val canvasBackgroundHex: Int
        get() = canvasObsidian.toArgb()

    val accentPeriwinkleHex: Int
        get() = accentPeriwinkle.toArgb()

    val statusRunningHex: Int
        get() = statusRunning.toArgb()

    val statusWaitingHex: Int
        get() = statusWaiting.toArgb()

    val statusDoneHex: Int
        get() = statusDone.toArgb()

    val statusErrorHex: Int
        get() = statusError.toArgb()
}

/**
 * Normative Android Material 3 geometry & color token factory aligned with `AntigravityTheme.swift`.
 */
object AntigravityDesignTokens {
    const val MIN_TOUCH_TARGET_DP: Int = 48

    val MinTouchTarget = MIN_TOUCH_TARGET_DP.dp
    val CardCornerRadius = 18.dp
    val SheetCornerRadius = 28.dp
    val PillCornerRadius = 100.dp
    val FabCornerRadius = 16.dp
    val FabSize = 56.dp

    // Locked cross-platform semantic status colors (Dark, UE v2.1 aligned)
    private val DarkStatusRunning = Color(0xFF7DA7FF)
    private val DarkStatusWaiting = Color(0xFFF2B866)
    private val DarkStatusDone = Color(0xFF6FD8A6)
    private val DarkStatusError = Color(0xFFF07167)

    // Locked cross-platform semantic status colors (Light, WCAG AA >= 4.5:1)
    private val LightStatusRunning = Color(0xFF2F66E8)
    private val LightStatusWaiting = Color(0xFFB86E00)
    private val LightStatusDone = Color(0xFF198754)
    private val LightStatusError = Color(0xFFCF372E)

    private val ObsidianDark = AntigravityExtendedColors(
        isDark = true,
        canvasObsidian = Color(0xFF111113),
        surfaceObsidian = Color(0xFF161619),
        surfaceCard = Color(0xFF1B1B1E),
        surfaceSheet = Color(0xFF1B1B1E),
        surfacePill = Color(0xFF1B1B1E),
        surfaceSubtleBox = Color(0xFF212125),
        surfaceElevated = Color(0xFF212125),
        surfaceSheetGroup = Color(0xFF212125),
        surfacePopover = Color(0xFF26262B),
        surfaceActiveTab = Color(0xFF24324A),
        cardBorder = Color.White.copy(alpha = 0.08f),
        subtleDivider = Color.White.copy(alpha = 0.07f),
        accentPeriwinkle = Color(0xFF8DB8FF),
        accentSecondary = Color(0xFF7DA7FF),
        inkOnPrimaryCta = Color(0xFF0A0E17),
        inkOnAmberCta = Color(0xFF0A0E17),
        pillActiveBackground = Color(0xFF24324A),
        pillActiveForeground = Color(0xFFE6EEFF),
        statusRunning = DarkStatusRunning,
        statusWaiting = DarkStatusWaiting,
        statusDone = DarkStatusDone,
        statusError = DarkStatusError,
        inkReading = Color(0xFFF2F2F5),
        inkLabel = Color(0xFFD6D6DC),
        inkSecondary = Color(0xFF9A9AA3),
        inkMuted = Color(0xFF767680),
        surfaceSelectionTint = Color(0xFF24324A),
        surfaceAmberTint = Color(0xFF241E14),
        surfaceCodeBlock = Color(0xFF141417),
        surfaceInlineCode = Color(0xFF212125),
        inkInlineCode = Color(0xFFDCE6FF),
        surfaceDiffAdd = DarkStatusDone.copy(alpha = 0.14f),
        surfaceDiffRemove = DarkStatusError.copy(alpha = 0.14f),
        ringTrack = Color(0xFF2E2E34),
        syntaxComment = Color(0xFF6E768A),
        syntaxKeyword = Color(0xFFC594F6),
        syntaxString = Color(0xFF6FD8A6),
        syntaxNumber = Color(0xFFF2B866),
        syntaxType = Color(0xFF8DB8FF),
        syntaxFunction = Color(0xFF7CC7FF),
        syntaxProperty = Color(0xFFE6A4B4),
    )

    private val ObsidianLight = AntigravityExtendedColors(
        isDark = false,
        canvasObsidian = Color(0xFFF4F5F8),
        surfaceObsidian = Color(0xFFECEEF4),
        surfaceCard = Color(0xFFFFFFFF),
        surfaceSheet = Color(0xFFF6F7FA),
        surfacePill = Color(0xFFE8EBF2),
        surfaceSubtleBox = Color(0xFFEEF0F6),
        surfaceElevated = Color(0xFFE6E9F2),
        surfaceSheetGroup = Color(0xFFFFFFFF),
        surfacePopover = Color(0xFFFFFFFF),
        surfaceActiveTab = Color(0xFFE3E7F2),
        cardBorder = Color.Black.copy(alpha = 0.09f),
        subtleDivider = Color.Black.copy(alpha = 0.08f),
        accentPeriwinkle = Color(0xFF2F66E8),
        accentSecondary = Color(0xFF3B71EE),
        inkOnPrimaryCta = Color(0xFFFFFFFF),
        inkOnAmberCta = Color(0xFFFFFFFF),
        pillActiveBackground = Color(0xFF141720),
        pillActiveForeground = Color(0xFFFFFFFF),
        statusRunning = LightStatusRunning,
        statusWaiting = LightStatusWaiting,
        statusDone = LightStatusDone,
        statusError = LightStatusError,
        inkReading = Color(0xFF111318),
        inkLabel = Color(0xFF272B36),
        inkSecondary = Color(0xFF5B6170),
        inkMuted = Color(0xFF64748B),
        surfaceSelectionTint = Color(0xFFEBF1FF),
        surfaceAmberTint = LightStatusWaiting.copy(alpha = 0.10f),
        surfaceCodeBlock = Color(0xFFF0F2F7),
        surfaceInlineCode = Color(0xFFE8ECF5),
        inkInlineCode = Color(0xFF1E46A8),
        surfaceDiffAdd = LightStatusDone.copy(alpha = 0.12f),
        surfaceDiffRemove = LightStatusError.copy(alpha = 0.12f),
        ringTrack = Color(0xFFD5DCEB),
        syntaxComment = Color(0xFF6A737D),
        syntaxKeyword = Color(0xFF8238C8),
        syntaxString = Color(0xFF177A4A),
        syntaxNumber = Color(0xFFB35C00),
        syntaxType = Color(0xFF1F57D6),
        syntaxFunction = Color(0xFF0969DA),
        syntaxProperty = Color(0xFFA6294F),
    )

    private val NordDark = ObsidianDark.copy(
        canvasObsidian = Color(0xFF2E3440),
        surfaceObsidian = Color(0xFF353C4A),
        surfaceCard = Color(0xFF3B4252),
        surfaceSheet = Color(0xFF363D4C),
        surfacePill = Color(0xFF434C5E),
        surfaceSubtleBox = Color(0xFF404859),
        surfaceElevated = Color(0xFF434C5E),
        surfaceSheetGroup = Color(0xFF434C5E),
        surfacePopover = Color(0xFF4C566A),
        surfaceActiveTab = Color(0xFF4C566A),
        cardBorder = Color(0xFFD8DEE9).copy(alpha = 0.12f),
        subtleDivider = Color(0xFFD8DEE9).copy(alpha = 0.09f),
        accentPeriwinkle = Color(0xFF88C0D0),
        accentSecondary = Color(0xFF81A1C1),
        inkOnPrimaryCta = Color(0xFF2E3440),
        inkOnAmberCta = Color(0xFF2E3440),
        pillActiveBackground = Color(0xFFECEFF4),
        pillActiveForeground = Color(0xFF2E3440),
        inkReading = Color(0xFFECEFF4),
        inkLabel = Color(0xFFD8DEE9),
        inkSecondary = Color(0xFFA5B1C6),
        inkMuted = Color(0xFF818DA3),
        surfaceSelectionTint = Color(0xFF434C5E),
        surfaceCodeBlock = Color(0xFF272C36),
        surfaceInlineCode = Color(0xFF434C5E),
        inkInlineCode = Color(0xFF8FBCBB),
        ringTrack = Color(0xFF4C566A),
        surfaceInput = Color(0xFF353C4A),
        surfaceBadge = Color(0xFF434C5E),
    )

    private val NordLight = ObsidianLight.copy(
        canvasObsidian = Color(0xFFECEFF4),
        surfaceObsidian = Color(0xFFE5E9F0),
        surfaceCard = Color(0xFFF8FAFC),
        surfaceSheet = Color(0xFFF1F4F9),
        surfacePill = Color(0xFFD8DEE9),
        surfaceSubtleBox = Color(0xFFE5E9F0),
        surfaceElevated = Color(0xFFD8DEE9),
        surfaceSheetGroup = Color(0xFFF8FAFC),
        surfacePopover = Color(0xFFFFFFFF),
        surfaceActiveTab = Color(0xFFD8DEE9),
        accentPeriwinkle = Color(0xFF5E81AC),
        accentSecondary = Color(0xFF4C6F99),
        inkReading = Color(0xFF2E3440),
        inkLabel = Color(0xFF3B4252),
        inkSecondary = Color(0xFF4C566A),
        inkMuted = Color(0xFF67748E),
        surfaceSelectionTint = Color(0xFFDCE7F5),
        surfaceCodeBlock = Color(0xFFE5E9F0),
        surfaceInlineCode = Color(0xFFD8DEE9),
        inkInlineCode = Color(0xFF3B5A82),
        ringTrack = Color(0xFFC8D2E3),
        surfaceInput = Color(0xFFFFFFFF),
        surfaceBadge = Color(0xFFD8DEE9),
    )

    private val EverforestDark = ObsidianDark.copy(
        canvasObsidian = Color(0xFF272E33),
        surfaceObsidian = Color(0xFF2B3339),
        surfaceCard = Color(0xFF2E383C),
        surfaceSheet = Color(0xFF2D353B),
        surfacePill = Color(0xFF374145),
        surfaceSubtleBox = Color(0xFF343F44),
        surfaceElevated = Color(0xFF374145),
        surfaceSheetGroup = Color(0xFF374145),
        surfacePopover = Color(0xFF414B50),
        surfaceActiveTab = Color(0xFF495156),
        cardBorder = Color(0xFFD3C6AA).copy(alpha = 0.12f),
        subtleDivider = Color(0xFFD3C6AA).copy(alpha = 0.09f),
        accentPeriwinkle = Color(0xFFA7C080),
        accentSecondary = Color(0xFF83C092),
        inkOnPrimaryCta = Color(0xFF232A2E),
        inkOnAmberCta = Color(0xFF232A2E),
        pillActiveBackground = Color(0xFFD3C6AA),
        pillActiveForeground = Color(0xFF232A2E),
        inkReading = Color(0xFFD3C6AA),
        inkLabel = Color(0xFFC5B99E),
        inkSecondary = Color(0xFF9DA9A0),
        inkMuted = Color(0xFF859289),
        surfaceSelectionTint = Color(0xFF3C4841),
        surfaceCodeBlock = Color(0xFF232A2E),
        surfaceInlineCode = Color(0xFF374145),
        inkInlineCode = Color(0xFFA7C080),
        ringTrack = Color(0xFF495156),
        surfaceInput = Color(0xFF2B3339),
        surfaceBadge = Color(0xFF374145),
    )

    private val EverforestLight = ObsidianLight.copy(
        canvasObsidian = Color(0xFFFDF6E3),
        surfaceObsidian = Color(0xFFF4F0D9),
        surfaceCard = Color(0xFFFFFBEF),
        surfaceSheet = Color(0xFFF8F4E2),
        surfacePill = Color(0xFFEDE8D0),
        surfaceSubtleBox = Color(0xFFF3EED9),
        surfaceElevated = Color(0xFFEAE4CA),
        surfaceSheetGroup = Color(0xFFFFFBEF),
        surfacePopover = Color(0xFFFFFDF5),
        surfaceActiveTab = Color(0xFFE5DFC5),
        cardBorder = Color(0xFF5C6A72).copy(alpha = 0.14f),
        subtleDivider = Color(0xFF5C6A72).copy(alpha = 0.10f),
        accentPeriwinkle = Color(0xFF3A94C5),
        accentSecondary = Color(0xFF35A77C),
        inkOnPrimaryCta = Color(0xFFFFFFFF),
        inkOnAmberCta = Color(0xFFFFFFFF),
        pillActiveBackground = Color(0xFF4A5860),
        pillActiveForeground = Color(0xFFFFFBEF),
        inkReading = Color(0xFF47545B),
        inkLabel = Color(0xFF5C6A72),
        inkSecondary = Color(0xFF708089),
        inkMuted = Color(0xFF829181),
        surfaceSelectionTint = Color(0xFFE6EFE8),
        surfaceCodeBlock = Color(0xFFF2ECE0),
        surfaceInlineCode = Color(0xFFEAE4CA),
        inkInlineCode = Color(0xFF2D6E94),
        ringTrack = Color(0xFFDCD6BE),
        surfaceInput = Color(0xFFFFFBEF),
        surfaceBadge = Color(0xFFEAE4CA),
    )

    fun extendedColors(
        preset: AppThemePreset = AppThemePreset.OBSIDIAN,
        darkTheme: Boolean = true,
    ): AntigravityExtendedColors = when (preset) {
        AppThemePreset.OBSIDIAN -> if (darkTheme) ObsidianDark else ObsidianLight
        AppThemePreset.NORD -> if (darkTheme) NordDark else NordLight
        AppThemePreset.EVERFOREST_DARK -> EverforestDark
        AppThemePreset.EVERFOREST_LIGHT -> EverforestLight
    }
}

val LocalAntigravityColors = staticCompositionLocalOf {
    AntigravityDesignTokens.extendedColors(preset = AppThemePreset.OBSIDIAN, darkTheme = true)
}

val MaterialTheme.antigravityColors: AntigravityExtendedColors
    @Composable
    @ReadOnlyComposable
    get() = LocalAntigravityColors.current

/**
 * 5-Tier Semantic Typography aligned with PRD Section 1.2:
 * - Large Title: `displaySmall` / `headlineMedium`
 * - Tier 1 (Reading): `bodyLarge` (16sp / 24sp Normal)
 * - Tier 2 (Evidence): `titleSmall` (14sp / 20sp SemiBold)
 * - Tier 3 (Process): `bodyMedium` (13sp / 18sp Normal)
 * - Tier 4 (Metadata): `labelSmall` (11sp / 14sp Medium Monospace)
 * - Tier 5 (Chrome): `labelLarge` (13sp / 18sp SemiBold)
 */
val AntigravityTypography = Typography(
    displaySmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 32.sp,
        lineHeight = 38.sp,
        letterSpacing = (-0.5).sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 26.sp,
        lineHeight = 32.sp,
        letterSpacing = (-0.3).sp,
    ),
    headlineSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 22.sp,
        lineHeight = 28.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        lineHeight = 26.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 22.sp,
    ),
    titleSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 18.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 13.sp,
        lineHeight = 18.sp,
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        letterSpacing = 0.2.sp,
    ),
)

val AntigravityShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(18.dp),
    large = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

private fun AntigravityExtendedColors.toMaterialColorScheme(): ColorScheme = if (isDark) {
    darkColorScheme(
        primary = accentPeriwinkle,
        onPrimary = inkOnPrimaryCta,
        primaryContainer = surfaceSelectionTint,
        onPrimaryContainer = accentPeriwinkle,
        secondary = accentSecondary,
        onSecondary = inkOnPrimaryCta,
        secondaryContainer = surfaceElevated,
        onSecondaryContainer = inkLabel,
        tertiary = statusWaiting,
        onTertiary = inkOnAmberCta,
        tertiaryContainer = surfaceAmberTint,
        onTertiaryContainer = statusWaiting,
        error = statusError,
        onError = inkOnPrimaryCta,
        errorContainer = surfaceDiffRemove,
        onErrorContainer = statusError,
        background = canvasObsidian,
        onBackground = inkReading,
        surface = canvasObsidian,
        onSurface = inkReading,
        surfaceVariant = surfaceElevated,
        onSurfaceVariant = inkSecondary,
        surfaceContainerLowest = canvasObsidian,
        surfaceContainerLow = surfaceObsidian,
        surfaceContainer = surfaceCard,
        surfaceContainerHigh = surfaceElevated,
        surfaceContainerHighest = surfacePopover,
        outline = inkMuted,
        outlineVariant = cardBorder,
    )
} else {
    lightColorScheme(
        primary = accentPeriwinkle,
        onPrimary = inkOnPrimaryCta,
        primaryContainer = surfaceSelectionTint,
        onPrimaryContainer = accentPeriwinkle,
        secondary = accentSecondary,
        onSecondary = inkOnPrimaryCta,
        secondaryContainer = surfaceElevated,
        onSecondaryContainer = inkLabel,
        tertiary = statusWaiting,
        onTertiary = inkOnAmberCta,
        tertiaryContainer = surfaceAmberTint,
        onTertiaryContainer = statusWaiting,
        error = statusError,
        onError = inkOnPrimaryCta,
        errorContainer = surfaceDiffRemove,
        onErrorContainer = statusError,
        background = canvasObsidian,
        onBackground = inkReading,
        surface = canvasObsidian,
        onSurface = inkReading,
        surfaceVariant = surfaceElevated,
        onSurfaceVariant = inkSecondary,
        surfaceContainerLowest = surfaceCard,
        surfaceContainerLow = surfaceSheet,
        surfaceContainer = surfaceCard,
        surfaceContainerHigh = surfaceElevated,
        surfaceContainerHighest = surfaceActiveTab,
        outline = inkMuted,
        outlineVariant = cardBorder,
    )
}

@Composable
fun AntigravityTheme(
    preset: AppThemePreset = AppThemePreset.OBSIDIAN,
    darkTheme: Boolean = isSystemInDarkTheme(),
    useDynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val resolvedDark = when (preset) {
        AppThemePreset.EVERFOREST_DARK -> true
        AppThemePreset.EVERFOREST_LIGHT -> false
        AppThemePreset.OBSIDIAN, AppThemePreset.NORD -> darkTheme
    }

    val extendedColors = AntigravityDesignTokens.extendedColors(
        preset = preset,
        darkTheme = resolvedDark,
    )

    val colorScheme = if (useDynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val context = LocalContext.current
        val dynamicScheme = if (resolvedDark) {
            dynamicDarkColorScheme(context)
        } else {
            dynamicLightColorScheme(context)
        }
        // Keep semantic error & approval roles consistent while adopting Material You surfaces/accents
        dynamicScheme.copy(
            error = extendedColors.statusError,
            tertiary = extendedColors.statusWaiting,
        )
    } else {
        extendedColors.toMaterialColorScheme()
    }

    CompositionLocalProvider(
        LocalAntigravityColors provides extendedColors,
    ) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = AntigravityTypography,
            shapes = AntigravityShapes,
            content = content,
        )
    }
}
