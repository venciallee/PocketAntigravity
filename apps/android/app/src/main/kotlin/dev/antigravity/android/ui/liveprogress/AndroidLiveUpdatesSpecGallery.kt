package dev.antigravity.android.ui.liveprogress

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Fingerprint
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.components.SevenSegmentProgressBar
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.shared.model.LiveProgressAgentSummary
import dev.antigravity.shared.model.LiveProgressPhase
import dev.antigravity.shared.model.LiveProgressSnapshot

private val BoardBackground = Color(0xFFECEEF2)
private val TraySurfaceLight = Color(0xFFD8DEE6)
private val TraySurfaceDark = Color(0xFF1F2330)
private val CardDarkSurface = Color(0xFF101218)
private val CardDarkElevated = Color(0xFF1A1D26)
private val CardDarkAction = Color(0xFF232734)
private val ChipPillBlack = Color(0xFF0A0B0F)
private val BoardTitleInk = Color(0xFF11141C)
private val BoardSubtitleInk = Color(0xFF525A6B)
private val RunningBlue = Color(0xFF7DA7FF)
private val PeriwinkleButton = Color(0xFF8EB4FF)
private val WaitingAmber = Color(0xFFEBB365)
private val DoneGreen = Color(0xFF57C88A)
private val ErrorCoral = Color(0xFFF07167)
private val DarkCardText = Color(0xFFF5F6F8)
private val DarkCardSecondary = Color(0xFF939AA8)
private val DarkButtonInk = Color(0xFF0A0E17)

/**
 * UE13_LIVE_ACTIVITY_SPEC: Native Android 16 Live Updates (`Notification.ProgressStyle` +
 * Status Bar Live Chips) & Lock Screen / Glance Multi-Agent Spec Showcase.
 *
 * Designed for 800x500dp landscape visual QA while adapting gracefully to portrait widths.
 */
@Composable
fun AndroidLiveUpdatesSpecGallery(
    snapshot: LiveProgressSnapshot = defaultLiveProgressSpecSnapshot(),
    modifier: Modifier = Modifier,
) {
    val activeSnapshot = snapshot.let {
        if (it.multiAgentItems.isEmpty()) {
            it.copy(multiAgentItems = defaultMultiAgentSummaries())
        } else {
            it
        }
    }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(BoardBackground),
    ) {
        val isCompactPortrait = maxWidth < 600.dp

        if (isCompactPortrait) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                SpecGalleryHeader(compact = true)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        StatusChipRunningTile(
                            snapshot = activeSnapshot,
                            modifier = Modifier.weight(1f),
                        )
                        StatusChipWaitingTile(
                            modifier = Modifier.weight(1f),
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        MinimalBadgeTile(
                            snapshot = activeSnapshot,
                            modifier = Modifier.weight(1f),
                        )
                        StatusChipDoneTile(
                            snapshot = activeSnapshot,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                ExpandedRunningNotificationTile(
                    snapshot = activeSnapshot,
                    modifier = Modifier.fillMaxWidth(),
                )
                ExpandedWaitingNotificationTile(
                    snapshot = activeSnapshot,
                    modifier = Modifier.fillMaxWidth(),
                )
                LockScreenMultiAgentTile(
                    snapshot = activeSnapshot,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 24.dp, vertical = 18.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                SpecGalleryHeader(compact = false)

                // Top 4 Android 16 Status Bar Live Chip variants
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    StatusChipRunningTile(
                        snapshot = activeSnapshot,
                        modifier = Modifier.weight(1f),
                    )
                    StatusChipWaitingTile(
                        modifier = Modifier.weight(1f),
                    )
                    MinimalBadgeTile(
                        snapshot = activeSnapshot,
                        modifier = Modifier.weight(1f),
                    )
                    StatusChipDoneTile(
                        snapshot = activeSnapshot,
                        modifier = Modifier.weight(1f),
                    )
                }

                // Bottom 3 Expanded ProgressStyle & Lock Screen / Glance Multi-Agent cards
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    ExpandedRunningNotificationTile(
                        snapshot = activeSnapshot,
                        modifier = Modifier.weight(1f),
                    )
                    ExpandedWaitingNotificationTile(
                        snapshot = activeSnapshot,
                        modifier = Modifier.weight(1f),
                    )
                    LockScreenMultiAgentTile(
                        snapshot = activeSnapshot,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun SpecGalleryHeader(compact: Boolean) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = "Android 16 Live Updates · 实时进度与多 Agent 通知",
            style = MaterialTheme.typography.titleLarge.copy(
                fontSize = if (compact) 18.sp else 20.sp,
                lineHeight = 24.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = (-0.3).sp,
            ),
            color = BoardTitleInk,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "单个运行中会话对应一条 Android 16 ProgressStyle 推广通知；锁屏与 Glance 聚合多 Agent；需批准时切换琥珀色并支持指纹 / 生物识别放行。",
                style = MaterialTheme.typography.bodySmall.copy(
                    fontSize = 10.5.sp,
                    lineHeight = 14.5.sp,
                ),
                color = BoardSubtitleInk,
                modifier = Modifier.weight(1f),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (!compact) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    LegendDotItem(color = RunningBlue, label = "运行中")
                    LegendDotItem(color = WaitingAmber, label = "等你处理")
                    LegendDotItem(color = DoneGreen, label = "完成")
                }
            }
        }
        if (compact) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = 2.dp),
            ) {
                LegendDotItem(color = RunningBlue, label = "运行中")
                LegendDotItem(color = WaitingAmber, label = "等你处理")
                LegendDotItem(color = DoneGreen, label = "完成")
            }
        }
    }
}

