package dev.antigravity.android.core.platform

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.LiveProgressPhase
import dev.antigravity.shared.model.LiveProgressSnapshot

/**
 * Pure Kotlin presentation model describing an Android 16 Live Update notification.
 * Verifies promotion invariants deterministically in JVM unit tests without custom RemoteViews
 * or colorized backgrounds (both forbidden for Android 16 promoted ongoing notifications).
 */
data class LiveUpdateRenderSpec(
    val cascadeId: String,
    val title: String,
    val subtitle: String,
    val shortCriticalText: String,
    val totalSegments: Int,
    val completedSegments: Int,
    val requestPromotedOngoing: Boolean,
    val usesCustomRemoteViews: Boolean,
    val isColorized: Boolean,
    val requiresBiometricApprovalAction: Boolean,
    val hasDenyAction: Boolean,
    val hasStopAction: Boolean,
)

/**
 * Tracks per-cascade user notification dismissals so subsequent streaming updates for the same
 * turn do not repost a notification the user explicitly swiped away until the next step begins.
 */
class LiveUpdateDismissTracker {
    private val lock = Any()
    private val dismissedStepByCascade = mutableMapOf<String, Int>()

    fun markUserDismissed(cascadeId: String, stepIndex: Int) {
        synchronized(lock) {
            dismissedStepByCascade[cascadeId] = stepIndex
        }
    }

    fun isSuppressed(cascadeId: String, stepIndex: Int): Boolean = synchronized(lock) {
        val dismissedStep = dismissedStepByCascade[cascadeId] ?: return false
        stepIndex <= dismissedStep
    }

    fun clear(cascadeId: String) {
        synchronized(lock) {
            dismissedStepByCascade.remove(cascadeId)
        }
    }

    fun clearAll() {
        synchronized(lock) {
            dismissedStepByCascade.clear()
        }
    }
}

/**
 * Builds Android 16+ promoted Live Update notifications (`NotificationCompat.ProgressStyle` +
 * `setRequestPromotedOngoing(true)` + `setShortCriticalText`) with graceful fallback to standard
 * progress + `BigTextStyle` notifications on Android 10–15 (`API 29–35`).
 */
object AndroidLiveUpdateBuilder {
    const val CHANNEL_LIVE_PROGRESS: String = "antigravity_live_progress"
    const val CHANNEL_WAITING_ALERTS: String = "antigravity_waiting_alerts"

    const val ACTION_APPROVE_BIOMETRIC: String = "dev.antigravity.android.action.APPROVE_BIOMETRIC"
    const val ACTION_DENY: String = "dev.antigravity.android.action.DENY"
    const val ACTION_STOP: String = "dev.antigravity.android.action.STOP"
    const val ACTION_DISMISSED: String = "dev.antigravity.android.action.LIVE_UPDATE_DISMISSED"

    const val EXTRA_CASCADE_ID: String = "dev.antigravity.android.extra.CASCADE_ID"
    const val EXTRA_STEP_INDEX: String = "dev.antigravity.android.extra.STEP_INDEX"

