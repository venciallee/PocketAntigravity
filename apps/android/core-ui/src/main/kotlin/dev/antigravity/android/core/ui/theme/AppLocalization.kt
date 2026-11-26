package dev.antigravity.android.core.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.compositionLocalOf
import dev.antigravity.shared.model.AppLanguage

/**
 * Reactive Compose [CompositionLocal] carrying the active in-app display language (`English` / `简体中文`).
 *
 * Changing `coordinator.settingsStore.setAppLanguage(...)` updates `AntigravityTheme` immediately
 * and recomposes all visible Composables in-place without recreating the Activity.
 */
val LocalAppLanguage = compositionLocalOf { AppLanguage.ENGLISH }

/**
 * Returns [zh] when the active [LocalAppLanguage] is Simplified Chinese, otherwise [en].
 */
@Composable
@ReadOnlyComposable
fun tr(en: String, zh: String): String =
    if (LocalAppLanguage.current.isChinese) zh else en