@Composable
private fun LegendDotItem(color: Color, label: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        StatusDot(color = color, size = 7.dp)
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(
                fontFamily = FontFamily.SansSerif,
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium,
            ),
            color = BoardSubtitleInk,
        )
    }
}

@Composable
private fun StatusChipRunningTile(
    snapshot: LiveProgressSnapshot,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.testTag("lu-chip-running"),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(68.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(TraySurfaceLight)
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(34.dp),
                shape = RoundedCornerShape(100.dp),
                color = ChipPillBlack,
                border = BorderStroke(1.dp, RunningBlue.copy(alpha = 0.35f)),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    ProgressRingBadge(
                        progress = snapshot.currentStepIndex.toFloat() / snapshot.totalSteps.coerceAtLeast(1),
                        accent = RunningBlue,
                        size = 19.dp,
                        showOrbitMark = true,
                    )
                    Text(
                        text = "${snapshot.currentStepIndex}/${snapshot.totalSteps}",
                        style = MaterialTheme.typography.labelMedium.copy(
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                            fontSize = 11.5.sp,
                        ),
                        color = RunningBlue,
                    )
                }
            }
        }
        SpecTileCaption(
            title = "Live Chip · 运行中",
            caption = "Android 16 状态栏短文本 4/7 + 进度环，轻点直达会话。",
        )
    }
}

@Composable
private fun StatusChipWaitingTile(
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.testTag("lu-chip-waiting"),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(68.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(TraySurfaceLight)
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(34.dp),
                shape = RoundedCornerShape(100.dp),
                color = ChipPillBlack,
                border = BorderStroke(1.dp, WaitingAmber.copy(alpha = 0.45f)),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    StatusDot(color = WaitingAmber, size = 8.dp, glow = true)
                    Text(
                        text = "Approve",
                        style = MaterialTheme.typography.labelMedium.copy(
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 11.5.sp,
                        ),
                        color = WaitingAmber,
                    )
                }
            }
        }
        SpecTileCaption(
            title = "Live Chip · 待批准",
            caption = "命令执行 / 计划审阅 / 问答时切琥珀色并提升高优通道。",
        )
    }
}

@Composable
private fun MinimalBadgeTile(
    snapshot: LiveProgressSnapshot,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.testTag("lu-minimal-badge"),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(68.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(TraySurfaceLight)
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(
                    modifier = Modifier
                        .width(68.dp)
                        .height(32.dp)
                        .clip(RoundedCornerShape(100.dp))
                        .background(ChipPillBlack),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "9:41",
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontFamily = FontFamily.SansSerif,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 10.5.sp,
                        ),
                        color = DarkCardSecondary,
                    )
                }
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(ChipPillBlack),
                    contentAlignment = Alignment.Center,
                ) {
                    ProgressRingBadge(
                        progress = snapshot.currentStepIndex.toFloat() / snapshot.totalSteps.coerceAtLeast(1),
                        accent = RunningBlue,
                        size = 20.dp,
                        showOrbitMark = false,
                    )
                }
            }
        }
        SpecTileCaption(
            title = "Minimal · 状态栏共存",
            caption = "状态栏拥挤时仅保留紧凑进度环徽章；待批准时变琥珀色。",
        )
    }
}

