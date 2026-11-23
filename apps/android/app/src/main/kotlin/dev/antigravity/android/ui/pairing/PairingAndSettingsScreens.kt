package dev.antigravity.android.ui.pairing

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.Router
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors

/**
 * Material 3 Onboarding & Pairing Screen supporting Remote Control QR/link pairing,
 * Google Cloud Relay WebView sign-in, Direct LAN / Tailscale manual pairing,
 * live connecting progress with Cancel, clear auth/network error diagnostics,
 * and offline ESDD demo exploration.
 */
@Composable
fun WelcomeAndPairingScreen(
    onScanQr: () -> Unit = {},
    onCloudRelaySignIn: () -> Unit = {},
    onConnectDirectLan: (endpointUrl: String, csrfToken: String) -> Unit = { _, _ -> },
    onContinueDemo: () -> Unit = {},
    isConnecting: Boolean = false,
    statusText: String? = null,
    errorText: String? = null,
    onCancelConnecting: () -> Unit = {},
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

        if (isConnecting) {
            AntigravitySurfaceCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("welcome-connecting-card"),
                borderColor = colors.accentPeriwinkle.copy(alpha = 0.45f),
                contentPadding = PaddingValues(14.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.5.dp,
                        color = colors.accentPeriwinkle,
                    )
                    Text(
                        text = statusText?.takeIf { it.isNotBlank() } ?: "Connecting to Antigravity host...",
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.inkReading,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(
                        onClick = onCancelConnecting,
                        modifier = Modifier.testTag("btn-welcome-cancel-connecting"),
                    ) {
                        Text("Cancel", color = colors.accentPeriwinkle)
                    }
                }
            }
        } else if (!errorText.isNullOrBlank()) {
            AntigravitySurfaceCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("welcome-error-banner"),
                containerColor = colors.surfaceAmberTint,
                borderColor = colors.statusWaiting.copy(alpha = 0.45f),
                contentPadding = PaddingValues(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Warning,
                        contentDescription = null,
                        tint = colors.statusWaiting,
                        modifier = Modifier
                            .padding(top = 2.dp)
                            .size(18.dp),
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            text = errorText,
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.inkReading,
                        )
                        if (errorText.contains("401") ||
                            errorText.contains("403") ||
                            errorText.contains("cookie", ignoreCase = true) ||
                            errorText.contains("sign", ignoreCase = true) ||
                            errorText.contains("auth", ignoreCase = true)
                        ) {
                            TextButton(
                                onClick = onCloudRelaySignIn,
                                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 2.dp),
                            ) {
                                Text("Sign in with Google again", color = colors.statusWaiting)
                            }
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        // Primary CTA: Scan Remote Control QR
        Button(
            onClick = onScanQr,
            enabled = !isConnecting,
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
            enabled = !isConnecting,
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
