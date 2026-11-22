package dev.antigravity.android

import android.app.Application
import dev.antigravity.android.core.platform.AndroidLiveUpdateBuilder
import kotlinx.coroutines.launch

/**
 * Android [Application] entrypoint initializing [AppGraph], Android 16 notification channels,
 * and offline projection cache hydration.
 */
class AntigravityApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        AppGraph.init(this)
        runCatching { AndroidLiveUpdateBuilder.ensureChannels(this) }
        val coordinator = AppGraph.coordinator(this)
        AppGraph.appScope.launch {
            runCatching { coordinator.hydrateOfflineCache() }
        }
    }
}