@Composable
private fun StatusChipDoneTile(
    snapshot: LiveProgressSnapshot,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.testTag("lu-chip-done"),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(68.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(TraySurfaceLight)
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(34.dp),
                shape = RoundedCornerShape(100.dp),
                color = ChipPillBlack,
                border = BorderStroke(1.dp, DoneGreen.copy(alpha = 0.35f)),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Box(
                        modifier = Modifier
                            .size(18.dp)
                            .clip(CircleShape)
                            .background(DoneGreen.copy(alpha = 0.22f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Check,
                            contentDescription = "Done",
                            tint = DoneGreen,
                            modifier = Modifier.size(12.dp),
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            text = "+${snapshot.additions}",
                            style = MaterialTheme.typography.labelMedium.copy(
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Bold,
                                fontSize = 11.sp,
                            ),
                            color = DoneGreen,
                        )
                        Text(
                            text = "-${snapshot.deletions}",
                            style = MaterialTheme.typography.labelMedium.copy(
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Bold,
                                fontSize = 11.sp,
                            ),
                            color = ErrorCoral,
                        )
                    }
                }
            }
        }
        SpecTileCaption(
            title = "Live Chip · 完成",
            caption = "展示本轮改动行数 +128 -14，手动取消时静默不弹完成提醒。",
        )
    }
}

@Composable
private fun ExpandedRunningNotificationTile(
    snapshot: LiveProgressSnapshot,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.testTag("lu-expanded-running"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(176.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(TraySurfaceLight)
                .padding(12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp),
                color = CardDarkSurface,
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f)),
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(24.dp)
                                .clip(CircleShape)
                                .background(RunningBlue.copy(alpha = 0.16f)),
                            contentAlignment = Alignment.Center,
                        ) {
                            ProgressRingBadge(
                                progress = snapshot.currentStepIndex.toFloat() / snapshot.totalSteps.coerceAtLeast(1),
                                accent = RunningBlue,
                                size = 18.dp,
                                showOrbitMark = true,
                            )
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = snapshot.cascadeTitle,
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontSize = 11.sp,
                                    lineHeight = 14.sp,
                                ),
                                color = DarkCardText,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                text = "${snapshot.workspaceName} · ${snapshot.hostName}",
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontFamily = FontFamily.SansSerif,
                                    fontSize = 9.5.sp,
                                ),
                                color = DarkCardSecondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Text(
                            text = formatElapsedLabel(snapshot.elapsedSeconds),
                            style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp),
                            color = DarkCardSecondary,
                        )
                    }

                    Text(
                        text = snapshot.activeToolAction,
                        style = MaterialTheme.typography.bodySmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 10.5.sp,
                        ),
                        color = RunningBlue,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )

                    SevenSegmentProgressBar(
                        completedCount = snapshot.currentStepIndex,
                        totalCount = snapshot.totalSteps,
                        hasWaitingStep = false,
                        segmentHeight = 4.5.dp,
                        segmentSpacing = 3.dp,
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(30.dp)
                                .clip(RoundedCornerShape(100.dp))
                                .background(CardDarkAction),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = "Stop",
                                style = MaterialTheme.typography.labelMedium.copy(
                                    fontWeight = FontWeight.SemiBold,
                                    fontSize = 11.sp,
                                ),
                                color = DarkCardText,
                            )
                        }
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(30.dp)
                                .clip(RoundedCornerShape(100.dp))
                                .background(PeriwinkleButton),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = "Open",
                                style = MaterialTheme.typography.labelMedium.copy(
                                    fontWeight = FontWeight.SemiBold,
                                    fontSize = 11.sp,
                                ),
                                color = DarkButtonInk,
                            )
                        }
                    }
                }
            }
        }
        SpecTileCaption(
            title = "Expanded · ProgressStyle 运行中",
            caption = "当前命令 + 7 段 Notification.ProgressStyle 进度条 + 用时；Stop 无需验证，Open 深链回会话。",
        )
    }
}

