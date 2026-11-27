package dev.antigravity.android.ui.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.android.ui.home.AgentsHomeScreen
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.localizedSummaryDescription
import dev.antigravity.shared.model.localizedTitle

/**
 * UE07B_PERMISSIONS_PRESET (`and-preset.png`): Anchored Material 3 Permissions Preset popup
 * over the composer (`Request Review`, `Default ✓`, `Auto`, `Turbo` on local projects;
 * `Request Review`, `Default`, `Turbo` on remote Cloud sessions).
 */
@Composable
fun PermissionsPresetOverlayScreen(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    onOpenSettings: () -> Unit = {},
    isRemote: Boolean = false,
    showHomeBackdrop: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val lang = LocalAppLanguage.current
    val settingsState by coordinator.settingsStore.state.collectAsState()
    val activePreset = settingsState.permissionPresetFor(isRemote = isRemote)

    val presets = AgentPermissionPreset.availablePresets(isRemote = isRemote).map { preset ->
        Triple(
            preset,
            preset.localizedTitle(lang),
            preset.localizedSummaryDescription(lang),
        )
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(if (showHomeBackdrop) colors.canvasObsidian else Color.Transparent),
    ) {
        if (showHomeBackdrop) {
            AgentsHomeScreen(
                coordinator = coordinator,
                onOpenSidebar = {},
                onOpenConversation = {},
                highlightPermissionsPill = true,
                showNeedsApprovalBanner = false,
                showSearchAction = false,
                showHostChevron = false,
                modifier = Modifier.fillMaxSize(),
            )
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.14f))
                .clickable(onClick = onDismiss),
        )

        Surface(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = 18.dp, bottom = 140.dp)
                .width(292.dp)
                .testTag("permissions-preset-popover"),
            shape = RoundedCornerShape(18.dp),
            color = colors.surfacePopover,
            border = BorderStroke(1.dp, colors.cardBorder),
            shadowElevation = 12.dp,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 10.dp),
            ) {
                Text(
                    text = if (isRemote) {
                        tr("Remote Permissions", "远程权限")
                    } else {
                        tr("Permissions for this conversation", "当前会话权限")
                    },
                    style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                    color = colors.inkSecondary,
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 8.dp),
                )

                presets.forEachIndexed { idx, (preset, title, subtitle) ->
                    val selected = activePreset == preset
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(if (selected) Color.White.copy(alpha = 0.06f) else Color.Transparent)
                            .clickable {
                                coordinator.settingsStore.selectPermissionPreset(
                                    preset = preset,
                                    isRemote = isRemote,
                                )
                                onDismiss()
                            }
                            .padding(horizontal = 18.dp, vertical = 11.dp)
                            .testTag("preset-option-${preset.name.lowercase()}"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                text = title,
                                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, fontWeight = FontWeight.Medium),
                                color = colors.inkReading,
                            )
                            Text(
                                text = subtitle,
                                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp, lineHeight = 18.sp),
                                color = colors.inkSecondary,
                            )
                        }
                        if (selected) {
                            Icon(
                                imageVector = Icons.Rounded.Check,
                                contentDescription = tr("Selected", "已选"),
                                tint = colors.accentPeriwinkle,
                                modifier = Modifier.size(19.dp),
                            )
                        }
                    }
                    if (idx == 0) {
                        HorizontalDivider(color = colors.subtleDivider)
                    }
                }

                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 6.dp),
                    color = colors.subtleDivider,
                )

                Text(
                    text = tr("Default for new turns: Settings > Permissions", "新轮次默认策略：设置 > 权限"),
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, lineHeight = 17.sp),
                    color = colors.inkSecondary,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            onDismiss()
                            onOpenSettings()
                        }
                        .padding(horizontal = 18.dp, vertical = 8.dp)
                        .testTag("preset-settings-footer"),
                )
            }
        }
    }
}