    private const val SEGMENT_UNIT: Int = 10
    private const val COLOR_RUNNING: Int = 0xFF7DA7FF.toInt()
    private const val COLOR_WAITING: Int = 0xFFEBB365.toInt()
    private const val COLOR_DONE: Int = 0xFF57C88A.toInt()
    private const val COLOR_TRACK: Int = 0xFF2A3142.toInt()

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        // Promoted ongoing notifications must not use IMPORTANCE_MIN.
        val progressChannel = NotificationChannel(
            CHANNEL_LIVE_PROGRESS,
            "Agent Live Progress",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Real-time agent execution progress and Android 16 Live Updates"
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        val waitingChannel = NotificationChannel(
            CHANNEL_WAITING_ALERTS,
            "Biometric Approval Gates",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "High-priority alerts when an agent pauses for command or plan approval"
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        manager.createNotificationChannel(progressChannel)
        manager.createNotificationChannel(waitingChannel)
    }

    fun canPostPromotedNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 36) return false
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        return runCatching { manager.canPostPromotedNotifications() }.getOrDefault(false)
    }

    fun buildRenderSpec(snapshot: LiveProgressSnapshot): LiveUpdateRenderSpec {
        val totalSegments = snapshot.totalSteps.coerceAtLeast(1)
        val completedSegments = when (snapshot.phase) {
            LiveProgressPhase.COMPLETED -> totalSegments
            LiveProgressPhase.RUNNING, LiveProgressPhase.WAITING_APPROVAL ->
                snapshot.currentStepIndex.coerceIn(0, totalSegments)
        }

        val title = snapshot.cascadeTitle.ifBlank {
            snapshot.workspaceName.ifBlank { "Antigravity Agent" }
        }

        val subtitle = when (snapshot.phase) {
            LiveProgressPhase.RUNNING ->
                snapshot.activeToolAction.ifBlank { "${snapshot.workspaceName} · ${snapshot.hostName}" }

            LiveProgressPhase.WAITING_APPROVAL ->
                snapshot.pendingApprovalCommand?.takeIf { it.isNotBlank() }
                    ?: snapshot.activeToolAction.ifBlank { "Approval required · ${snapshot.workspaceName}" }

            LiveProgressPhase.COMPLETED ->
                "Completed on ${snapshot.hostName} · +${snapshot.additions} -${snapshot.deletions}"
        }

        val shortCriticalText = when (snapshot.phase) {
            LiveProgressPhase.RUNNING -> "${snapshot.currentStepIndex}/$totalSegments"
            LiveProgressPhase.WAITING_APPROVAL -> "Approve"
            LiveProgressPhase.COMPLETED -> "+${snapshot.additions} -${snapshot.deletions}"
        }

        return LiveUpdateRenderSpec(
            cascadeId = snapshot.cascadeId,
            title = title,
            subtitle = subtitle,
            shortCriticalText = shortCriticalText,
            totalSegments = totalSegments,
            completedSegments = completedSegments,
            requestPromotedOngoing = true,
            usesCustomRemoteViews = false,
            isColorized = false,
            requiresBiometricApprovalAction = snapshot.phase == LiveProgressPhase.WAITING_APPROVAL,
            hasDenyAction = snapshot.phase == LiveProgressPhase.WAITING_APPROVAL,
            hasStopAction = snapshot.phase == LiveProgressPhase.RUNNING,
        )
    }

    fun buildNotification(
        context: Context,
        snapshot: LiveProgressSnapshot,
        contentIntent: PendingIntent? = null,
        approveIntent: PendingIntent? = null,
        denyIntent: PendingIntent? = null,
        stopIntent: PendingIntent? = null,
        dismissIntent: PendingIntent? = null,
    ): Notification {
        runCatching { ensureChannels(context) }

        val spec = buildRenderSpec(snapshot)
        val channelId = if (snapshot.phase == LiveProgressPhase.WAITING_APPROVAL) {
            CHANNEL_WAITING_ALERTS
        } else {
            CHANNEL_LIVE_PROGRESS
        }

        val smallIcon = when (snapshot.phase) {
            LiveProgressPhase.RUNNING -> android.R.drawable.stat_notify_sync
            LiveProgressPhase.WAITING_APPROVAL -> android.R.drawable.ic_dialog_alert
            LiveProgressPhase.COMPLETED -> android.R.drawable.stat_sys_download_done
        }

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(smallIcon)
            .setContentTitle(spec.title)
            .setContentText(spec.subtitle)
            .setSubText("${snapshot.workspaceName} · ${snapshot.hostName}")
            .setOngoing(snapshot.phase != LiveProgressPhase.COMPLETED)
            .setOnlyAlertOnce(snapshot.phase != LiveProgressPhase.WAITING_APPROVAL)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColorized(false)
            .setRequestPromotedOngoing(spec.requestPromotedOngoing)
            .setShortCriticalText(spec.shortCriticalText)

        if (contentIntent != null) {
            builder.setContentIntent(contentIntent)
        }
        if (dismissIntent != null) {
            builder.setDeleteIntent(dismissIntent)
        }

        if (Build.VERSION.SDK_INT >= 36) {
            val segments = (0 until spec.totalSegments).map { index ->
                val segmentColor = when {
                    snapshot.phase == LiveProgressPhase.COMPLETED -> COLOR_DONE
                    index < spec.completedSegments -> COLOR_RUNNING
                    index == spec.completedSegments && snapshot.phase == LiveProgressPhase.WAITING_APPROVAL ->
                        COLOR_WAITING
                    else -> COLOR_TRACK
                }
                NotificationCompat.ProgressStyle.Segment(SEGMENT_UNIT)
                    .setColor(segmentColor)
            }
            val progressStyle = NotificationCompat.ProgressStyle()
                .setStyledByProgress(true)
                .setProgressSegments(segments)
                .setProgress(spec.completedSegments * SEGMENT_UNIT)
            builder.setStyle(progressStyle)
        } else {
            builder.setProgress(spec.totalSegments, spec.completedSegments, false)
            builder.setStyle(
                NotificationCompat.BigTextStyle()
                    .setBigContentTitle(spec.title)
                    .bigText(spec.subtitle),
            )
        }

        if (spec.requiresBiometricApprovalAction && approveIntent != null) {
            builder.addAction(
                android.R.drawable.ic_lock_lock,
                "Allow",
                approveIntent,
            )
        }
        if (spec.hasDenyAction && denyIntent != null) {
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Deny",
                denyIntent,
            )
        }
        if (spec.hasStopAction && stopIntent != null) {
            builder.addAction(
                android.R.drawable.ic_media_pause,
                "Stop",
                stopIntent,
            )
        }

        return builder.build()
    }

    /**
     * Suppresses completion/cancellation alerts whenever a turn was manually cancelled by the user
     * (matching Desktop v2.22+ and iOS behavior), while alerting on waiting approval gates, errors,
     * and natural completion transitions.
     */
    fun shouldNotifyOnStatusTransition(
        previousStatus: CortexStepStatus,
        nextStatus: CortexStepStatus,
        wasManuallyCancelled: Boolean,
    ): Boolean {
        if (wasManuallyCancelled) return false
        if (previousStatus == nextStatus) return false
        return when (nextStatus) {
            CortexStepStatus.WAITING,
            CortexStepStatus.BLOCKED,
            CortexStepStatus.ERROR,
            -> true

            CortexStepStatus.DONE -> previousStatus == CortexStepStatus.IN_PROGRESS ||
                previousStatus == CortexStepStatus.WAITING ||
                previousStatus == CortexStepStatus.PENDING

            CortexStepStatus.CANCELLED,
            CortexStepStatus.IN_PROGRESS,
            CortexStepStatus.PENDING,
            CortexStepStatus.UNSPECIFIED,
            -> false
        }
    }
}