@Composable
private fun ExpandedWaitingNotificationTile(
    snapshot: LiveProgressSnapshot,
    modifier: Modifier = Modifier,
) {
    val cmdText = snapshot.pendingApprovalCommand?.takeIf { it.isNotBlank() }
        ?: "vegeta attack -rate=2000/s -duration=30s"

    Column(
        modifier = modifier.testTag("lu-expanded-waiting"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(176.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(TraySurfaceLight)
                .padding(12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp),
                color = CardDarkSurface,
                border = BorderStroke(1.dp, WaitingAmber.copy(alpha = 0.42f)),
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(24.dp)
                                .clip(RoundedCornerShape(7.dp))
                                .background(WaitingAmber.copy(alpha = 0.16f)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Terminal,
                                contentDescription = "Command approval",
                                tint = WaitingAmber,
                                modifier = Modifier.size(14.dp),
                            )
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "Run this command?",
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontSize = 11.sp,
                                    lineHeight = 14.sp,
                                ),
                                color = WaitingAmber,
                                maxLines = 1,
                            )
                            Text(
                                text = "Add rate limiter · step ${snapshot.currentStepIndex + 1} of ${snapshot.totalSteps}",
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontFamily = FontFamily.SansSerif,
                                    fontSize = 9.5.sp,
                                ),
                                color = DarkCardSecondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }

                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(CardDarkElevated)
                            .padding(horizontal = 9.dp, vertical = 7.dp),
                    ) {
                        Text(
                            text = cmdText,
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 9.5.sp,
                            ),
                            color = DarkCardText,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(30.dp)
                                .clip(RoundedCornerShape(100.dp))
                                .background(CardDarkAction),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = "Deny",
                                style = MaterialTheme.typography.labelMedium.copy(
                                    fontWeight = FontWeight.SemiBold,
                                    fontSize = 11.sp,
                                ),
                                color = DarkCardText,
                            )
                        }
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(30.dp)
                                .clip(RoundedCornerShape(100.dp))
                                .background(WaitingAmber),
                            contentAlignment = Alignment.Center,
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Fingerprint,
                                    contentDescription = "Biometric Allow",
                                    tint = DarkButtonInk,
                                    modifier = Modifier.size(14.dp),
                                )
                                Text(
                                    text = "Allow",
                                    style = MaterialTheme.typography.labelMedium.copy(
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 11.sp,
                                    ),
                                    color = DarkButtonInk,
                                )
                            }
                        }
                    }
                }
            }
        }
        SpecTileCaption(
            title = "Expanded · 待批准 (Biometric)",
            caption = "Allow 经透明 Activity 唤起 BiometricPrompt 验签后回传桌面；Deny 可直接点击拒绝。",
        )
    }
}

@Composable
private fun LockScreenMultiAgentTile(
    snapshot: LiveProgressSnapshot,
    modifier: Modifier = Modifier,
) {
    val agents = snapshot.multiAgentItems.ifEmpty { defaultMultiAgentSummaries() }

    Column(
        modifier = modifier.testTag("lu-lockscreen-multi-agent"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(176.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(TraySurfaceDark)
                .padding(12.dp),
            contentAlignment = Alignment.BottomCenter,
        ) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                color = CardDarkSurface.copy(alpha = 0.94f),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.09f)),
            ) {
                Column(
                    modifier = Modifier.padding(11.dp),
                    verticalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        ProgressRingBadge(
                            progress = 0.65f,
                            accent = RunningBlue,
                            size = 13.dp,
                            showOrbitMark = false,
                        )
                        Text(
                            text = "Agents · 2 running · 1 needs you",
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontFamily = FontFamily.SansSerif,
                                fontSize = 10.sp,
                            ),
                            color = DarkCardSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }

                    agents.take(2).forEach { item ->
                        val dotColor = when (item.phase) {
                            LiveProgressPhase.WAITING_APPROVAL -> WaitingAmber
                            LiveProgressPhase.RUNNING -> RunningBlue
                            LiveProgressPhase.COMPLETED -> DoneGreen
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(7.dp),
                        ) {
                            StatusDot(color = dotColor, size = 6.5.dp)
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = item.title,
                                    style = MaterialTheme.typography.labelLarge.copy(
                                        fontSize = 10.5.sp,
                                        lineHeight = 13.sp,
                                    ),
                                    color = DarkCardText,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    text = item.subtitle,
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        fontFamily = FontFamily.SansSerif,
                                        fontSize = 9.5.sp,
                                    ),
                                    color = if (item.phase == LiveProgressPhase.WAITING_APPROVAL) {
                                        WaitingAmber
                                    } else {
                                        DarkCardSecondary
                                    },
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            if (item.phase == LiveProgressPhase.WAITING_APPROVAL) {
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(100.dp))
                                        .background(WaitingAmber)
                                        .padding(horizontal = 9.dp, vertical = 4.dp),
                                ) {
                                    Text(
                                        text = item.trailingLabel,
                                        style = MaterialTheme.typography.labelSmall.copy(
                                            fontFamily = FontFamily.SansSerif,
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 9.5.sp,
                                        ),
                                        color = DarkButtonInk,
                                    )
                                }
                            } else {
                                Text(
                                    text = item.trailingLabel,
                                    style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.5.sp),
                                    color = DarkCardSecondary,
                                )
                            }
                        }
                    }
                }
            }
        }
        SpecTileCaption(
            title = "Lock Screen & Glance · 多 Agent 聚合",
            caption = "待处理排最前；本地会话随电脑在线，云端与主屏 Glance 小组件持续同步。",
        )
    }
}

