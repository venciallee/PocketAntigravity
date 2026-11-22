package dev.antigravity.android.ui.liveprogress

import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import dev.antigravity.android.AppGraph
import dev.antigravity.android.MainActivity
import dev.antigravity.android.core.platform.AndroidLiveUpdateBuilder
import dev.antigravity.shared.model.LiveProgressPhase
import dev.antigravity.shared.model.LiveProgressSnapshot
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Foreground Service (`dataSync`) owning Android 16+ promoted Live Update notifications
 * (`NotificationCompat.ProgressStyle`) and Android 10–15 progress notification fallback.
 */
class AgentProgressForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_SERVICE) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val rawSnapshot = intent?.getStringExtra(EXTRA_SNAPSHOT_JSON)
        val snapshot = rawSnapshot?.let { raw ->
            runCatching { ServiceJson.decodeFromString<LiveProgressSnapshot>(raw) }.getOrNull()
        } ?: defaultLiveProgressSpecSnapshot()

        if (AppGraph.dismissTracker.isSuppressed(snapshot.cascadeId, snapshot.currentStepIndex)) {
            if (snapshot.phase == LiveProgressPhase.COMPLETED) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            return START_NOT_STICKY
        }

        val notification = AndroidLiveUpdateBuilder.buildNotification(
            context = this,
            snapshot = snapshot,
            contentIntent = buildContentPendingIntent(snapshot),
            approveIntent = buildApprovePendingIntent(snapshot),
            denyIntent = buildActionBroadcastPendingIntent(
                action = AndroidLiveUpdateBuilder.ACTION_DENY,
                snapshot = snapshot,
                requestCode = REQUEST_CODE_DENY,
            ),
            stopIntent = buildActionBroadcastPendingIntent(
                action = AndroidLiveUpdateBuilder.ACTION_STOP,
                snapshot = snapshot,
                requestCode = REQUEST_CODE_STOP,
            ),
            dismissIntent = buildActionBroadcastPendingIntent(
                action = AndroidLiveUpdateBuilder.ACTION_DISMISSED,
                snapshot = snapshot,
                requestCode = REQUEST_CODE_DISMISS,
            ),
        )

        if (snapshot.phase == LiveProgressPhase.COMPLETED) {
            val manager = getSystemService(NotificationManager::class.java)
            manager?.notify(NOTIFICATION_ID, notification)
            stopForeground(STOP_FOREGROUND_DETACH)
            stopSelf()
        } else {
            val fgsType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            }
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, fgsType)
        }

        return START_NOT_STICKY
    }

    private fun buildContentPendingIntent(snapshot: LiveProgressSnapshot): PendingIntent {
        val intent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("agpocket://cascade/${snapshot.cascadeId}"),
            this,
            MainActivity::class.java,
        ).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(AndroidLiveUpdateBuilder.EXTRA_CASCADE_ID, snapshot.cascadeId)
        }
        return PendingIntent.getActivity(
            this,
            REQUEST_CODE_OPEN,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildApprovePendingIntent(snapshot: LiveProgressSnapshot): PendingIntent {
        val intent = Intent(this, BiometricApprovalTrampolineActivity::class.java).apply {
            action = AndroidLiveUpdateBuilder.ACTION_APPROVE_BIOMETRIC
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
            putExtra(AndroidLiveUpdateBuilder.EXTRA_CASCADE_ID, snapshot.cascadeId)
            putExtra(AndroidLiveUpdateBuilder.EXTRA_STEP_INDEX, snapshot.currentStepIndex + 1)
            putExtra(EXTRA_COMMAND_PREVIEW, snapshot.pendingApprovalCommand ?: snapshot.activeToolAction)
        }
        return PendingIntent.getActivity(
            this,
            REQUEST_CODE_APPROVE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildActionBroadcastPendingIntent(
        action: String,
        snapshot: LiveProgressSnapshot,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(this, LiveProgressActionReceiver::class.java).apply {
            this.action = action
            putExtra(AndroidLiveUpdateBuilder.EXTRA_CASCADE_ID, snapshot.cascadeId)
            putExtra(AndroidLiveUpdateBuilder.EXTRA_STEP_INDEX, snapshot.currentStepIndex)
        }
        return PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val NOTIFICATION_ID: Int = 4091
        const val ACTION_START_OR_UPDATE: String = "com.thousandtimes.agpocket.action.START_OR_UPDATE_LIVE_PROGRESS"
        const val ACTION_STOP_SERVICE: String = "com.thousandtimes.agpocket.action.STOP_LIVE_PROGRESS_SERVICE"
        const val EXTRA_SNAPSHOT_JSON: String = "com.thousandtimes.agpocket.extra.SNAPSHOT_JSON"
        const val EXTRA_COMMAND_PREVIEW: String = "com.thousandtimes.agpocket.extra.COMMAND_PREVIEW"

        private const val REQUEST_CODE_OPEN = 1001
        private const val REQUEST_CODE_APPROVE = 1002
        private const val REQUEST_CODE_DENY = 1003
        private const val REQUEST_CODE_STOP = 1004
        private const val REQUEST_CODE_DISMISS = 1005

        private val ServiceJson = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        fun startOrUpdate(context: Context, snapshot: LiveProgressSnapshot) {
            if (AppGraph.dismissTracker.isSuppressed(snapshot.cascadeId, snapshot.currentStepIndex)) {
                return
            }
            val intent = Intent(context, AgentProgressForegroundService::class.java).apply {
                action = ACTION_START_OR_UPDATE
                putExtra(EXTRA_SNAPSHOT_JSON, ServiceJson.encodeToString(snapshot))
            }
            runCatching {
                ContextCompat.startForegroundService(context, intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, AgentProgressForegroundService::class.java).apply {
                action = ACTION_STOP_SERVICE
            }
            runCatching { context.stopService(intent) }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.cancel(NOTIFICATION_ID)
        }
    }
}
