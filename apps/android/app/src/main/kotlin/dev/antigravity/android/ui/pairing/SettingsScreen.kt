package dev.antigravity.android.ui.pairing

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.LaptopMac
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.RadioButtonChecked
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.AppAppearanceMode
import dev.antigravity.shared.model.AppLanguage
import dev.antigravity.shared.model.AppThemePreset
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.model.localizedTitle
import dev.antigravity.shared.protocol.ConnectionLifecyclePhase
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * Flattened Material 3 Mobile Settings screen (`UE15_SETTINGS`) aligned with
 * `docs/ue/android/and-settings.png` and `docs/ue/android/and-settings-more.png`.
 */
@Composable
fun SettingsAndCustomizationsScreen(
    coordinator: AntigravityCoreCoordinator,
    onOpenPairing: () -> Unit,
    onBack: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val lang = LocalAppLanguage.current
    val connectionState by coordinator.connectionState.collectAsStateWithLifecycle()
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()
    val settingsState by coordinator.settingsStore.state.collectAsStateWithLifecycle()
    val capabilityBanner by coordinator.capabilityErrorBanner.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var showMoreSubpage by rememberSaveable { mutableStateOf(false) }
    var languageMenuExpanded by remember { mutableStateOf(false) }
    var selectedHostId by rememberSaveable(connectionState.activeHost?.instanceId) {
        mutableStateOf(connectionState.activeHost?.instanceId ?: "macbook-pro-local")
    }
    var didRefreshHosts by remember { mutableStateOf(false) }

    val appearance = settingsState.appearance
    val activeHost = connectionState.activeHost
    val isNoInternet = !coordinator.isVerificationMode &&
        connectionState.hasPairedBackend &&
        !connectionState.isDeviceNetworkReachable
    val isConnectingHero = !coordinator.isVerificationMode &&
        connectionState.isDeviceNetworkReachable &&
        (connectionState.isConnecting || connectionState.lifecyclePhase is ConnectionLifecyclePhase.Connecting)
    val isOnlineConnected = coordinator.isVerificationMode ||
        (connectionState.isDeviceNetworkReachable && connectionState.isConnected && (activeHost?.isOnline == true))
    val isGoogleAuthExpired = !coordinator.isVerificationMode &&
        activeHost?.channel == RemoteConnectionChannel.CLOUD_RELAY &&
        (connectionState.statusText.contains("Expired", ignoreCase = true) ||
            connectionState.errorText?.contains("unauthorized", ignoreCase = true) == true)

    LaunchedEffect(connectionState.hasPairedBackend, activeHost?.channel) {
        if (!coordinator.isVerificationMode &&
            connectionState.hasPairedBackend &&
            activeHost?.channel == RemoteConnectionChannel.CLOUD_RELAY
        ) {
            try {
                coordinator.refreshAvailableRelayHosts(verifyEndToEnd = true)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Best-effort live host liveness check on Settings entry.
            }
        }
    }

    val displayHosts = remember(
        connectionState.knownHosts,
        connectionState.availableRelayInstances,
        connectionState.isDeviceNetworkReachable,
        coordinator.isVerificationMode,
    ) {
        if (coordinator.isVerificationMode) {
            connectionState.knownHosts.filterNot { host ->
                host.instanceId == "cloud-vm-us-central1"
            }
        } else if (connectionState.availableRelayInstances.isNotEmpty()) {
            val fromRelay = connectionState.availableRelayInstances.map { inst ->
                val existing = connectionState.knownHosts.firstOrNull { it.instanceId == inst.uuid }
                RemoteHostInstance(
                    instanceId = inst.uuid,
                    hostname = inst.name,
                    version = inst.version.ifBlank { existing?.version.orEmpty() },
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = existing?.endpointUrl ?: "https://antigravity.google.com/r/${inst.uuid}",
                    isOnline = connectionState.isDeviceNetworkReachable && inst.status.isReachable,
                    latencyMs = existing?.latencyMs ?: 0,
                )
            }
            val relayIds = fromRelay.map { it.instanceId }.toSet()
            val remainingKnown = connectionState.knownHosts
                .filterNot { it.instanceId == "unpaired" || it.hostname.equals("cloud", ignoreCase = true) || it.instanceId in relayIds }
                .map { host ->
                    host.copy(isOnline = connectionState.isLocalHostOnline(host.instanceId, host.hostname))
                }
            fromRelay + remainingKnown
        } else {
            connectionState.knownHosts
                .filterNot { it.instanceId == "unpaired" || it.hostname.equals("cloud", ignoreCase = true) }
                .map { host ->
                    host.copy(isOnline = connectionState.isLocalHostOnline(host.instanceId, host.hostname))
                }
        }
    }

    if (showMoreSubpage) {
        SettingsMoreSubpage(
            coordinator = coordinator,
            appearance = appearance,
            activePermissionPreset = settingsState.localPermissionPreset,
            onBack = { showMoreSubpage = false },
            onDisconnect = {
                scope.launch {
                    runCatching { coordinator.disconnectAndClearCredentials() }
                    onOpenPairing()
                }
            },
            modifier = modifier,
        )
        return
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(top = 8.dp, bottom = 32.dp)
            .testTag("settings-customizations-screen"),
    ) {
        // Top back button
        IconButton(
            onClick = onBack,
            modifier = Modifier
                .size(44.dp)
                .testTag("btn-settings-back"),
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                contentDescription = tr("Back", "返回"),
                tint = colors.inkReading,
                modifier = Modifier.size(22.dp),
            )
        }

        Spacer(modifier = Modifier.height(6.dp))

        // Large Settings Title
        Text(
            text = tr("Settings", "设置"),
            style = MaterialTheme.typography.headlineMedium.copy(
                fontSize = 30.sp,
                lineHeight = 36.sp,
                fontWeight = FontWeight.Normal,
                letterSpacing = (-0.2).sp,
            ),
            color = colors.inkReading,
        )

        Spacer(modifier = Modifier.height(18.dp))

        if (!capabilityBanner.isNullOrBlank()) {
            AntigravitySurfaceCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 14.dp),
                containerColor = colors.surfaceAmberTint,
                borderColor = colors.statusWaiting.copy(alpha = 0.35f),
                contentPadding = PaddingValues(12.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Warning,
                        contentDescription = null,
                        tint = colors.statusWaiting,
                        modifier = Modifier.size(18.dp),
                    )
                    Text(
                        text = capabilityBanner.orEmpty(),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkReading,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = { coordinator.dismissCapabilityError() }) {
                        Text(tr("Dismiss", "关闭"), color = colors.statusWaiting)
                    }
                }
            }
        }

        // 1. Connected Host Hero Card
        val heroTint = when {
            isOnlineConnected -> colors.statusDone
            isConnectingHero -> colors.accentPeriwinkle
            isGoogleAuthExpired -> colors.statusWaiting
            else -> colors.statusError
        }
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .testTag("card-host-capability-profile"),
            shape = RoundedCornerShape(22.dp),
            color = colors.surfaceCard,
            border = BorderStroke(
                1.dp,
                if (isOnlineConnected) colors.cardBorder.copy(alpha = 0.7f) else heroTint.copy(alpha = 0.45f),
            ),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(heroTint.copy(alpha = 0.14f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (isConnectingHero) {
                            CircularProgressIndicator(
                                strokeWidth = 2.dp,
                                color = colors.accentPeriwinkle,
                                modifier = Modifier.size(20.dp),
                            )
                        } else {
                            Icon(
                                imageVector = when {
                                    isOnlineConnected -> Icons.Rounded.LaptopMac
                                    isGoogleAuthExpired -> Icons.Rounded.Warning
                                    else -> Icons.Rounded.WifiOff
                                },
                                contentDescription = null,
                                tint = heroTint,
                                modifier = Modifier.size(22.dp),
                            )
                        }
                    }
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        val hostDisplayName = activeHost?.hostname ?: "MacBook Pro"
                        val heroTitle = when {
                            isOnlineConnected -> tr("Connected: $hostDisplayName", "已连接：$hostDisplayName")
                            isConnectingHero -> tr("Connecting: $hostDisplayName", "正在连接：$hostDisplayName")
                            isNoInternet -> tr("No Internet Connection", "无网络连接")
                            isGoogleAuthExpired -> tr("Google Sign-In Expired", "Google 登录已过期")
                            connectionState.hasPairedBackend -> tr("Host Offline: $hostDisplayName", "主机离线：$hostDisplayName")
                            else -> tr("Not Connected", "未连接")
                        }
                        Text(
                            text = heroTitle,
                            style = MaterialTheme.typography.titleMedium.copy(
                                fontSize = 16.sp,
                                fontWeight = FontWeight.SemiBold,
                            ),
                            color = colors.inkReading,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        val channelLabel = when (activeHost?.channel) {
                            RemoteConnectionChannel.DIRECT_HOST -> tr("Direct LAN", "局域网直连")
                            else -> tr("Cloud Relay", "云中继")
                        }
                        val latencyMs = connectionState.lastPingLatencyMs ?: activeHost?.latencyMs ?: 42
                        val sessionCount = if (coordinator.isVerificationMode) 12 else syncState.summaries.size
                        val heroSubtitle = when {
                            isOnlineConnected -> tr(
                                "$channelLabel · ${latencyMs}ms · $sessionCount sessions",
                                "$channelLabel · ${latencyMs}ms · $sessionCount 个会话",
                            )
                            isConnectingHero -> connectionState.statusText.ifBlank {
                                tr("Checking host reachability...", "正在检查主机连通性...")
                            }
                            isNoInternet -> tr(
                                "Paused while offline · Auto-resumes when network returns",
                                "离线时已暂停 · 网络恢复后自动继续",
                            )
                            isGoogleAuthExpired -> tr(
                                "Sign in with Google again to restore sync",
                                "请重新登录 Google 以恢复同步",
                            )
                            else -> tr(
                                "Power-saving backoff reconnect · Tap Reconnect or scan QR",
                                "节能退避重连中 · 点击重连或重新扫码",
                            )
                        }
                        Text(
                            text = heroSubtitle,
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                            color = colors.inkSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }

                if (!coordinator.isVerificationMode && connectionState.hasPairedBackend && !isOnlineConnected && !isConnectingHero && !isNoInternet) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        FilledTonalButton(
                            onClick = {
                                scope.launch {
                                    try {
                                        coordinator.reconnectNow()
                                    } catch (e: CancellationException) {
                                        throw e
                                    } catch (_: Throwable) {
                                        // Status reflected in connectionState.
                                    }
                                }
                            },
                            modifier = Modifier
                                .weight(1f)
                                .height(44.dp)
                                .testTag("btn-reconnect-host"),
                            shape = RoundedCornerShape(100.dp),
                            colors = ButtonDefaults.filledTonalButtonColors(
                                containerColor = colors.accentPeriwinkle.copy(alpha = 0.18f),
                                contentColor = colors.accentPeriwinkle,
                            ),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Refresh,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                text = tr("Reconnect", "重新连接"),
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold,
                                ),
                            )
                        }
                        FilledTonalButton(
                            onClick = onOpenPairing,
                            modifier = Modifier
                                .weight(1f)
                                .height(44.dp)
                                .testTag("btn-scan-new-qr"),
                            shape = RoundedCornerShape(100.dp),
                            colors = ButtonDefaults.filledTonalButtonColors(
                                containerColor = colors.surfaceSelectionTint,
                                contentColor = colors.inkReading,
                            ),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.QrCodeScanner,
                                contentDescription = null,
                                tint = colors.inkReading,
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                text = tr("Scan New QR", "扫描新二维码"),
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold,
                                ),
                            )
                        }
                    }
                } else {
                    FilledTonalButton(
                        onClick = onOpenPairing,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(44.dp)
                            .testTag("btn-scan-new-qr"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.filledTonalButtonColors(
                            containerColor = colors.surfaceSelectionTint,
                            contentColor = colors.inkReading,
                        ),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.QrCodeScanner,
                            contentDescription = null,
                            tint = colors.inkReading,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = tr("Scan New QR", "扫描新二维码"),
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 14.5.sp,
                                fontWeight = FontWeight.SemiBold,
                            ),
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(22.dp))

        // 2. Available Hosts
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = tr("Available hosts", "可用主机"),
                style = MaterialTheme.typography.titleSmall.copy(
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
                color = colors.accentPeriwinkle,
            )
            val refreshLabel = when {
                connectionState.isRefreshingRelayHosts -> tr("Probing...", "探测中...")
                didRefreshHosts -> tr("Refreshed", "已刷新")
                else -> tr("Refresh", "刷新")
            }
            Text(
                text = refreshLabel,
                style = MaterialTheme.typography.titleSmall.copy(
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
                color = colors.accentPeriwinkle,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(enabled = !connectionState.isRefreshingRelayHosts) {
                        didRefreshHosts = true
                        scope.launch {
                            try {
                                coordinator.refreshAvailableRelayHosts(verifyEndToEnd = true)
                                coordinator.refreshWorkspacesAndSummaries(skipRelayListRefresh = true)
                            } catch (e: CancellationException) {
                                throw e
                            } catch (_: Throwable) {
                                // ConnectionState reflects offline/error outcome cleanly.
                            }
                        }
                    }
                    .padding(horizontal = 4.dp, vertical = 2.dp)
                    .testTag("btn-refresh-hosts"),
            )
        }

        Spacer(modifier = Modifier.height(10.dp))

        displayHosts.forEach { host ->
            val isSelected = selectedHostId == host.instanceId
            val hostOnline = connectionState.isLocalHostOnline(host.instanceId, host.hostname)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 56.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .clickable {
                        selectedHostId = host.instanceId
                        coordinator.selectHostScope(
                            AgentsHostFilterScope.LocalHost(id = host.instanceId, name = host.hostname),
                        )
                    }
                    .padding(vertical = 8.dp)
                    .testTag("settings-host-${host.instanceId}"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Icon(
                    imageVector = if (isSelected) Icons.Rounded.RadioButtonChecked else Icons.Rounded.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = if (isSelected) colors.accentPeriwinkle else colors.inkMuted,
                    modifier = Modifier.size(22.dp),
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = host.hostname,
                        style = MaterialTheme.typography.bodyLarge.copy(
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Normal,
                        ),
                        color = colors.inkReading,
                    )
                    val onlineText = if (hostOnline) tr("Online", "在线") else tr("Offline", "离线")
                    val cleanVer = host.version.removePrefix("v")
                    Text(
                        text = if (cleanVer.isBlank()) onlineText else "$onlineText · $cleanVer",
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = if (hostOnline) colors.statusDone else colors.inkSecondary,
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(18.dp))

        // 3. Appearance
        Text(
            text = tr("Appearance", "外观"),
            style = MaterialTheme.typography.titleSmall.copy(
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
            ),
            color = colors.accentPeriwinkle,
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Material 3 Segmented Button (System | Dark | Light)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(42.dp)
                .clip(RoundedCornerShape(100.dp))
                .border(1.dp, colors.cardBorder, RoundedCornerShape(100.dp)),
        ) {
            val modes = listOf(
                AppAppearanceMode.SYSTEM,
                AppAppearanceMode.DARK,
                AppAppearanceMode.LIGHT,
            )
            modes.forEachIndexed { index, mode ->
                val selected = appearance.appearanceMode == mode
                if (index > 0) {
                    Box(
                        modifier = Modifier
                            .width(1.dp)
                            .fillMaxHeight()
                            .background(colors.cardBorder),
                    )
                }
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .background(if (selected) colors.surfaceSelectionTint else Color.Transparent)
                        .clickable {
                            coordinator.settingsStore.updateAppearance { it.copy(appearanceMode = mode) }
                        }
                        .testTag("appearance-mode-${mode.name.lowercase()}"),
                    contentAlignment = Alignment.Center,
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        if (selected) {
                            Icon(
                                imageVector = Icons.Rounded.Check,
                                contentDescription = null,
                                tint = colors.inkReading,
                                modifier = Modifier.size(15.dp),
                            )
                        }
                        Text(
                            text = mode.localizedTitle(lang),
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 13.5.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.inkReading,
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Theme Preset Split-Swatch Chips (Obsidian, Nord, Everforest)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val presets = listOf(
                Triple(AppThemePreset.OBSIDIAN, Color(0xFF141519), Color(0xFF8DB8FF)),
                Triple(AppThemePreset.NORD, Color(0xFF2E3440), Color(0xFF88C0D0)),
                Triple(AppThemePreset.EVERFOREST_DARK, Color(0xFF2D353B), Color(0xFFA7C080)),
            )
            presets.forEach { (preset, bgHex, accentHex) ->
                val selected = appearance.theme == preset
                Surface(
                    onClick = {
                        coordinator.settingsStore.updateAppearance { it.copy(theme = preset) }
                    },
                    modifier = Modifier
                        .weight(1f)
                        .height(44.dp)
                        .testTag("theme-preset-${preset.name.lowercase()}"),
                    shape = RoundedCornerShape(14.dp),
                    color = colors.surfaceObsidian,
                    border = BorderStroke(
                        width = if (selected) 1.5.dp else 1.dp,
                        color = if (selected) colors.accentPeriwinkle else colors.cardBorder,
                    ),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        SplitThemeSwatch(
                            darkHalf = bgHex,
                            accentHalf = accentHex,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = preset.localizedTitle(lang),
                            style = MaterialTheme.typography.labelMedium.copy(
                                fontSize = 12.5.sp,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                            ),
                            color = colors.inkReading,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (selected) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Icon(
                                imageVector = Icons.Rounded.Check,
                                contentDescription = null,
                                tint = colors.accentPeriwinkle,
                                modifier = Modifier.size(14.dp),
                            )
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Dynamic Color Switch Row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 56.dp)
                .clickable {
                    coordinator.settingsStore.updateAppearance {
                        it.copy(useDynamicColor = !it.useDynamicColor)
                    }
                }
                .padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = tr("Dynamic color", "动态取色"),
                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                    color = colors.inkReading,
                )
                Text(
                    text = tr(
                        "Material You from wallpaper · status colors stay fixed",
                        "跟随壁纸自动适配 Material You · 状态色保持固定",
                    ),
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp, lineHeight = 18.sp),
                    color = colors.inkSecondary,
                )
            }
            Switch(
                checked = appearance.useDynamicColor,
                onCheckedChange = { enabled ->
                    coordinator.settingsStore.updateAppearance {
                        it.copy(useDynamicColor = enabled)
                    }
                },
                modifier = Modifier.testTag("switch-dynamic-color"),
                colors = SwitchDefaults.colors(
                    checkedThumbColor = colors.inkOnPrimaryCta,
                    checkedTrackColor = colors.accentPeriwinkle,
                    uncheckedThumbColor = colors.inkSecondary,
                    uncheckedTrackColor = colors.surfaceElevated,
                    uncheckedBorderColor = colors.inkMuted,
                ),
            )
        }

        Spacer(modifier = Modifier.height(10.dp))

        // 4. Language Row
        Box(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 56.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .clickable { languageMenuExpanded = true }
                    .padding(vertical = 6.dp)
                    .testTag("row-settings-language"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        text = tr("Language", "语言"),
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                        color = colors.inkReading,
                    )
                    Text(
                        text = "English · 简体中文",
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = colors.inkSecondary,
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        text = appearance.language.displayTitle,
                        style = MaterialTheme.typography.titleSmall.copy(
                            fontSize = 14.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.accentPeriwinkle,
                    )
                    Icon(
                        imageVector = Icons.Rounded.ArrowDropDown,
                        contentDescription = tr("Select language", "选择语言"),
                        tint = colors.inkSecondary,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }

            DropdownMenu(
                expanded = languageMenuExpanded,
                onDismissRequest = { languageMenuExpanded = false },
                containerColor = colors.surfacePopover,
            ) {
                AppLanguage.entries.forEach { option ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = option.displayTitle,
                                color = if (appearance.language == option) colors.accentPeriwinkle else colors.inkReading,
                            )
                        },
                        onClick = {
                            coordinator.settingsStore.setAppLanguage(option)
                            languageMenuExpanded = false
                        },
                        modifier = Modifier.testTag("language-option-${option.name.lowercase()}"),
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(6.dp))
        HorizontalDivider(color = colors.subtleDivider)
        Spacer(modifier = Modifier.height(6.dp))

        // 5. Permissions, notifications & about drill-down row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 52.dp)
                .clip(RoundedCornerShape(10.dp))
                .clickable { showMoreSubpage = true }
                .padding(vertical = 8.dp)
                .testTag("row-settings-more"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = tr("Permissions, notifications & about", "权限、通知与关于"),
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                color = colors.inkReading,
                modifier = Modifier.weight(1f),
            )
            Icon(
                imageVector = Icons.Rounded.ChevronRight,
                contentDescription = null,
                tint = colors.inkSecondary,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
private fun SettingsMoreSubpage(
    coordinator: AntigravityCoreCoordinator,
    appearance: dev.antigravity.shared.model.AppAppearancePreferences,
    activePermissionPreset: AgentPermissionPreset,
    onBack: () -> Unit,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val lang = LocalAppLanguage.current

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(top = 8.dp, bottom = 32.dp)
            .testTag("settings-more-subpage"),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier
                    .size(44.dp)
                    .testTag("btn-settings-more-back"),
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                    contentDescription = tr("Back", "返回"),
                    tint = colors.inkReading,
                    modifier = Modifier.size(22.dp),
                )
            }
            Text(
                text = tr("Settings", "设置"),
                style = MaterialTheme.typography.titleLarge.copy(
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Normal,
                ),
                color = colors.inkReading,
            )
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Permissions
        Text(
            text = tr("Permissions", "权限"),
            style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
            color = colors.accentPeriwinkle,
        )
        Text(
            text = tr("Default policy for commands & tools", "命令与工具的默认权限策略"),
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
            color = colors.inkSecondary,
            modifier = Modifier.padding(top = 2.dp, bottom = 10.dp),
        )

        val presets = listOf(
            AgentPermissionPreset.REQUEST_REVIEW to tr("Every command requires approval", "每条命令都需要审批"),
            AgentPermissionPreset.DEFAULT_POLICY to tr("Ask before sensitive operations", "敏感操作前先征求确认"),
            AgentPermissionPreset.AUTO to tr("Automatically decide if commands run", "自动判断是否直接执行命令"),
            AgentPermissionPreset.TURBO to tr("Run all commands without restrictions", "无限制自动执行所有命令"),
        )
        presets.forEach { (preset, desc) ->
            val selected = activePermissionPreset == preset
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 56.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .clickable {
                        coordinator.settingsStore.selectPermissionPreset(
                            preset = preset,
                            isRemote = false,
                        )
                    }
                    .padding(vertical = 8.dp)
                    .testTag("permission-preset-${preset.rawValue}"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Icon(
                    imageVector = if (selected) Icons.Rounded.RadioButtonChecked else Icons.Rounded.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = if (selected) colors.accentPeriwinkle else colors.inkMuted,
                    modifier = Modifier.size(22.dp),
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = preset.localizedTitle(lang),
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                        color = colors.inkReading,
                    )
                    Text(
                        text = desc,
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = colors.inkSecondary,
                    )
                }
            }
        }

        Text(
            text = tr(
                "Applies to new turns on your paired Mac/PC. Fine-grained rules are managed in Antigravity Desktop.",
                "适用于已配对 Mac/PC 上的新轮次。精细化权限规则请在 Antigravity Desktop 中管理。",
            ),
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, lineHeight = 18.sp),
            color = colors.inkSecondary,
            modifier = Modifier.padding(top = 8.dp, bottom = 22.dp),
        )

        // Notifications
        Text(
            text = tr("Notifications", "通知"),
            style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
            color = colors.accentPeriwinkle,
        )
        Text(
            text = tr("Alerts while agents run in the background", "代理在后台运行时的提醒"),
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
            color = colors.inkSecondary,
            modifier = Modifier.padding(top = 2.dp, bottom = 10.dp),
        )

        NotificationSwitchRow(
            title = tr("Approval & Completion Alerts", "审批与完成提醒"),
            subtitle = tr("Notify on waiting approval, run complete, or error", "在等待审批、任务完成或出错时推送通知"),
            checked = appearance.notificationsEnabled,
            onCheckedChange = { enabled ->
                coordinator.settingsStore.updateAppearance { it.copy(notificationsEnabled = enabled) }
            },
            testTag = "switch-notif-approval",
        )
        NotificationSwitchRow(
            title = tr("Quiet on Manual Stop", "手动停止时静音"),
            subtitle = tr("Skip the alert when you stop a run yourself", "由你主动停止运行时不发送提醒"),
            checked = appearance.suppressManualStopNotification,
            onCheckedChange = { enabled ->
                coordinator.settingsStore.updateAppearance { it.copy(suppressManualStopNotification = enabled) }
            },
            testTag = "switch-notif-quiet-stop",
        )
        NotificationSwitchRow(
            title = tr("Live updates", "实时进度通知"),
            subtitle = tr("Show run progress as a live notification", "在状态栏与锁屏中实时显示运行进度"),
            checked = appearance.liveUpdatesEnabled,
            onCheckedChange = { enabled ->
                coordinator.settingsStore.updateAppearance { it.copy(liveUpdatesEnabled = enabled) }
            },
            testTag = "switch-notif-live-updates",
        )

        Spacer(modifier = Modifier.height(18.dp))

        FilledTonalButton(
            onClick = onDisconnect,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .testTag("btn-sign-out-disconnect"),
            shape = RoundedCornerShape(100.dp),
            colors = ButtonDefaults.filledTonalButtonColors(
                containerColor = colors.statusError.copy(alpha = 0.16f),
                contentColor = colors.statusError,
            ),
        ) {
            Text(
                text = tr("Sign out & disconnect host", "退出登录并断开主机"),
                style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold),
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // About (App Store / Play Compliance)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .testTag("card-about-copyright"),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = tr("About", "关于"),
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                color = colors.accentPeriwinkle,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "AG Pocket",
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                        color = colors.inkReading,
                    )
                    Text(
                        text = tr("Companion for Antigravity", "Antigravity 移动伴侣客户端"),
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = colors.inkSecondary,
                    )
                }
                Text(
                    text = "v2.0.0 (1)",
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                    color = colors.inkSecondary,
                )
            }
            Text(
                text = tr(
                    "Independent third-party client, not affiliated with Google LLC.",
                    "独立第三方客户端，与 Google LLC 无隶属或官方关联关系。",
                ),
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp),
                color = colors.inkMuted,
            )
        }
    }
}

@Composable
private fun NotificationSwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    testTag: String,
) {
    val colors = MaterialTheme.antigravityColors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
            .clickable { onCheckedChange(!checked) }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp),
                color = colors.inkReading,
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                color = colors.inkSecondary,
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            modifier = Modifier.testTag(testTag),
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

@Composable
private fun SplitThemeSwatch(
    darkHalf: Color,
    accentHalf: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier.clip(CircleShape)) {
        drawCircle(color = darkHalf)
        val path = Path().apply {
            moveTo(size.width, 0f)
            lineTo(size.width, size.height)
            lineTo(0f, size.height)
            close()
        }
        drawPath(path = path, color = accentHalf)
    }
}