@Composable
private fun SpecTileCaption(
    title: String,
    caption: String,
) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelMedium.copy(
                fontWeight = FontWeight.Bold,
                fontSize = 11.sp,
                lineHeight = 14.sp,
            ),
            color = BoardTitleInk,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = caption,
            style = MaterialTheme.typography.bodySmall.copy(
                fontSize = 9.5.sp,
                lineHeight = 13.sp,
            ),
            color = BoardSubtitleInk,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun ProgressRingBadge(
    progress: Float,
    accent: Color,
    size: Dp,
    showOrbitMark: Boolean,
) {
    Box(
        modifier = Modifier.size(size),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val strokePx = (size.toPx() * 0.14f).coerceAtLeast(1.8f)
            drawArc(
                color = Color(0xFF2B3142),
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                style = Stroke(width = strokePx, cap = StrokeCap.Round),
            )
            drawArc(
                color = accent,
                startAngle = -90f,
                sweepAngle = (progress.coerceIn(0.08f, 1f) * 360f),
                useCenter = false,
                style = Stroke(width = strokePx, cap = StrokeCap.Round),
            )
        }
        if (showOrbitMark) {
            Box(
                modifier = Modifier
                    .size(size * 0.28f)
                    .clip(CircleShape)
                    .background(accent),
            )
        }
    }
}

private fun formatElapsedLabel(seconds: Int): String {
    val safe = seconds.coerceAtLeast(0)
    val mins = safe / 60
    val rem = safe % 60
    return "$mins:${rem.toString().padStart(2, '0')}"
}

fun defaultLiveProgressSpecSnapshot(): LiveProgressSnapshot = LiveProgressSnapshot(
    cascadeId = "cas-rate-limiter",
    cascadeTitle = "Add rate limiter to /transfers",
    hostName = "MacBook Pro",
    workspaceName = "ledger-svc",
    branchName = "main",
    phase = LiveProgressPhase.WAITING_APPROVAL,
    currentStepIndex = 4,
    totalSteps = 7,
    activeToolAction = "go test ./internal/...",
    pendingApprovalCommand = "vegeta attack -rate=2000/s -duration=30s",
    elapsedSeconds = 161,
    additions = 128,
    deletions = 14,
    multiAgentItems = defaultMultiAgentSummaries(),
)

private fun defaultMultiAgentSummaries(): List<LiveProgressAgentSummary> = listOf(
    LiveProgressAgentSummary(
        id = "cas-rate-limiter",
        title = "Add rate limiter to /transfers",
        subtitle = "Approve: vegeta attack...",
        phase = LiveProgressPhase.WAITING_APPROVAL,
        trailingLabel = "Review",
    ),
    LiveProgressAgentSummary(
        id = "cas-dark-mode",
        title = "Dark mode for settings page",
        subtitle = "Cloud · step 2 of 5",
        phase = LiveProgressPhase.RUNNING,
        trailingLabel = "12:04",
    ),
)
