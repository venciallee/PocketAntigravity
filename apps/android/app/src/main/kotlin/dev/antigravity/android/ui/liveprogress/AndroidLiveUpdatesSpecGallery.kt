package dev.antigravity.android.ui.liveprogress

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Fingerprint
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.shared.model.LiveProgressAgentSummary
import dev.antigravity.shared.model.LiveProgressPhase
import dev.antigravity.shared.model.LiveProgressSnapshot

private val ShadeCanvas = Color(0xFF0A0A0C)
private val ShadeCard = Color(0xFF1A1B1F)
private val ShadeAmberCard = Color(0xFF252016)
private val ShadePillDark = Color(0xFF26272D)
private val ShadeAmberPillDark = Color(0xFF363026)
private val ShadeCodeBg = Color(0xFF14120F)
private val RunningBlue = Color(0xFF8DB8FF)
private val WaitingAmber = Color(0xFFF2B866)
private val DoneGreen = Color(0xFF6FD8A6)
private val ErrorCoral = Color(0xFFF07167)
private val InkPrimary = Color(0xFFF2F2F5)
private val InkSecondary = Color(0xFF9C9CA6)
private val InkDarkButton = Color(0xFF0A0E17)
private val TrackInactive = Color(0xFF2D2E35)

/**
 * UE13_LIVE_ACTIVITY_SPEC (`and-live-update.png`): Native Android 16 Notification Shade
 * showcasing `NotificationCompat.ProgressStyle` 7-segment Live Update, Amber biometric
 * approval card (`Deny` / `Allow` / `Reply`), Cloud 5-segment progress notification,
 * Completed diff review card, and bottom `Manage` / `Clear all` controls.
 */
@Composable
fun AndroidLiveUpdatesSpecGallery(
    snapshot: LiveProgressSnapshot = defaultLiveProgressSpecSnapshot(),
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(ShadeCanvas)
            .statusBarsPadding()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 14.dp, vertical = 20.dp)
            .testTag("android-live-updates-shade"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // 1. Running Android 16 ProgressStyle Card
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .testTag("live-card-running"),
            shape = RoundedCornerShape(24.dp),
            color = ShadeCard,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Surface(
                        shape = CircleShape,
                        color = Color(0xFF23324D),
                        modifier = Modifier.size(24.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = Icons.Rounded.AutoAwesome,
                                contentDescription = null,
                                tint = RunningBlue,
                                modifier = Modifier.size(14.dp),
                            )
                        }
                    }
                    Text(
                        text = "Agents · ${snapshot.workspaceName} · now",
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                        color = InkSecondary,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = formatElapsedMinSec(snapshot.elapsedSeconds.coerceAtLeast(161)),
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 13.5.sp,
                        ),
                        color = RunningBlue,
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        text = snapshot.cascadeTitle,
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                        color = InkPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = "Running go test ./internal/...",
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 13.5.sp,
                        ),
                        color = InkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                // 7-Segment Android 16 ProgressStyle bar with circular tracker badge
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(24.dp),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        val completed = snapshot.currentStepIndex.coerceIn(1, 7)
                        for (i in 0 until 7) {
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(5.dp)
                                    .clip(RoundedCornerShape(100.dp))
                                    .background(if (i < completed) RunningBlue else TrackInactive),
                            )
                        }
                    }
                    // Tracker circle at segment 4 boundary
                    Row(modifier = Modifier.fillMaxWidth()) {
                        Spacer(modifier = Modifier.weight(0.50f))
                        Surface(
                            shape = CircleShape,
                            color = Color(0xFFEAF1FF),
                            modifier = Modifier.size(22.dp),
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    imageVector = Icons.Rounded.AutoAwesome,
                                    contentDescription = null,
                                    tint = InkDarkButton,
                                    modifier = Modifier.size(13.dp),
                                )
                            }
                        }
                        Spacer(modifier = Modifier.weight(0.42f))
                    }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Surface(
                        shape = RoundedCornerShape(100.dp),
                        color = ShadePillDark,
                        modifier = Modifier.testTag("live-action-stop"),
                    ) {
                        Text(
                            text = "Stop",
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
                            color = InkPrimary,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
                        )
                    }
                    Surface(
                        shape = RoundedCornerShape(100.dp),
                        color = ShadePillDark,
                        modifier = Modifier.testTag("live-action-open"),
                    ) {
                        Text(
                            text = "Open",
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
                            color = InkPrimary,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
                        )
                    }
                }
            }
        }

        // 2. Amber Biometric Approval Card (`Run this command?`)
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .testTag("live-card-approval"),
            shape = RoundedCornerShape(24.dp),
            color = ShadeAmberCard,
            border = BorderStroke(1.dp, WaitingAmber.copy(alpha = 0.18f)),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Surface(
                        shape = CircleShape,
                        color = WaitingAmber.copy(alpha = 0.16f),
                        modifier = Modifier.size(24.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = Icons.Rounded.Terminal,
                                contentDescription = null,
                                tint = WaitingAmber,
                                modifier = Modifier.size(14.dp),
                            )
                        }
                    }
                    Text(
                        text = "Agents · Needs approval",
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                        color = WaitingAmber.copy(alpha = 0.85f),
                    )
                }

                Text(
                    text = "Run this command?",
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontSize = 17.5.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    color = InkPrimary,
                )

                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    color = ShadeCodeBg,
                ) {
                    Text(
                        text = snapshot.pendingApprovalCommand ?: "vegeta attack -rate=2000/s -duration=30s",
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 13.sp,
                        ),
                        color = InkPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                    )
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Surface(
                        shape = RoundedCornerShape(100.dp),
                        color = ShadeAmberPillDark,
                        modifier = Modifier.testTag("live-action-deny"),
                    ) {
                        Text(
                            text = "Deny",
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
                            color = InkPrimary,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 11.dp),
                        )
                    }

                    Button(
                        onClick = {},
                        modifier = Modifier
                            .defaultMinSize(minHeight = 42.dp)
                            .testTag("live-action-allow"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = WaitingAmber,
                            contentColor = InkDarkButton,
                        ),
                        contentPadding = PaddingValues(horizontal = 18.dp, vertical = 10.dp),
                    ) {
                        Icon(Icons.Rounded.Fingerprint, contentDescription = null, modifier = Modifier.size(17.dp))
                        Spacer(modifier = Modifier.size(6.dp))
                        Text("Allow", style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold))
                    }

                    TextButton(onClick = {}) {
                        Text(
                            text = "Reply",
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
                            color = WaitingAmber.copy(alpha = 0.88f),
                        )
                    }
                }
            }
        }

        // 3. Compact Cloud VM 5-Segment Card (`Dark mode for settings page`)
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .testTag("live-card-cloud"),
            shape = RoundedCornerShape(22.dp),
            color = ShadeCard,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 18.dp, vertical = 15.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Surface(
                        shape = CircleShape,
                        color = Color(0xFF23324D),
                        modifier = Modifier.size(30.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = Icons.Rounded.Cloud,
                                contentDescription = null,
                                tint = RunningBlue,
                                modifier = Modifier.size(16.dp),
                            )
                        }
                    }
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            text = "Dark mode for settings page",
                            style = MaterialTheme.typography.titleSmall.copy(fontSize = 15.5.sp, fontWeight = FontWeight.SemiBold),
                            color = InkPrimary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = "Cloud · step 2 of 5",
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                            color = InkSecondary,
                        )
                    }
                    Text(
                        text = "12:04",
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = InkSecondary,
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    for (i in 0 until 5) {
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(4.dp)
                                .clip(RoundedCornerShape(100.dp))
                                .background(if (i < 2) RunningBlue else TrackInactive),
                        )
                    }
                }
            }
        }

        // 4. Completed Card (`Upgrade to Go 1.25` + `Review`)
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .testTag("live-card-done"),
            shape = RoundedCornerShape(22.dp),
            color = ShadeCard,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 18.dp, vertical = 15.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Surface(
                    shape = CircleShape,
                    color = Color(0xFF183125),
                    modifier = Modifier.size(30.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Rounded.Check,
                            contentDescription = null,
                            tint = DoneGreen,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "Upgrade to Go 1.25",
                        style = MaterialTheme.typography.titleSmall.copy(fontSize = 15.5.sp, fontWeight = FontWeight.SemiBold),
                        color = InkPrimary,
                    )
                    Text(
                        text = buildAnnotatedString {
                            withStyle(SpanStyle(color = InkSecondary)) { append("Done · 6 files ") }
                            withStyle(SpanStyle(color = DoneGreen, fontFamily = FontFamily.Monospace)) { append("+42 ") }
                            withStyle(SpanStyle(color = ErrorCoral, fontFamily = FontFamily.Monospace)) { append("-31") }
                        },
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                    )
                }
                Surface(
                    shape = RoundedCornerShape(100.dp),
                    color = ShadePillDark,
                    modifier = Modifier.testTag("live-action-review"),
                ) {
                    Text(
                        text = "Review",
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                        color = InkPrimary,
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
                    )
                }
            }
        }

        // Bottom Android Notification Shade Footer: Manage | Clear all
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                shape = RoundedCornerShape(100.dp),
                color = ShadeCard,
            ) {
                Text(
                    text = "Manage",
                    style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.5.sp),
                    color = InkPrimary,
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            Surface(
                shape = RoundedCornerShape(100.dp),
                color = ShadeCard,
            ) {
                Text(
                    text = "Clear all",
                    style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.5.sp),
                    color = InkPrimary,
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
                )
            }
        }
    }
}