/**
 * UE08B_SLASH_MENU (`and-slash.png`): Categorized Slash Command autocomplete card (`Actions` + `Skills`)
 * docked cleanly above the composer with `/` entered.
 */
@Composable
fun SlashMenuOverlayScreen(
    coordinator: AntigravityCoreCoordinator,
    onSelectCommand: (String) -> Unit,
    onDismiss: () -> Unit,
    includeSideQuestionPreview: Boolean = false,
    showHomeBackdrop: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current

    // Feature-flag gated preview entry for UE08B visual parity while keeping `/btw` deferred in live mode.
    val actionItems = buildList {
        add("/plan" to tr("Explore first, then draft a reviewable plan", "先探索代码，再起草可审核的实施计划"))
        add("/goal" to tr("Keep working until the goal is verified", "持续推进直到验证达成目标"))
        add("/schedule" to tr("Wake this conversation later", "稍后定时唤醒此会话"))
        add("/automation" to tr("Set up a recurring automation", "设置周期性自动化任务"))
        if (includeSideQuestionPreview) {
            add("/btw" to tr("Side question in a read-only fork", "在只读分支中顺便提问"))
        }
    }
    val skillItems = listOf(
        "/go-testing" to tr("Table-driven tests with -race", "使用 -race 运行表驱动测试"),
        "/api-review" to tr("Check handlers against API rules", "按 API 规范检查接口处理器"),
    )

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(if (showHomeBackdrop) colors.canvasObsidian else Color.Transparent),
    ) {
        if (showHomeBackdrop) {
            AgentsHomeScreen(
                coordinator = coordinator,
                onOpenSidebar = {},
                onOpenConversation = {},
                composerDraftOverride = "/",
                showGreeting = false,
                showNeedsApprovalBanner = false,
                showSearchAction = false,
                showHostChevron = false,
                modifier = Modifier.fillMaxSize(),
            )
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .clickable(onClick = onDismiss),
        )

        Surface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(start = 14.dp, end = 14.dp, bottom = 196.dp)
                .fillMaxWidth()
                .testTag("slash-menu-card"),
            shape = RoundedCornerShape(20.dp),
            color = colors.surfacePopover,
            border = BorderStroke(1.dp, colors.cardBorder),
            shadowElevation = 12.dp,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
            ) {
                Text(
                    text = tr("Actions", "操作"),
                    style = MaterialTheme.typography.titleSmall.copy(fontSize = 13.5.sp, fontWeight = FontWeight.Medium),
                    color = colors.accentPeriwinkle,
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 6.dp),
                )

                actionItems.forEachIndexed { idx, (cmd, desc) ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(if (idx == 0) colors.surfaceActiveTab else Color.Transparent)
                            .clickable { onSelectCommand(cmd) }
                            .padding(horizontal = 18.dp, vertical = 10.dp)
                            .testTag("slash-item-${cmd.removePrefix("/")}"),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(
                            text = cmd,
                            style = MaterialTheme.typography.bodyLarge.copy(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.inkReading,
                        )
                        Text(
                            text = desc,
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                            color = colors.inkSecondary,
                        )
                    }
                }

                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 8.dp),
                    color = colors.subtleDivider,
                )

                Text(
                    text = tr("Skills", "技能"),
                    style = MaterialTheme.typography.titleSmall.copy(fontSize = 13.5.sp, fontWeight = FontWeight.Medium),
                    color = colors.accentPeriwinkle,
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 6.dp),
                )

                skillItems.forEach { (cmd, desc) ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelectCommand(cmd) }
                            .padding(horizontal = 18.dp, vertical = 10.dp)
                            .testTag("slash-skill-${cmd.removePrefix("/")}"),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(
                            text = cmd,
                            style = MaterialTheme.typography.bodyLarge.copy(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.inkReading,
                        )
                        Text(
                            text = desc,
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                            color = colors.inkSecondary,
                        )
                    }
                }
            }
        }
    }
}
