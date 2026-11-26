package dev.antigravity.android.ui.projects

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/**
 * UE14_RULES_AND_SKILLS (`and-customizations.png`): Dedicated read-only Customizations /
 * Rules & skills screen with Loaded-every-turn token budget bar, 4-tab switcher
 * (`Skills 5`, `Rules 4`, `Plugins 2`, `Agents 1`), plugin toggle switches, and Desktop note.
 */
@Composable
fun ProjectRulesAndSkillsScreen(
    coordinator: AntigravityCoreCoordinator,
    projectName: String = "ledger-svc",
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val settingsState by coordinator.settingsStore.state.collectAsStateWithLifecycle()
    val catalog = settingsState.customizations
    val scope = rememberCoroutineScope()

    var selectedTabIndex by rememberSaveable { mutableIntStateOf(0) }
    val tabs = listOf(
        tr("Skills ${catalog.skills.size}", "技能 ${catalog.skills.size}"),
        tr("Rules ${catalog.rules.size}", "规则 ${catalog.rules.size}"),
        tr("Plugins ${catalog.plugins.size}", "插件 ${catalog.plugins.size}"),
        tr("Agents ${catalog.customAgents.size}", "代理 ${catalog.customAgents.size}"),
    )

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .statusBarsPadding()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 24.dp),
    ) {
        // Top App Bar: Back | Rules & skills / ledger-svc
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier
                    .size(AntigravityDesignTokens.MinTouchTarget)
                    .testTag("btn-back"),
            ) {
                Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = tr("Back", "返回"), tint = colors.inkReading)
            }
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(
                    text = tr("Rules & skills", "规则与技能"),
                    style = MaterialTheme.typography.titleLarge.copy(fontSize = 20.sp, fontWeight = FontWeight.Normal),
                    color = colors.inkReading,
                )
                Text(
                    text = projectName,
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                    color = colors.inkSecondary,
                )
            }
        }

        // Token budget card (`Loaded every turn` · `6.2k tokens`)
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .testTag("rules-token-budget-card"),
            shape = RoundedCornerShape(16.dp),
            color = colors.surfaceCard,
            border = BorderStroke(1.dp, colors.cardBorder),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = tr("Loaded every turn", "每轮自动加载"),
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp),
                        color = colors.inkReading,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = catalog.loadedTokensLabel,
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                        color = colors.inkSecondary,
                    )
                }

                // Segmented 3-color bar: Rules (blue) + Skills (mint) + Plugins (amber) + remainder track
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(7.dp)
                        .clip(RoundedCornerShape(100.dp))
                        .background(colors.ringTrack),
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Box(modifier = Modifier.weight(0.31f).fillMaxHeight().background(colors.accentPeriwinkle))
                    Box(modifier = Modifier.weight(0.14f).fillMaxHeight().background(colors.statusDone))
                    Box(modifier = Modifier.weight(0.17f).fillMaxHeight().background(colors.statusWaiting))
                    Spacer(modifier = Modifier.weight(0.38f))
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TokenLegendItem(color = colors.accentPeriwinkle, label = tr("Rules", "规则"))
                    TokenLegendItem(color = colors.statusDone, label = tr("Skills", "技能"))
                    TokenLegendItem(color = colors.statusWaiting, label = tr("Plugins", "插件"))
                }
            }
        }

        Spacer(modifier = Modifier.height(6.dp))

        // 4 Underline Tabs: Skills 5 | Rules 4 | Plugins 2 | Agents 1
        PrimaryTabRow(
            selectedTabIndex = selectedTabIndex,
            containerColor = colors.canvasObsidian,
            contentColor = colors.accentPeriwinkle,
            indicator = {
                TabRowDefaults.PrimaryIndicator(
                    modifier = Modifier.tabIndicatorOffset(selectedTabIndex, matchContentSize = true),
                    width = 48.dp,
                    height = 3.dp,
                    color = colors.accentPeriwinkle,
                )
            },
            divider = { HorizontalDivider(color = colors.subtleDivider) },
        ) {
            tabs.forEachIndexed { idx, label ->
                val selected = selectedTabIndex == idx
                Tab(
                    selected = selected,
                    onClick = { selectedTabIndex = idx },
                    modifier = Modifier.testTag("customizations-tab-$idx"),
                    text = {
                        Text(
                            text = label,
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 14.sp,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            ),
                            color = if (selected) colors.accentPeriwinkle else colors.inkSecondary,
                            maxLines = 1,
                        )
                    },
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        when (selectedTabIndex) {
            0 -> {
                // Skills list (top 4 visible matching `and-customizations.png`)
                catalog.skills.take(4).forEach { skill ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 18.dp, vertical = 12.dp)
                            .testTag("skill-row-${skill.name}"),
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.AutoAwesome,
                            contentDescription = null,
                            tint = colors.inkLabel,
                            modifier = Modifier.padding(top = 2.dp).size(19.dp),
                        )
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    text = skill.name,
                                    style = MaterialTheme.typography.bodyLarge.copy(
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 15.5.sp,
                                    ),
                                    color = colors.inkReading,
                                )
                                if (skill.scope.equals("Global", ignoreCase = true)) {
                                    ScopePill(label = tr("Global", "全局"), isAccent = true)
                                }
                            }
                            Text(
                                text = skill.description,
                                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                                color = colors.inkSecondary,
                            )
                        }
                    }
                }
            }

            1 -> {
                catalog.rules.forEach { rule ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 18.dp, vertical = 12.dp)
                            .testTag("rule-row-${rule.name}"),
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Description,
                            contentDescription = null,
                            tint = colors.inkLabel,
                            modifier = Modifier.padding(top = 2.dp).size(19.dp),
                        )
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    text = rule.name,
                                    style = MaterialTheme.typography.bodyLarge.copy(
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 15.5.sp,
                                    ),
                                    color = colors.inkReading,
                                )
                                ScopePill(
                                    label = if (rule.scope.equals("Global", ignoreCase = true)) tr("Global", "全局") else rule.scope,
                                    isAccent = rule.scope.equals("Global", ignoreCase = true),
                                )
                            }
                            Text(
                                text = rule.preview,
                                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                                color = colors.inkSecondary,
                            )
                        }
                    }
                }
            }

            2 -> {
                Text(
                    text = tr("Manage installed plugins below.", "在下方管理已安装的插件。"),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary,
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
                )
            }

            else -> {
                catalog.customAgents.forEach { agent ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 18.dp, vertical = 12.dp)
                            .testTag("agent-row-$agent"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Icon(Icons.Rounded.Person, contentDescription = null, tint = colors.inkLabel, modifier = Modifier.size(19.dp))
                        Text(
                            text = agent,
                            style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace, fontSize = 15.5.sp),
                            color = colors.inkReading,
                        )
                    }
                }
            }
        }

        // Plugins in this project section (always visible beneath Skills matching `and-customizations.png`)
        Text(
            text = tr("Plugins in this project", "此项目中的插件"),
            style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
            color = colors.accentPeriwinkle,
            modifier = Modifier.padding(start = 18.dp, end = 18.dp, top = 14.dp, bottom = 6.dp),
        )

        catalog.plugins.forEach { plugin ->
            val hasError = !plugin.mcpStartupError.isNullOrBlank() || plugin.summary.contains("API key", ignoreCase = true)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 18.dp, vertical = 12.dp)
                    .testTag("plugin-row-${plugin.id}"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Extension,
                    contentDescription = null,
                    tint = colors.inkLabel,
                    modifier = Modifier.size(20.dp),
                )
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = plugin.name,
                            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, fontWeight = FontWeight.Medium),
                            color = colors.inkReading,
                        )
                        ScopePill(
                            label = if (plugin.scope.equals("Global", ignoreCase = true)) tr("Global", "全局") else plugin.scope,
                            isAccent = plugin.scope.equals("Global", ignoreCase = true),
                        )
                    }
                    Text(
                        text = plugin.mcpStartupError ?: plugin.summary,
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                        color = if (hasError) colors.statusError else colors.inkSecondary,
                    )
                }

                Switch(
                    checked = plugin.isEnabled,
                    onCheckedChange = { enabled ->
                        scope.launch(start = CoroutineStart.UNDISPATCHED) {
                            val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                            coordinator.settingsStore.togglePlugin(client = rpc, pluginId = plugin.id, isEnabled = enabled)
                        }
                    },
                    modifier = Modifier.testTag("switch-plugin-${plugin.id}"),
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = colors.inkOnPrimaryCta,
                        checkedTrackColor = colors.accentPeriwinkle,
                        uncheckedThumbColor = colors.inkSecondary,
                        uncheckedTrackColor = colors.surfaceElevated,
                        uncheckedBorderColor = colors.inkMuted,
                    ),
                )
            }
        }

        Spacer(modifier = Modifier.height(28.dp))

        Text(
            text = tr(
                "Phone can view and switch plugins on or off. Marketplace installs, editing rules / SKILL.md and API keys stay in Antigravity Desktop → Customizations.",
                "移动端支持查看及开关插件；插件市场安装、编辑规则 / SKILL.md 与 API 密钥请在 Antigravity Desktop → Customizations 中操作。",
            ),
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp, lineHeight = 19.sp),
            color = colors.inkSecondary,
            modifier = Modifier.padding(horizontal = 18.dp),
        )
    }
}

@Composable
private fun TokenLegendItem(color: Color, label: String) {
    val colors = MaterialTheme.antigravityColors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        StatusDot(color = color, size = 8.dp, glow = false)
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.sp),
            color = colors.inkSecondary,
        )
    }
}

@Composable
private fun ScopePill(label: String, isAccent: Boolean) {
    val colors = MaterialTheme.antigravityColors
    Surface(
        shape = RoundedCornerShape(6.dp),
        color = if (isAccent) colors.surfaceActiveTab else colors.surfaceElevated,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.5.sp, fontWeight = FontWeight.Medium),
            color = if (isAccent) colors.pillActiveForeground else colors.inkSecondary,
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
        )
    }
}
