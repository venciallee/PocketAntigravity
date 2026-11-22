package dev.antigravity.android.ui.pairing

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Router
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.components.SectionHeaderLabel
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.icons.toMaterialIcon
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AppAppearanceMode
import dev.antigravity.shared.model.AppThemePreset
import dev.antigravity.shared.protocol.CapabilitySupportState
import dev.antigravity.shared.protocol.HostCapability
import dev.antigravity.shared.protocol.HostCapabilityProfile
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/**
 * Material 3 Onboarding & Pairing Screen supporting Remote Control QR scanning,
 * Google Cloud Relay WebView sign-in, Direct LAN / Tailscale manual pairing,
 * and offline ESDD demo exploration.
 */
@Composable
fun WelcomeAndPairingScreen(
    onScanQr: () -> Unit = {},
    onCloudRelaySignIn: () -> Unit = {},
    onConnectDirectLan: (endpointUrl: String, csrfToken: String) -> Unit = { _, _ -> },
    onContinueDemo: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    var directLanExpanded by rememberSaveable { mutableStateOf(false) }
    var endpointUrl by rememberSaveable { mutableStateOf("https://192.168.1.42:42100") }
    var csrfToken by rememberSaveable { mutableStateOf("") }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 28.dp)
            .testTag("welcome-pairing-screen"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Spacer(modifier = Modifier.height(24.dp))

        // Brand Identity Badge
        Surface(
            modifier = Modifier.size(80.dp),
            shape = RoundedCornerShape(22.dp),
            color = colors.surfaceCard,
            border = BorderStroke(1.dp, colors.accentPeriwinkle.copy(alpha = 0.35f)),
            tonalElevation = 2.dp,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Rounded.Terminal,
                    contentDescription = "AG Pocket",
                    tint = colors.accentPeriwinkle,
                    modifier = Modifier.size(36.dp),
                )
            }
        }

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = "AG Pocket",
                style = MaterialTheme.typography.displaySmall,
                color = colors.inkReading,
            )
            Text(
                text = "Companion for Antigravity",
                style = MaterialTheme.typography.labelLarge,
                color = colors.accentPeriwinkle,
            )
            Text(
                text = "Scan the Remote Control QR code in Antigravity Desktop or sign in with Google Cloud Relay to steer your agents over Wi-Fi or 5G.",
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontSize = 14.5.sp,
                    lineHeight = 21.sp,
                ),
                color = colors.inkSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Primary CTA: Scan Remote Control QR
        Button(
            onClick = onScanQr,
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 54.dp)
                .testTag("btn-welcome-scan-qr"),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = colors.accentPeriwinkle,
                contentColor = colors.inkOnPrimaryCta,
            ),
        ) {
            Icon(
                imageVector = Icons.Rounded.QrCodeScanner,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = "Scan Remote Control QR",
                style = MaterialTheme.typography.titleSmall.copy(
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                ),
            )
        }

        // Secondary CTA: Google Cloud Relay WebView Sign-In
        FilledTonalButton(
            onClick = onCloudRelaySignIn,
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 52.dp)
                .testTag("btn-welcome-cloud-relay"),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.filledTonalButtonColors(
                containerColor = colors.surfaceElevated,
                contentColor = colors.inkReading,
            ),
        ) {
            Icon(
                imageVector = Icons.Rounded.Cloud,
                contentDescription = null,
                tint = colors.accentPeriwinkle,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = "Sign in with Google Cloud Relay",
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 15.sp),
            )
        }

        // Collapsible Direct LAN / Tailscale Entry Card
        AntigravitySurfaceCard(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(0.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 52.dp)
                    .clickable { directLanExpanded = !directLanExpanded }
                    .padding(horizontal = 16.dp, vertical = 12.dp)
                    .testTag("btn-welcome-direct-lan"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Router,
                    contentDescription = null,
                    tint = colors.inkLabel,
                    modifier = Modifier.size(20.dp),
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Direct LAN / Tailscale",
                        style = MaterialTheme.typography.titleSmall,
                        color = colors.inkReading,
                    )
                    Text(
                        text = "Manual endpoint URL & CSRF token",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                    )
                }
                Icon(
                    imageVector = if (directLanExpanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                    contentDescription = null,
                    tint = colors.inkSecondary,
                    modifier = Modifier.size(20.dp),
                )
            }

            if (directLanExpanded) {
                HorizontalDivider(color = colors.subtleDivider)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    OutlinedTextField(
                        value = endpointUrl,
                        onValueChange = { endpointUrl = it },
                        label = { Text("Host Endpoint URL") },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("input-direct-lan-url"),
                        textStyle = MaterialTheme.typography.bodyMedium.copy(
                            fontFamily = FontFamily.Monospace,
                            color = colors.inkReading,
                        ),
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedContainerColor = colors.surfaceInput,
                            unfocusedContainerColor = colors.surfaceInput,
                            focusedBorderColor = colors.accentPeriwinkle,
                            unfocusedBorderColor = colors.cardBorder,
                        ),
                    )
                    OutlinedTextField(
                        value = csrfToken,
                        onValueChange = { csrfToken = it },
                        label = { Text("CSRF Token (x-codeium-csrf-token)") },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("input-direct-lan-csrf"),
                        textStyle = MaterialTheme.typography.bodyMedium.copy(
                            fontFamily = FontFamily.Monospace,
                            color = colors.inkReading,
                        ),
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedContainerColor = colors.surfaceInput,
                            unfocusedContainerColor = colors.surfaceInput,
                            focusedBorderColor = colors.accentPeriwinkle,
                            unfocusedBorderColor = colors.cardBorder,
                        ),
                    )
                    Button(
                        onClick = { onConnectDirectLan(endpointUrl.trim(), csrfToken.trim()) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-submit-direct-lan"),
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.accentPeriwinkle,
                            contentColor = colors.inkOnPrimaryCta,
                        ),
                    ) {
                        Text(
                            text = "Connect Host",
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
        }

        TextButton(
            onClick = onContinueDemo,
            modifier = Modifier
                .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                .testTag("btn-welcome-demo"),
        ) {
            Text(
                text = "Continue in Offline Demo Mode",
                style = MaterialTheme.typography.labelLarge,
                color = colors.accentPeriwinkle,
            )
        }

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = "Open Antigravity on Mac / PC → Remote Control",
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkMuted,
            )
            Text(
                text = "Independent third-party companion · Not affiliated with Google LLC",
                style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.SansSerif),
                color = colors.inkMuted.copy(alpha = 0.8f),
                textAlign = TextAlign.Center,
            )
        }
    }
}

