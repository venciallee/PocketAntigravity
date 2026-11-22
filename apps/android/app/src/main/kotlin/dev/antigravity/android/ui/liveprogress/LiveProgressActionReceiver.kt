package dev.antigravity.android.ui.liveprogress

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.antigravity.android.AppGraph
import dev.antigravity.android.core.platform.AndroidLiveUpdateBuilder
import dev.antigravity.shared.model.InteractionDecision
import kotlinx.coroutines.launch

/**
 * Handles notification action taps (`ACTION_DENY`, `ACTION_STOP`) and notification swipe-away
 * dismissal (`ACTION_DISMISSED`), preserving Android 16 user-dismissal suppression and
 * manual-cancellation completion-alert suppression.
 */
class LiveProgressActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val cascadeId = intent.getStringExtra(AndroidLiveUpdateBuilder.EXTRA_CASCADE_ID).orEmpty()
        val stepIndex = intent.getIntExtra(AndroidLiveUpdateBuilder.EXTRA_STEP_INDEX, 0)

        when (action) {
            AndroidLiveUpdateBuilder.ACTION_DISMISSED -> {
                if (cascadeId.isNotEmpty()) {
                    AppGraph.dismissTracker.markUserDismissed(cascadeId, stepIndex)
                }
            }

            AndroidLiveUpdateBuilder.ACTION_DENY -> {
                if (cascadeId.isEmpty()) return
                val pendingResult = goAsync()
                val coordinator = AppGraph.coordinator(context)
                AppGraph.appScope.launch {
                    try {
                        runCatching {
                            coordinator.resolveWaitingInteraction(
                                cascadeId = cascadeId,
                                stepIndex = stepIndex,
                                decision = InteractionDecision.Reject,
                            )
                        }
                        context.getSystemService(NotificationManager::class.java)
                            ?.cancel(AgentProgressForegroundService.NOTIFICATION_ID)
                    } finally {
                        pendingResult.finish()
                    }
                }
            }

            AndroidLiveUpdateBuilder.ACTION_STOP -> {
                if (cascadeId.isEmpty()) {
                    AgentProgressForegroundService.stop(context)
                    return
                }
                val pendingResult = goAsync()
                val coordinator = AppGraph.coordinator(context)
                AppGraph.appScope.launch {
                    try {
                        // Mark dismissed and cancel turn silently without emitting a "Task completed" alert.
                        AppGraph.dismissTracker.markUserDismissed(cascadeId, stepIndex)
                        runCatching {
                            coordinator.cancelActiveTurn(cascadeId)
                        }
                        AgentProgressForegroundService.stop(context)
                    } finally {
                        pendingResult.finish()
                    }
                }
            }
        }
    }
}
