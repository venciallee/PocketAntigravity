package dev.antigravity.android

import android.content.Context
import dev.antigravity.android.core.platform.AndroidNetworkReachabilityMonitor
import dev.antigravity.android.core.platform.AndroidPowerStateProvider
import dev.antigravity.android.core.platform.AndroidPreferencesStore
import dev.antigravity.android.core.platform.AndroidProjectionStorage
import dev.antigravity.android.core.platform.AndroidSecretStore
import dev.antigravity.android.core.platform.BiometricApprovalController
import dev.antigravity.android.core.platform.LiveUpdateDismissTracker
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * Pure Kotlin application dependency graph wiring `:shared:core-domain` ([AntigravityCoreCoordinator])
 * to native Android platform ports in `:apps:android:core-platform`.
 */
object AppGraph {
    private val lock = Any()

    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val dismissTracker: LiveUpdateDismissTracker = LiveUpdateDismissTracker()
    val biometricController: BiometricApprovalController = BiometricApprovalController()

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var coordinatorInstance: AntigravityCoreCoordinator? = null

    @Volatile
    private var secretStoreInstance: AndroidSecretStore? = null

    @Volatile
    private var preferencesStoreInstance: AndroidPreferencesStore? = null

    @Volatile
    private var projectionStorageInstance: AndroidProjectionStorage? = null

    fun init(context: Context) {
        val ctx = context.applicationContext
        if (appContext != null && coordinatorInstance != null) return
        synchronized(lock) {
            if (appContext == null) {
                appContext = ctx
            }
            if (coordinatorInstance == null) {
                val secrets = AndroidSecretStore(ctx).also { secretStoreInstance = it }
                val prefs = AndroidPreferencesStore(ctx).also { preferencesStoreInstance = it }
                val storage = AndroidProjectionStorage(ctx).also { projectionStorageInstance = it }
                val network = AndroidNetworkReachabilityMonitor(ctx)
                val power = AndroidPowerStateProvider(ctx)

                coordinatorInstance = AntigravityCoreCoordinator(
                    secretStore = secrets,
                    networkMonitor = network,
                    powerStateProvider = power,
                    preferencesStore = prefs,
                    projectionStorage = storage,
                    scope = appScope,
                )
            }
        }
    }

    fun coordinator(context: Context): AntigravityCoreCoordinator {
        coordinatorInstance?.let { return it }
        init(context)
        return requireNotNull(coordinatorInstance)
    }

    fun secretStore(context: Context): AndroidSecretStore {
        secretStoreInstance?.let { return it }
        init(context)
        return requireNotNull(secretStoreInstance)
    }

    fun preferencesStore(context: Context): AndroidPreferencesStore {
        preferencesStoreInstance?.let { return it }
        init(context)
        return requireNotNull(preferencesStoreInstance)
    }

    fun projectionStorage(context: Context): AndroidProjectionStorage {
        projectionStorageInstance?.let { return it }
        init(context)
        return requireNotNull(projectionStorageInstance)
    }
}