/**
 * Full Settings & v2.33 Customizations Hub screen featuring HostCapabilityProfile diagnostics,
 * Appearance & Theme presets (with Android 12+ Material You Dynamic Color switch),
 * Permission Preset selector, and collapsible Skills / Rules / MCP Servers / Plugins / Hooks panels.
 */
@Composable
fun SettingsAndCustomizationsScreen(
    coordinator: AntigravityCoreCoordinator,
    onOpenPairing: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val connectionState by coordinator.connectionState.collectAsStateWithLifecycle()
    val settingsState by coordinator.settingsStore.state.collectAsStateWithLifecycle()
    val capabilityBanner by coordinator.capabilityErrorBanner.collectAsStateWithLifecycle()
    val chatState by coordinator.chatState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var capabilityProfile by remember {
        mutableStateOf(
            HostCapabilityProfile(
                hostKey = connectionState.activeHost?.instanceId ?: "macbook-pro-local",
                reportedVersion = connectionState.activeHost?.version ?: "v2.33.0",
            ),
        )
    }

    LaunchedEffect(connectionState.activeHost, connectionState.isConnected) {
        val activeClient = coordinator.connectionStore.activeClient()
        capabilityProfile = activeClient?.capabilityProfile() ?: HostCapabilityProfile(
            hostKey = connectionState.activeHost?.instanceId ?: "macbook-pro-local",
            reportedVersion = connectionState.activeHost?.version ?: "v2.33.0",
            supportedMethods = if (coordinator.isVerificationMode) {
                HostCapability.allRegisteredMethods
            } else {
                emptySet()
            },
        )
    }

    var expandSkills by rememberSaveable { mutableStateOf(true) }
    var expandRules by rememberSaveable { mutableStateOf(false) }
    var expandMcp by rememberSaveable { mutableStateOf(true) }
    var expandPlugins by rememberSaveable { mutableStateOf(true) }
    var expandHooks by rememberSaveable { mutableStateOf(false) }

    val appearance = settingsState.appearance
    val customizations = settingsState.customizations
    val activeHost = connectionState.activeHost

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 104.dp)
            .testTag("settings-customizations-screen"),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        // Header
        Text(
            text = "Settings",
            style = MaterialTheme.typography.headlineMedium.copy(
                fontSize = 30.sp,
                lineHeight = 36.sp,
                fontWeight = FontWeight.Bold,
            ),
            color = colors.inkReading,
        )

        // Optional Capability Compatibility Banner
        if (!capabilityBanner.isNullOrBlank()) {
            AntigravitySurfaceCard(
                modifier = Modifier.fillMaxWidth(),
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
                        Text("Dismiss", color = colors.statusWaiting)
                    }
                }
            }
        }

        // 1. Host Connection & Capability Profile Card
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeaderLabel(title = "HOST & CAPABILITIES")

            AntigravitySurfaceCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("card-host-capability-profile"),
                contentPadding = PaddingValues(14.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        StatusDot(
                            color = if (connectionState.isConnected || coordinator.isVerificationMode) {
                                colors.statusDone
                            } else {
                                colors.statusWaiting
                            },
                            size = 9.dp,
                            glow = true,
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = activeHost?.hostname ?: "MacBook Pro",
                                style = MaterialTheme.typography.titleMedium,
                                color = colors.inkReading,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                text = "${activeHost?.channel?.displayName ?: "Direct LAN / Tailscale"} · ${capabilityProfile.displayVersionLabel}" +
                                    (connectionState.lastPingLatencyMs?.let { " · ${it}ms" } ?: ""),
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.inkSecondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        if (capabilityProfile.isCompanionBridge) {
                            Surface(
                                shape = RoundedCornerShape(100.dp),
                                color = colors.surfaceSelectionTint,
                            ) {
                                Text(
                                    text = "BRIDGE",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = colors.accentPeriwinkle,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                                )
                            }
                        }
                    }

                    val supportedCaps = remember(capabilityProfile) {
                        HostCapability.entries.count {
                            capabilityProfile.supportState(it) == CapabilitySupportState.SUPPORTED
                        }
                    }
                    val unsupportedCaps = remember(capabilityProfile) {
                        HostCapability.entries.count {
                            capabilityProfile.supportState(it) == CapabilitySupportState.UNSUPPORTED
                        }
                    }
                    Text(
                        text = "Protocol profile: $supportedCaps verified capabilities · $unsupportedCaps downgraded · ${connectionState.statusText}",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                    )

                    FilledTonalButton(
                        onClick = onOpenPairing,
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-open-pairing"),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.filledTonalButtonColors(
                            containerColor = colors.surfaceElevated,
                            contentColor = colors.inkReading,
                        ),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.QrCodeScanner,
                            contentDescription = null,
                            tint = colors.accentPeriwinkle,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "Pair or Switch Host",
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
        }

        // 2. Appearance, Theme Presets & Material You Dynamic Color
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeaderLabel(title = "APPEARANCE & THEME")

            AntigravitySurfaceCard(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(14.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Palette,
                            contentDescription = null,
                            tint = colors.accentPeriwinkle,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            text = "Theme Preset",
                            style = MaterialTheme.typography.titleSmall,
                            color = colors.inkReading,
                        )
                    }

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        AppThemePreset.entries.forEach { preset ->
                            val selected = appearance.theme == preset
                            FilterChip(
                                selected = selected,
                                onClick = {
                                    coordinator.settingsStore.updateAppearance { it.copy(theme = preset) }
                                },
                                label = {
                                    Text(
                                        text = preset.displayTitle,
                                        style = MaterialTheme.typography.labelLarge,
                                        maxLines = 1,
                                    )
                                },
                                colors = FilterChipDefaults.filterChipColors(
                                    containerColor = colors.surfacePill,
                                    labelColor = colors.inkLabel,
                                    selectedContainerColor = colors.surfaceSelectionTint,
                                    selectedLabelColor = colors.accentPeriwinkle,
                                ),
                                border = FilterChipDefaults.filterChipBorder(
                                    enabled = true,
                                    selected = selected,
                                    borderColor = colors.cardBorder,
                                    selectedBorderColor = colors.accentPeriwinkle,
                                ),
                                modifier = Modifier.testTag("theme-preset-${preset.name.lowercase()}"),
                            )
                        }
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        AppAppearanceMode.entries.forEach { mode ->
                            val selected = appearance.appearanceMode == mode
                            FilterChip(
                                selected = selected,
                                onClick = {
                                    coordinator.settingsStore.updateAppearance { it.copy(appearanceMode = mode) }
                                },
                                label = { Text(mode.displayTitle, maxLines = 1) },
                                colors = FilterChipDefaults.filterChipColors(
                                    containerColor = colors.surfacePill,
                                    labelColor = colors.inkLabel,
                                    selectedContainerColor = colors.pillActiveBackground,
                                    selectedLabelColor = colors.pillActiveForeground,
                                ),
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }

                    HorizontalDivider(color = colors.subtleDivider)

                    // Material You Dynamic Color Toggle
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = 56.dp)
                            .clickable {
                                coordinator.settingsStore.updateAppearance {
                                    it.copy(useDynamicColor = !it.useDynamicColor)
                                }
                            },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            Text(
                                text = "Material You Dynamic Color",
                                style = MaterialTheme.typography.titleSmall,
                                color = colors.inkReading,
                            )
                            Text(
                                text = "Adopt Android 12+ wallpaper surfaces while locking semantic status hues",
                                style = MaterialTheme.typography.bodySmall,
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
                            modifier = Modifier.testTag("toggle-dynamic-color"),
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = colors.inkOnPrimaryCta,
                                checkedTrackColor = colors.accentPeriwinkle,
                                uncheckedThumbColor = colors.inkLabel,
                                uncheckedTrackColor = colors.surfaceElevated,
                            ),
                        )
                    }
                }
            }
        }

        // 3. Permission Preset Selector
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeaderLabel(title = "PERMISSIONS & SANDBOX")

            AntigravitySurfaceCard(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(14.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Security,
                            contentDescription = null,
                            tint = colors.accentPeriwinkle,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            text = "Execution Permission Preset",
                            style = MaterialTheme.typography.titleSmall,
                            color = colors.inkReading,
                        )
                    }

                    val presets = listOf(
                        AgentPermissionPreset.REQUEST_REVIEW,
                        AgentPermissionPreset.DEFAULT_POLICY,
                        AgentPermissionPreset.AUTO,
                        AgentPermissionPreset.TURBO,
                    )
                    presets.forEach { preset ->
                        val selected = settingsState.activePermissionPreset == preset
                        Surface(
                            onClick = {
                                coordinator.settingsStore.updateAppearance {
                                    it.copy(globalPermissionPreset = preset)
                                }
                                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                    val rpcClient = if (coordinator.isVerificationMode) {
                                        null
                                    } else {
                                        coordinator.connectionStore.activeClient()
                                    }
                                    coordinator.settingsStore.setPermissionPreset(
                                        client = rpcClient,
                                        cascadeId = chatState.activeCascadeId.ifBlank { "cas-rate-limiter" },
                                        preset = preset,
                                    )
                                }
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .defaultMinSize(minHeight = 52.dp)
                                .testTag("permission-preset-${preset.rawValue}"),
                            shape = RoundedCornerShape(14.dp),
                            color = if (selected) colors.surfaceSelectionTint else colors.surfaceObsidian,
                            border = BorderStroke(
                                width = 1.dp,
                                color = if (selected) colors.accentPeriwinkle else colors.cardBorder,
                            ),
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Icon(
                                    imageVector = if (selected) {
                                        Icons.Rounded.CheckCircle
                                    } else {
                                        Icons.Rounded.RadioButtonUnchecked
                                    },
                                    contentDescription = null,
                                    tint = if (selected) colors.accentPeriwinkle else colors.inkMuted,
                                    modifier = Modifier.size(18.dp),
                                )
                                Icon(
                                    imageVector = preset.semanticIcon.toMaterialIcon(),
                                    contentDescription = null,
                                    tint = colors.inkLabel,
                                    modifier = Modifier.size(18.dp),
                                )
                                Text(
                                    text = preset.displayTitle,
                                    style = MaterialTheme.typography.titleSmall,
                                    color = colors.inkReading,
                                    modifier = Modifier.weight(1f),
                                )
                                if (preset.usesTerminalSandbox) {
                                    Surface(
                                        shape = RoundedCornerShape(100.dp),
                                        color = colors.statusDone.copy(alpha = 0.16f),
                                    ) {
                                        Text(
                                            text = "SANDBOX",
                                            style = MaterialTheme.typography.labelSmall.copy(
                                                fontFamily = FontFamily.SansSerif,
                                                fontSize = 10.sp,
                                                fontWeight = FontWeight.Bold,
                                            ),
                                            color = colors.statusDone,
                                            modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 4. v2.33 Customizations Hub (Collapsible Sections with Counts)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeaderLabel(title = "CUSTOMIZATIONS HUB")

            AntigravitySurfaceCard(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(14.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Extension,
                            contentDescription = null,
                            tint = colors.accentPeriwinkle,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            text = "Skills, Rules, MCP, Plugins & Hooks",
                            style = MaterialTheme.typography.titleSmall,
                            color = colors.inkReading,
                        )
                    }

                    // 4a. Skills
                    CollapsibleCustomizationGroup(
                        title = "Skills",
                        count = customizations.skills.size,
                        expanded = expandSkills,
                        onToggle = { expandSkills = !expandSkills },
                    ) {
                        customizations.skills.forEach { skill ->
                            Surface(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp),
                                color = colors.surfaceObsidian,
                                border = BorderStroke(1.dp, colors.cardBorder),
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = "/${skill.name}",
                                            style = MaterialTheme.typography.titleSmall.copy(
                                                fontFamily = FontFamily.Monospace,
                                            ),
                                            color = colors.accentPeriwinkle,
                                        )
                                        Text(
                                            text = skill.description,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = colors.inkSecondary,
                                        )
                                    }
                                    Text(
                                        text = skill.scope,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = colors.inkMuted,
                                    )
                                }
                            }
                        }
                    }

                    HorizontalDivider(color = colors.subtleDivider)

                    // 4b. Rules
                    CollapsibleCustomizationGroup(
                        title = "Rules",
                        count = customizations.rules.size,
                        expanded = expandRules,
                        onToggle = { expandRules = !expandRules },
                    ) {
                        customizations.rules.forEach { rule ->
                            Surface(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp),
                                color = colors.surfaceObsidian,
                                border = BorderStroke(1.dp, colors.cardBorder),
                            ) {
                                Column(
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                                    verticalArrangement = Arrangement.spacedBy(3.dp),
                                ) {
                                    Text(
                                        text = "${rule.name} · ${rule.scope}",
                                        style = MaterialTheme.typography.titleSmall,
                                        color = colors.inkReading,
                                    )
                                    Text(
                                        text = rule.preview,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = colors.inkSecondary,
                                    )
                                }
                            }
                        }
                    }

                    HorizontalDivider(color = colors.subtleDivider)

                    // 4c. MCP Servers with Restart Button
                    CollapsibleCustomizationGroup(
                        title = "MCP Servers",
                        count = customizations.mcpServers.size,
                        expanded = expandMcp,
                        onToggle = { expandMcp = !expandMcp },
                    ) {
                        customizations.mcpServers.forEach { server ->
                            Surface(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp),
                                color = colors.surfaceObsidian,
                                border = BorderStroke(1.dp, colors.cardBorder),
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 12.dp, vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    StatusDot(
                                        color = if (server.isConnected) colors.statusDone else colors.statusError,
                                        size = 8.dp,
                                    )
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = "${server.name} · ${server.toolCount} tools",
                                            style = MaterialTheme.typography.titleSmall,
                                            color = colors.inkReading,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                        Text(
                                            text = server.errorMessage
                                                ?: "${server.transport} · ${if (server.oauthConnected) "OAuth connected" else "Local"}",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = if (server.errorMessage != null) colors.statusError else colors.inkSecondary,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                    FilledTonalButton(
                                        onClick = {
                                            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                                val rpcClient = if (coordinator.isVerificationMode) {
                                                    null
                                                } else {
                                                    coordinator.connectionStore.activeClient()
                                                }
                                                coordinator.settingsStore.restartMcpServer(
                                                    client = rpcClient,
                                                    serverName = server.name,
                                                )
                                            }
                                        },
                                        modifier = Modifier
                                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                                            .testTag("btn-restart-mcp-${server.name}"),
                                        shape = RoundedCornerShape(100.dp),
                                        colors = ButtonDefaults.filledTonalButtonColors(
                                            containerColor = colors.surfaceElevated,
                                            contentColor = colors.accentPeriwinkle,
                                        ),
                                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.Refresh,
                                            contentDescription = null,
                                            modifier = Modifier.size(14.dp),
                                        )
                                        Spacer(modifier = Modifier.width(4.dp))
                                        Text("Restart", style = MaterialTheme.typography.labelMedium)
                                    }
                                }
                            }
                        }
                    }

                    HorizontalDivider(color = colors.subtleDivider)

                    // 4d. Plugins Marketplace with Toggle / Install
                    CollapsibleCustomizationGroup(
                        title = "Plugins Marketplace",
                        count = customizations.plugins.size,
                        expanded = expandPlugins,
                        onToggle = { expandPlugins = !expandPlugins },
                    ) {
                        customizations.plugins.forEach { plugin ->
                            Surface(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp),
                                color = colors.surfaceObsidian,
                                border = BorderStroke(1.dp, colors.cardBorder),
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 12.dp, vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Column(
                                        modifier = Modifier.weight(1f),
                                        verticalArrangement = Arrangement.spacedBy(2.dp),
                                    ) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                                        ) {
                                            Text(
                                                text = plugin.name,
                                                style = MaterialTheme.typography.titleSmall,
                                                color = colors.inkReading,
                                            )
                                            if (plugin.isFeaturedPartner) {
                                                Surface(
                                                    shape = RoundedCornerShape(100.dp),
                                                    color = colors.surfaceSelectionTint,
                                                ) {
                                                    Text(
                                                        text = "PARTNER",
                                                        style = MaterialTheme.typography.labelSmall.copy(
                                                            fontFamily = FontFamily.SansSerif,
                                                            fontSize = 9.sp,
                                                            fontWeight = FontWeight.Bold,
                                                        ),
                                                        color = colors.accentPeriwinkle,
                                                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                                    )
                                                }
                                            }
                                        }
                                        Text(
                                            text = plugin.summary,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = colors.inkSecondary,
                                        )
                                    }
                                    if (plugin.isInstalled) {
                                        Switch(
                                            checked = plugin.isEnabled,
                                            onCheckedChange = { enabled ->
                                                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                                    val rpcClient = if (coordinator.isVerificationMode) {
                                                        null
                                                    } else {
                                                        coordinator.connectionStore.activeClient()
                                                    }
                                                    coordinator.settingsStore.togglePlugin(
                                                        client = rpcClient,
                                                        pluginId = plugin.id,
                                                        isEnabled = enabled,
                                                    )
                                                }
                                            },
                                            modifier = Modifier.testTag("toggle-plugin-${plugin.id}"),
                                            colors = SwitchDefaults.colors(
                                                checkedThumbColor = colors.inkOnPrimaryCta,
                                                checkedTrackColor = colors.accentPeriwinkle,
                                                uncheckedThumbColor = colors.inkLabel,
                                                uncheckedTrackColor = colors.surfaceElevated,
                                            ),
                                        )
                                    } else {
                                        FilledTonalButton(
                                            onClick = {
                                                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                                    val rpcClient = if (coordinator.isVerificationMode) {
                                                        null
                                                    } else {
                                                        coordinator.connectionStore.activeClient()
                                                    }
                                                    coordinator.settingsStore.installPlugin(
                                                        client = rpcClient,
                                                        pluginId = plugin.id,
                                                    )
                                                }
                                            },
                                            modifier = Modifier
                                                .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                                                .testTag("btn-install-plugin-${plugin.id}"),
                                            shape = RoundedCornerShape(100.dp),
                                            colors = ButtonDefaults.filledTonalButtonColors(
                                                containerColor = colors.accentPeriwinkle,
                                                contentColor = colors.inkOnPrimaryCta,
                                            ),
                                            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
                                        ) {
                                            Text("Install", style = MaterialTheme.typography.labelMedium)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HorizontalDivider(color = colors.subtleDivider)

                    // 4e. Lifecycle Hooks
                    CollapsibleCustomizationGroup(
                        title = "Lifecycle Hooks",
                        count = customizations.hooks.size,
                        expanded = expandHooks,
                        onToggle = { expandHooks = !expandHooks },
                    ) {
                        customizations.hooks.forEach { hook ->
                            Surface(
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp),
                                color = colors.surfaceObsidian,
                                border = BorderStroke(1.dp, colors.cardBorder),
                            ) {
                                Column(
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                                    verticalArrangement = Arrangement.spacedBy(3.dp),
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    ) {
                                        Text(
                                            text = hook.event,
                                            style = MaterialTheme.typography.titleSmall,
                                            color = colors.inkReading,
                                        )
                                        Text(
                                            text = "· ${hook.matcher} · ${hook.timeoutSeconds}s",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = colors.inkMuted,
                                        )
                                    }
                                    Text(
                                        text = hook.command,
                                        style = MaterialTheme.typography.bodySmall.copy(
                                            fontFamily = FontFamily.Monospace,
                                        ),
                                        color = colors.inkLabel,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CollapsibleCustomizationGroup(
    title: String,
    count: Int,
    expanded: Boolean,
    onToggle: () -> Unit,
    content: @Composable () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                .clickable(onClick = onToggle),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                color = colors.inkReading,
                modifier = Modifier.weight(1f),
            )
            Surface(
                shape = CircleShape,
                color = colors.surfaceBadge,
            ) {
                Text(
                    text = count.toString(),
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.inkSecondary,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                )
            }
            Icon(
                imageVector = if (expanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                contentDescription = if (expanded) "Collapse $title" else "Expand $title",
                tint = colors.inkSecondary,
                modifier = Modifier.size(18.dp),
            )
        }
        if (expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                content()
            }
        }
    }
}