private fun formatElapsedMinSec(seconds: Int): String {
    val mins = seconds / 60
    val rem = seconds % 60
    return "$mins:${rem.toString().padStart(2, '0')}"
}

fun defaultLiveProgressSpecSnapshot(): LiveProgressSnapshot = LiveProgressSnapshot(
    cascadeId = "cas-rate-limiter",
    cascadeTitle = "Add rate limiter to /transfers",
    hostName = "MacBook Pro",
    workspaceName = "ledger-svc",
    branchName = "main",
    phase = LiveProgressPhase.RUNNING,
    currentStepIndex = 4,
    totalSteps = 7,
    activeToolAction = "go test ./internal/...",
    pendingApprovalCommand = "vegeta attack -rate=2000/s -duration=30s",
    elapsedSeconds = 161,
    additions = 128,
    deletions = 14,
    multiAgentItems = listOf(
        LiveProgressAgentSummary(
            id = "cas-rate-limiter",
            title = "Add rate limiter to /transfers",
            subtitle = "ledger-svc · MacBook Pro",
            phase = LiveProgressPhase.RUNNING,
            trailingLabel = "4/7",
        ),
        LiveProgressAgentSummary(
            id = "cas-dark-mode-cloud",
            title = "Dark mode for settings page",
            subtitle = "web-console · Cloud",
            phase = LiveProgressPhase.RUNNING,
            trailingLabel = "2/5",
        ),
        LiveProgressAgentSummary(
            id = "cas-upgrade-go",
            title = "Upgrade to Go 1.25",
            subtitle = "ledger-svc · MacBook Pro",
            phase = LiveProgressPhase.COMPLETED,
            trailingLabel = "+42 -31",
        ),
    ),
)
