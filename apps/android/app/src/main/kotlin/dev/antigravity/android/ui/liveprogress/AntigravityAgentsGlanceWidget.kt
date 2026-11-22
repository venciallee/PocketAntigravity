package dev.antigravity.android.ui.liveprogress

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import dev.antigravity.android.AppGraph
import dev.antigravity.android.MainActivity
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.LiveProgressAgentSummary
import dev.antigravity.shared.model.LiveProgressPhase

/**
 * Jetpack Glance home-screen widget displaying active Antigravity agents, prioritizing
 * conversations waiting for user biometric approval or plan review.
 */
class AntigravityAgentsGlanceWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val summaries = runCatching {
            AppGraph.coordinator(context).syncState.value.summaries
        }.getOrDefault(emptyList())

        val agentRows = if (summaries.isNotEmpty()) {
            summaries
                .sortedWith(
                    compareByDescending<dev.antigravity.shared.model.CascadeSummary> {
                        it.status == CortexStepStatus.WAITING || it.status == CortexStepStatus.BLOCKED
                    }.thenByDescending {
                        it.status == CortexStepStatus.IN_PROGRESS
                    }.thenByDescending { it.updatedAtEpochMs },
                )
                .take(3)
                .map { summary ->
                    val phase = when (summary.status) {
                        CortexStepStatus.WAITING, CortexStepStatus.BLOCKED -> LiveProgressPhase.WAITING_APPROVAL
                        CortexStepStatus.IN_PROGRESS, CortexStepStatus.PENDING -> LiveProgressPhase.RUNNING
                        else -> LiveProgressPhase.COMPLETED
                    }
                    LiveProgressAgentSummary(
                        id = summary.cascadeId,
                        title = summary.title,
                        subtitle = summary.pendingInteractionTitle ?: summary.statusSubtitle,
                        phase = phase,
                        trailingLabel = if (phase == LiveProgressPhase.WAITING_APPROVAL) {
                            "Review"
                        } else {
                            summary.relativeTimeLabel
                        },
                    )
                }
        } else {
            defaultLiveProgressSpecSnapshot().multiAgentItems
        }

        val runningCount = agentRows.count { it.phase == LiveProgressPhase.RUNNING }
        val waitingCount = agentRows.count { it.phase == LiveProgressPhase.WAITING_APPROVAL }

        provideContent {
            GlanceTheme {
                AntigravityGlanceWidgetContent(
                    rows = agentRows,
                    runningCount = runningCount.coerceAtLeast(1),
                    waitingCount = waitingCount,
                )
            }
        }
    }
}

@Composable
private fun AntigravityGlanceWidgetContent(
    rows: List<LiveProgressAgentSummary>,
    runningCount: Int,
    waitingCount: Int,
) {
    val bgCard = Color(0xFF12141B)
    val inkPrimary = Color(0xFFF5F6F8)
    val inkSecondary = Color(0xFF939AA8)
    val amber = Color(0xFFEBB365)
    val blue = Color(0xFF7DA7FF)
    val green = Color(0xFF57C88A)
    val darkOnAmber = Color(0xFF0A0E17)

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .cornerRadius(20.dp)
            .background(bgCard)
            .clickable(actionStartActivity<MainActivity>())
            .padding(14.dp),
    ) {
        Text(
            text = "AG Pocket · $runningCount running · $waitingCount needs you",
            style = TextStyle(
                color = ColorProvider(inkSecondary),
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
        Spacer(modifier = GlanceModifier.height(10.dp))

        rows.take(2).forEachIndexed { idx, row ->
            val dotColor = when (row.phase) {
                LiveProgressPhase.WAITING_APPROVAL -> amber
                LiveProgressPhase.RUNNING -> blue
                LiveProgressPhase.COMPLETED -> green
            }
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = GlanceModifier
                        .size(8.dp)
                        .cornerRadius(4.dp)
                        .background(dotColor),
                ) {}
                Spacer(modifier = GlanceModifier.width(8.dp))
                Column(modifier = GlanceModifier.defaultWeight()) {
                    Text(
                        text = row.title,
                        style = TextStyle(
                            color = ColorProvider(inkPrimary),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        maxLines = 1,
                    )
                    Text(
                        text = row.subtitle,
                        style = TextStyle(
                            color = ColorProvider(
                                if (row.phase == LiveProgressPhase.WAITING_APPROVAL) amber else inkSecondary,
                            ),
                            fontSize = 11.sp,
                        ),
                        maxLines = 1,
                    )
                }
                Spacer(modifier = GlanceModifier.width(8.dp))
                if (row.phase == LiveProgressPhase.WAITING_APPROVAL) {
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(12.dp)
                            .background(amber)
                            .padding(horizontal = 10.dp, vertical = 4.dp),
                    ) {
                        Text(
                            text = row.trailingLabel,
                            style = TextStyle(
                                color = ColorProvider(darkOnAmber),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                            ),
                        )
                    }
                } else {
                    Text(
                        text = row.trailingLabel,
                        style = TextStyle(
                            color = ColorProvider(inkSecondary),
                            fontSize = 11.sp,
                        ),
                    )
                }
            }
            if (idx == 0 && rows.size > 1) {
                Spacer(modifier = GlanceModifier.height(8.dp))
            }
        }
    }
}

class AntigravityAgentsGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AntigravityAgentsGlanceWidget()
}
