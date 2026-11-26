package dev.antigravity.android.ui.pairing

import android.annotation.SuppressLint
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import dev.antigravity.android.core.platform.CloudRelayCookieBridge
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.protocol.SapisidHashGenerator

/**
 * Result captured from an authenticated Google Cloud Relay WebView session on Android.
 */
data class CloudRelayCapturedSession(
    val cookieHeader: String,
    val relayApiKey: String? = null,
    val authUser: String? = null,
    val finalUrl: String? = null,
)

/**
 * Full-screen Material 3 Google Cloud Relay WebView sign-in modal with 1:1 feature parity
 * against iOS `CloudRelaySignInSheet`:
 * - Strips Android WebView `; wv)` UA marker so Google OAuth never rejects with `disallowed_useragent`.
 * - Injects a `fetch`/`XMLHttpRequest` interceptor capturing the exact `ApiService` `X-Goog-Api-Key`,
 *   `X-Goog-AuthUser`, and `?key=` query parameter while ignoring unrelated telemetry hosts.
 * - Normalizes `antigravity.google` -> `antigravity.google.com` for cookie extraction.
 * - Applies two-phase capture timers (10s loading ceiling + 4.5s post-load grace) so slow VPN loads never dismiss early or stall login.
 * - Surfaces navigation errors with Retry and Reset Cookies actions instead of hanging silently.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun CloudRelaySignInScreen(
    targetRelayUrl: String = SapisidHashGenerator.DEFAULT_ORIGIN,
    onAuthenticated: (CloudRelayCapturedSession) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val lang = LocalAppLanguage.current
    val normalizedUrl = remember(targetRelayUrl) { normalizeRelayStartUrl(targetRelayUrl) }
    val targetHost = remember(normalizedUrl) {
        runCatching { Uri.parse(normalizedUrl).host }.getOrNull()?.takeIf { it.isNotBlank() }
            ?: "antigravity.google.com"
    }

    var currentUrl by remember { mutableStateOf(normalizedUrl) }
    var isLoading by remember { mutableStateOf(true) }
    var loadErrorText by remember { mutableStateOf<String?>(null) }
    val defaultStatusHint = tr(
        "Sign in with your Google account to pair Antigravity Cloud Relay.",
        "登录你的 Google 账号以配对 Antigravity 云中继。",
    )
    var statusHint by remember(defaultStatusHint) { mutableStateOf(defaultStatusHint) }
    var webViewRef by remember { mutableStateOf<WebView?>(null) }

    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    val stateHolder = remember(targetHost) {
        CloudRelayWebCaptureState(
            targetHost = targetHost,
            onStatus = { statusHint = it },
            onAuthenticated = onAuthenticated,
        )
    }

    DisposableEffect(stateHolder) {
        onDispose {
            stateHolder.cancelPendingTimers(mainHandler)
            webViewRef?.stopLoading()
            webViewRef?.destroy()
            webViewRef = null
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .statusBarsPadding()
            .navigationBarsPadding()
            .testTag("cloud-relay-signin-screen"),
    ) {
        // Top Bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            IconButton(
                onClick = {
                    stateHolder.cancelPendingTimers(mainHandler)
                    onCancel()
                },
                modifier = Modifier
                    .defaultMinSize(
                        minWidth = AntigravityDesignTokens.MinTouchTarget,
                        minHeight = AntigravityDesignTokens.MinTouchTarget,
                    )
                    .testTag("btn-relay-signin-cancel"),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Close,
                    contentDescription = tr("Cancel sign in", "取消登录"),
                    tint = colors.inkReading,
                )
            }

            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Lock,
                        contentDescription = null,
                        tint = colors.accentPeriwinkle,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        text = tr("Google Cloud Relay Sign-In", "Google 云中继登录"),
                        style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Text(
                    text = currentUrl,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            IconButton(
                onClick = {
                    loadErrorText = null
                    isLoading = true
                    webViewRef?.reload()
                },
                modifier = Modifier.testTag("btn-relay-signin-reload"),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Refresh,
                    contentDescription = tr("Reload page", "重新加载页面"),
                    tint = colors.inkLabel,
                )
            }

            IconButton(
                onClick = {
                    statusHint = lang.t("Clearing Google cookies...", "正在清除 Google Cookie…")
                    loadErrorText = null
                    CloudRelayCookieBridge.clearGoogleCookies {
                        mainHandler.post {
                            stateHolder.resetForRetry()
                            statusHint = lang.t("Cookies cleared. Sign in again.", "Cookie 已清除，请重新登录。")
                            webViewRef?.loadUrl(normalizedUrl)
                        }
                    }
                },
                modifier = Modifier.testTag("btn-relay-signin-clear-cookies"),
            ) {
                Icon(
                    imageVector = Icons.Rounded.DeleteOutline,
                    contentDescription = tr("Clear Google cookies", "清除 Google Cookie"),
                    tint = colors.inkSecondary,
                )
            }
        }

        if (isLoading) {
            LinearProgressIndicator(
                modifier = Modifier.fillMaxWidth(),
                color = colors.accentPeriwinkle,
                trackColor = colors.surfaceElevated,
            )
        } else {
            HorizontalDivider(color = colors.subtleDivider)
        }

        // Navigation error banner with Retry CTA
        if (!loadErrorText.isNullOrBlank()) {
            AntigravitySurfaceCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                containerColor = colors.surfaceAmberTint,
                borderColor = colors.statusWaiting.copy(alpha = 0.4f),
                contentPadding = PaddingValues(10.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Warning,
                        contentDescription = null,
                        tint = colors.statusWaiting,
                        modifier = Modifier.size(18.dp),
                    )
                    Text(
                        text = loadErrorText.orEmpty(),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkReading,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(
                        onClick = {
                            loadErrorText = null
                            isLoading = true
                            webViewRef?.loadUrl(normalizedUrl)
                        },
                    ) {
                        Text(tr("Retry", "重试"), color = colors.statusWaiting)
                    }
                }
            }
        }

        // Embedded Android WebView
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        ) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { context ->
                    WebView(context).apply {
                        webViewRef = this
                        val cookieManager = CookieManager.getInstance()
                        cookieManager.setAcceptCookie(true)
                        cookieManager.setAcceptThirdPartyCookies(this, true)

                        settings.apply {
                            javaScriptEnabled = true
                            domStorageEnabled = true
                            // Strip `; wv)` token so Google Accounts never blocks embedded login
                            // with `403 disallowed_useragent`.
                            userAgentString = sanitizeGoogleOAuthUserAgent(userAgentString)
                        }

                        addJavascriptInterface(
                            object {
                                @JavascriptInterface
                                fun postSignal(kind: String?, apiKey: String?, authUser: String?) {
                                    mainHandler.post {
                                        val activeUrl = url?.takeIf { it.isNotBlank() } ?: currentUrl
                                        stateHolder.updateLatestUrl(activeUrl)
                                        stateHolder.onJsSignal(
                                            kind = kind.orEmpty(),
                                            apiKey = apiKey.orEmpty(),
                                            authUser = authUser.orEmpty(),
                                            liveHost = runCatching { Uri.parse(activeUrl).host }
                                                .getOrNull()
                                                ?.takeIf { it.isNotBlank() }
                                                ?: targetHost,
                                            webView = this@apply,
                                            handler = mainHandler,
                                        )
                                    }
                                }
                            },
                            ANDROID_JS_BRIDGE_NAME,
                        )

                        webChromeClient = WebChromeClient()
                        webViewClient = object : WebViewClient() {
                            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                                super.onPageStarted(view, url, favicon)
                                if (!url.isNullOrBlank()) {
                                    currentUrl = url
                                    stateHolder.updateLatestUrl(url)
                                }
                                isLoading = true
                                loadErrorText = null
                                view?.evaluateJavascript(ANDROID_API_KEY_CAPTURE_JS, null)
                                val liveHost = runCatching { Uri.parse(url.orEmpty()).host }
                                    .getOrNull()
                                    ?.takeIf { it.isNotBlank() }
                                    ?: targetHost
                                Log.i(CLOUD_RELAY_SIGNIN_LOG_TAG, "WebView onPageStarted host=$liveHost")
                                if (isRelayHostUrl(url)) {
                                    stateHolder.scheduleLoadingSafetyCapture(
                                        liveHost = liveHost,
                                        webView = view,
                                        handler = mainHandler,
                                    )
                                } else {
                                    stateHolder.cancelPendingTimers(mainHandler)
                                }
                            }

                            override fun onPageFinished(view: WebView?, url: String?) {
                                super.onPageFinished(view, url)
                                if (!url.isNullOrBlank()) {
                                    currentUrl = url
                                    stateHolder.updateLatestUrl(url)
                                }
                                isLoading = false
                                view?.evaluateJavascript(ANDROID_API_KEY_CAPTURE_JS, null)
                                val liveHost = runCatching { Uri.parse(url.orEmpty()).host }
                                    .getOrNull()
                                    ?.takeIf { it.isNotBlank() }
                                    ?: targetHost
                                Log.i(CLOUD_RELAY_SIGNIN_LOG_TAG, "WebView onPageFinished host=$liveHost")
                                if (isRelayHostUrl(url)) {
                                    stateHolder.onRelayPageFinished(
                                        liveHost = liveHost,
                                        webView = view,
                                        handler = mainHandler,
                                    )
                                }
                            }

                            override fun onReceivedError(
                                view: WebView?,
                                request: WebResourceRequest?,
                                error: WebResourceError?,
                            ) {
                                super.onReceivedError(view, request, error)
                                if (request?.isForMainFrame == true) {
                                    isLoading = false
                                    loadErrorText = lang.t(
                                        "Failed to load sign-in page: ${error?.description ?: "Network error"}",
                                        "登录页面加载失败：${error?.description ?: "网络错误"}",
                                    )
                                    Log.w(
                                        CLOUD_RELAY_SIGNIN_LOG_TAG,
                                        "WebView onReceivedError code=${error?.errorCode} desc=${error?.description}",
                                    )
                                }
                            }
                        }

                        loadUrl(normalizedUrl)
                    }
                },
            )
        }

        HorizontalDivider(color = colors.subtleDivider)

        // Bottom status + manual "Use Current Session" action
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.surfaceObsidian)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = statusHint,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            Button(
                onClick = {
                    stateHolder.updateLatestUrl(currentUrl)
                    val liveHost = runCatching { Uri.parse(currentUrl).host }
                        .getOrNull()
                        ?.takeIf { it.isNotBlank() }
                        ?: targetHost
                    val captured = stateHolder.attemptManualCapture(
                        liveHost = liveHost,
                        webView = webViewRef,
                        handler = mainHandler,
                    )
                    if (!captured) {
                        statusHint = lang.t(
                            "Complete Google Sign-In first (waiting for SAPISID auth cookies).",
                            "请先完成 Google 登录（正在等待 SAPISID 认证 Cookie）。",
                        )
                    }
                },
                modifier = Modifier
                    .defaultMinSize(minHeight = 40.dp)
                    .testTag("btn-relay-use-session"),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.accentPeriwinkle,
                    contentColor = colors.inkOnPrimaryCta,
                ),
            ) {
                Text(
                    text = tr("Use Session", "使用当前会话"),
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        }
    }
}

/**
 * In-window Material 3 overlay dialog for entering or pasting a Desktop Remote Control QR link
 * (`https://antigravity.google.com/r/<uuid>` or `agpocket://pair?...`). Android users can also scan
 * the QR directly with the system camera because `MainActivity` registers `agpocket://` and
 * `https://antigravity.google.com/r/` deep links.
 */
@Composable
fun RemoteControlLinkDialog(
    initialValue: String = "",
    onSubmitLink: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    val context = androidx.compose.ui.platform.LocalContext.current
    var linkText by rememberSaveable { mutableStateOf(initialValue) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.62f))
            .clickable(onClick = onDismiss)
            .padding(horizontal = 20.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = false, onClick = {})
                .testTag("dialog-remote-control-link"),
            shape = RoundedCornerShape(24.dp),
            color = colors.surfaceCard,
            border = BorderStroke(1.dp, colors.cardBorder),
            tonalElevation = 6.dp,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.QrCodeScanner,
                        contentDescription = null,
                        tint = colors.accentPeriwinkle,
                    )
                    Text(
                        text = tr("Pair via Remote Control Link", "通过远程控制链接配对"),
                        style = MaterialTheme.typography.titleMedium,
                        color = colors.inkReading,
                    )
                }

                Text(
                    text = tr(
                        "Paste the link from Antigravity Desktop → Remote Control (or scan its QR code with your Android Camera app to open AG Pocket directly).",
                        "粘贴来自 Antigravity Desktop → 远程控制 的链接（或使用系统相机扫描二维码直接打开 AG Pocket）。",
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary,
                )

                OutlinedTextField(
                    value = linkText,
                    onValueChange = { linkText = it },
                    label = { Text(tr("Remote Control URL or Pairing URI", "远程控制 URL 或配对链接")) },
                    placeholder = { Text("https://antigravity.google.com/r/...") },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("input-remote-control-link"),
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

                TextButton(
                    onClick = {
                        val mgr = context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
                        val pasted = mgr?.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString()?.trim().orEmpty()
                        if (pasted.isNotEmpty()) {
                            linkText = pasted
                        }
                    },
                    modifier = Modifier.testTag("btn-paste-remote-link"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.ContentPaste,
                        contentDescription = null,
                        tint = colors.accentPeriwinkle,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(tr("Paste from Clipboard", "从剪贴板粘贴"), color = colors.accentPeriwinkle)
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TextButton(onClick = onDismiss) {
                        Text(tr("Cancel", "取消"), color = colors.inkSecondary)
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Button(
                        onClick = { onSubmitLink(linkText.trim()) },
                        enabled = linkText.trim().isNotEmpty(),
                        modifier = Modifier.testTag("btn-submit-remote-link"),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.accentPeriwinkle,
                            contentColor = colors.inkOnPrimaryCta,
                        ),
                    ) {
                        Text(tr("Continue", "继续"))
                    }
                }
            }
        }
    }
}

internal fun sanitizeGoogleOAuthUserAgent(rawUserAgent: String?): String {
    val base = rawUserAgent?.trim().orEmpty()
    if (base.isEmpty()) {
        return "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
    }
    return base
        .replace("; wv)", ")")
        .replace(" wv)", ")")
        .replace(Regex("Version/[0-9.]+\\s*"), "")
}

internal fun normalizeRelayStartUrl(rawUrl: String): String {
    val trimmed = rawUrl.trim()
    if (trimmed.isEmpty()) return SapisidHashGenerator.DEFAULT_ORIGIN
    val parsed = runCatching { Uri.parse(trimmed) }.getOrNull() ?: return SapisidHashGenerator.DEFAULT_ORIGIN
    val host = parsed.host?.trim().orEmpty()
    if (host.isEmpty()) return trimmed
    val canonicalHost = RemoteHostInstance.canonicalRelayHost(host)
    if (!canonicalHost.equals(host, ignoreCase = true)) {
        return trimmed.replaceFirst(host, canonicalHost, ignoreCase = true)
    }
    return trimmed
}

internal fun isRelayHostUrl(rawUrl: String?): Boolean {
    if (rawUrl.isNullOrBlank()) return false
    val host = runCatching { Uri.parse(rawUrl).host?.lowercase().orEmpty() }.getOrDefault("")
    return host == "antigravity.google.com" ||
        host == "antigravity.google" ||
        host.endsWith(".antigravity.google.com") ||
        host.endsWith(".antigravity.google") ||
        host == "127.0.0.1" ||
        host == "localhost"
}

internal fun parseEvaluateJsStringResult(raw: String?): String? {
    val trimmed = raw?.trim().orEmpty()
    if (trimmed.isEmpty() || trimmed.equals("null", ignoreCase = true) || trimmed.equals("undefined", ignoreCase = true)) {
        return null
    }
    val unquoted = if (trimmed.length >= 2 && trimmed.first() == '"' && trimmed.last() == '"') {
        trimmed.substring(1, trimmed.length - 1)
            .replace("\\\"", "\"")
            .replace("\\\\", "\\")
    } else {
        trimmed
    }.trim()
    return unquoted.takeIf { it.length in 16..128 }
}

private class CloudRelayWebCaptureState(
    private val targetHost: String,
    private val onStatus: (String) -> Unit,
    private val onAuthenticated: (CloudRelayCapturedSession) -> Unit,
) {
    private enum class TimerMode {
        NONE,
        LOADING_CEILING,
        POST_LOAD_GRACE,
        API_KEY_VERIFY_GRACE,
    }

    private var didComplete: Boolean = false
    private var didObserveApiServiceSuccess: Boolean = false
    private var verifiedApiKey: String? = null
    private var candidateApiKey: String? = null
    private var capturedAuthUser: String? = null
    private var latestUrl: String? = null
    private var pendingTimerMode: TimerMode = TimerMode.NONE
    private var pendingFallbackRunnable: Runnable? = null
    private var pendingInspectTimeoutRunnable: Runnable? = null

    fun updateLatestUrl(url: String?) {
        val clean = url?.trim()?.takeIf { it.isNotEmpty() } ?: return
        latestUrl = clean
    }

    fun resetForRetry() {
        didComplete = false
        didObserveApiServiceSuccess = false
        verifiedApiKey = null
        candidateApiKey = null
        capturedAuthUser = null
        latestUrl = null
        pendingTimerMode = TimerMode.NONE
    }

    fun cancelPendingTimers(handler: Handler) {
        pendingFallbackRunnable?.let { handler.removeCallbacks(it) }
        pendingFallbackRunnable = null
        pendingInspectTimeoutRunnable?.let { handler.removeCallbacks(it) }
        pendingInspectTimeoutRunnable = null
        pendingTimerMode = TimerMode.NONE
    }

    fun onJsSignal(
        kind: String,
        apiKey: String,
        authUser: String,
        liveHost: String,
        webView: WebView?,
        handler: Handler,
    ) {
        if (didComplete) return
        val cleanKey = apiKey.trim().takeIf { it.length in 16..128 }
        val cleanUser = authUser.trim().takeIf { it.isNotEmpty() }
        if (cleanUser != null) {
            capturedAuthUser = cleanUser
        }
        Log.i(
            CLOUD_RELAY_SIGNIN_LOG_TAG,
            "JS signal kind=$kind hasKey=${cleanKey != null} authUser=${cleanUser ?: "auto"}",
        )
        when (kind) {
            "apiServiceVerified" -> {
                didObserveApiServiceSuccess = true
                if (cleanKey != null) {
                    verifiedApiKey = cleanKey
                    candidateApiKey = cleanKey
                }
                // Brief 150ms flush window so Android CookieManager commits any Set-Cookie headers
                // before extracting cookies and dismissing the WebView.
                cancelPendingTimers(handler)
                onStatus("Google session verified — pairing host...")
                val flushRunnable = Runnable {
                    tryAutoCaptureIfSignedIn(
                        liveHost = liveHost,
                        webView = webView,
                        handler = handler,
                        allowImmediateWithoutKey = true,
                        reason = "apiServiceVerified",
                    )
                }
                pendingFallbackRunnable = flushRunnable
                handler.postDelayed(flushRunnable, COOKIE_FLUSH_DELAY_MS)
            }

            "apiServiceKey" -> {
                if (cleanKey != null) {
                    verifiedApiKey = cleanKey
                    candidateApiKey = cleanKey
                }
                if (didObserveApiServiceSuccess) {
                    tryAutoCaptureIfSignedIn(
                        liveHost = liveHost,
                        webView = webView,
                        handler = handler,
                        allowImmediateWithoutKey = true,
                        reason = "apiServiceKeyAfterVerified",
                    )
                } else {
                    onStatus("Google session detected — verifying Cloud Relay key...")
                    scheduleCaptureTimer(
                        mode = TimerMode.API_KEY_VERIFY_GRACE,
                        delayMs = API_KEY_VERIFY_GRACE_DELAY_MS,
                        liveHost = liveHost,
                        webView = webView,
                        handler = handler,
                        reason = "apiKeyVerifyGrace",
                    )
                }
            }

            else -> {
                if (cleanKey != null && verifiedApiKey == null) {
                    candidateApiKey = cleanKey
                }
            }
        }
    }

    /**
     * Phase 1 timer: while the relay page is still loading over a slow VPN, allow up to 10s
     * before falling back so we never dismiss the WebView prematurely before Google sets cookies
     * or finishes the initial `ApiService` request.
     */
    fun scheduleLoadingSafetyCapture(
        liveHost: String,
        webView: WebView?,
        handler: Handler,
    ) {
        if (didComplete || pendingTimerMode != TimerMode.NONE) return
        scheduleCaptureTimer(
            mode = TimerMode.LOADING_CEILING,
            delayMs = LOADING_SAFETY_CAPTURE_DELAY_MS,
            liveHost = liveHost,
            webView = webView,
            handler = handler,
            reason = "loadingCeiling",
        )
    }

    /**
     * Phase 2 timer: once the relay page finishes loading, complete immediately if `ApiService`
     * already succeeded, wait a short 1.2s grace if we already saw the key header, or give the
     * SPA 4.5s to fire its initial `ListInstances` call before DOM inspection fallback.
     */
    fun onRelayPageFinished(
        liveHost: String,
        webView: WebView?,
        handler: Handler,
    ) {
        if (didComplete) return
        if (didObserveApiServiceSuccess) {
            tryAutoCaptureIfSignedIn(
                liveHost = liveHost,
                webView = webView,
                handler = handler,
                allowImmediateWithoutKey = true,
                reason = "pageFinishedVerified",
            )
            return
        }
        val hasCookies = CloudRelayCookieBridge.extractSessionCookieHeaderForHost(liveHost) != null ||
            CloudRelayCookieBridge.extractSessionCookieHeaderForHost(targetHost) != null
        if (hasCookies) {
            onStatus("Google session detected — capturing Cloud Relay API key...")
        }
        if (verifiedApiKey != null) {
            scheduleCaptureTimer(
                mode = TimerMode.API_KEY_VERIFY_GRACE,
                delayMs = API_KEY_VERIFY_GRACE_DELAY_MS,
                liveHost = liveHost,
                webView = webView,
                handler = handler,
                reason = "pageFinishedKeyGrace",
            )
        } else if (pendingTimerMode != TimerMode.POST_LOAD_GRACE) {
            scheduleCaptureTimer(
                mode = TimerMode.POST_LOAD_GRACE,
                delayMs = POST_LOAD_FALLBACK_CAPTURE_DELAY_MS,
                liveHost = liveHost,
                webView = webView,
                handler = handler,
                reason = "postLoadGrace",
            )
        }
    }

    private fun scheduleCaptureTimer(
        mode: TimerMode,
        delayMs: Long,
        liveHost: String,
        webView: WebView?,
        handler: Handler,
        reason: String,
    ) {
        if (didComplete) return
        pendingFallbackRunnable?.let { handler.removeCallbacks(it) }
        pendingTimerMode = mode
        val runnable = Runnable {
            pendingTimerMode = TimerMode.NONE
            tryAutoCaptureIfSignedIn(
                liveHost = liveHost,
                webView = webView,
                handler = handler,
                allowImmediateWithoutKey = true,
                reason = reason,
            )
        }
        pendingFallbackRunnable = runnable
        handler.postDelayed(runnable, delayMs)
    }

    fun tryAutoCaptureIfSignedIn(
        liveHost: String,
        webView: WebView?,
        handler: Handler,
        allowImmediateWithoutKey: Boolean,
        reason: String = "auto",
    ) {
        if (didComplete) return
        val cookieHeader = CloudRelayCookieBridge.extractSessionCookieHeaderForHost(liveHost)
            ?: CloudRelayCookieBridge.extractSessionCookieHeaderForHost(targetHost)
            ?: return

        val verified = verifiedApiKey
        if (verified != null && (didObserveApiServiceSuccess || allowImmediateWithoutKey)) {
            completeCapture(cookieHeader, verified, "verified", reason, handler)
        } else if (allowImmediateWithoutKey) {
            completeCaptureWithDomInspection(cookieHeader, webView, reason, handler)
        } else {
            onStatus("Google session detected — capturing Cloud Relay API key...")
            scheduleCaptureTimer(
                mode = TimerMode.POST_LOAD_GRACE,
                delayMs = POST_LOAD_FALLBACK_CAPTURE_DELAY_MS,
                liveHost = liveHost,
                webView = webView,
                handler = handler,
                reason = "fallbackAfterCookie",
            )
        }
    }

    fun attemptManualCapture(liveHost: String, webView: WebView?, handler: Handler): Boolean {
        if (didComplete) return true
        val cookieHeader = CloudRelayCookieBridge.extractSessionCookieHeaderForHost(liveHost)
            ?: CloudRelayCookieBridge.extractSessionCookieHeaderForHost(targetHost)
            ?: return false
        val verified = verifiedApiKey
        if (verified != null) {
            completeCapture(cookieHeader, verified, "verified", "manual", handler)
        } else {
            completeCaptureWithDomInspection(cookieHeader, webView, "manual", handler)
        }
        return true
    }

    private fun completeCaptureWithDomInspection(
        cookieHeader: String,
        webView: WebView?,
        reason: String,
        handler: Handler,
    ) {
        if (didComplete) return
        if (webView == null) {
            val fallbackKey = verifiedApiKey ?: candidateApiKey
            val keySource = when {
                verifiedApiKey != null -> "verified"
                candidateApiKey != null -> "candidate"
                else -> "none"
            }
            completeCapture(cookieHeader, fallbackKey, keySource, reason, handler)
            return
        }
        pendingInspectTimeoutRunnable?.let { handler.removeCallbacks(it) }
        val timeoutRunnable = Runnable {
            val fallbackKey = verifiedApiKey ?: candidateApiKey
            val keySource = when {
                verifiedApiKey != null -> "verified"
                candidateApiKey != null -> "candidate"
                else -> "none"
            }
            completeCapture(cookieHeader, fallbackKey, keySource, "$reason+inspectTimeout", handler)
        }
        pendingInspectTimeoutRunnable = timeoutRunnable
        handler.postDelayed(timeoutRunnable, DOM_INSPECT_TIMEOUT_MS)
        runCatching {
            webView.evaluateJavascript(ANDROID_API_KEY_INSPECT_JS) { rawResult ->
                handler.post {
                    val inspectedKey = parseEvaluateJsStringResult(rawResult)
                    if (inspectedKey != null && verifiedApiKey == null) {
                        candidateApiKey = inspectedKey
                    }
                    val resolvedKey = verifiedApiKey ?: inspectedKey ?: candidateApiKey
                    val keySource = when {
                        verifiedApiKey != null -> "verified"
                        inspectedKey != null -> "dom"
                        candidateApiKey != null -> "candidate"
                        else -> "none"
                    }
                    completeCapture(
                        cookieHeader = cookieHeader,
                        apiKey = resolvedKey,
                        keySource = keySource,
                        reason = reason,
                        handler = handler,
                    )
                }
            }
        }.onFailure {
            val fallbackKey = verifiedApiKey ?: candidateApiKey
            val keySource = when {
                verifiedApiKey != null -> "verified"
                candidateApiKey != null -> "candidate"
                else -> "none"
            }
            completeCapture(cookieHeader, fallbackKey, keySource, "$reason+inspectErr", handler)
        }
    }

    private fun completeCapture(
        cookieHeader: String,
        apiKey: String?,
        keySource: String,
        reason: String,
        handler: Handler,
    ) {
        if (didComplete) return
        didComplete = true
        cancelPendingTimers(handler)
        val ckSummary = SapisidHashGenerator.summarizeCookieNames(cookieHeader)
        val keyDesc = apiKey?.let { "$keySource(len=${it.length})" } ?: "none"
        Log.i(
            CLOUD_RELAY_SIGNIN_LOG_TAG,
            "Capture complete reason=$reason authUser=${capturedAuthUser ?: "auto"} key=$keyDesc ck=$ckSummary",
        )
        onStatus("Google session verified — pairing host...")
        onAuthenticated(
            CloudRelayCapturedSession(
                cookieHeader = cookieHeader,
                relayApiKey = apiKey,
                authUser = capturedAuthUser,
                finalUrl = latestUrl,
            ),
        )
    }

    companion object {
        private const val LOADING_SAFETY_CAPTURE_DELAY_MS = 10_000L
        private const val POST_LOAD_FALLBACK_CAPTURE_DELAY_MS = 4_500L
        private const val API_KEY_VERIFY_GRACE_DELAY_MS = 1_200L
        private const val COOKIE_FLUSH_DELAY_MS = 150L
        private const val DOM_INSPECT_TIMEOUT_MS = 600L
    }
}

private const val CLOUD_RELAY_SIGNIN_LOG_TAG = "CloudRelaySignIn"
private const val ANDROID_JS_BRIDGE_NAME = "__agAndroidBridge"

internal const val ANDROID_API_KEY_INSPECT_JS = """
(function() {
  try {
    if (typeof window.__agApiServiceKey === 'string' && window.__agApiServiceKey.length >= 16) {
      return window.__agApiServiceKey;
    }
    var meta = document.querySelector('meta[name="antigravity-relay-api-key"]');
    if (meta && meta.getAttribute('content')) {
      return meta.getAttribute('content');
    }
    var keyPattern = new RegExp("^AI" + "za[0-9A-Za-z_-]{35}${'$'}");
    var wiz = window.WIZ_global_data;
    if (wiz && typeof wiz === 'object') {
      var priorityKeys = ['WIu0Nc', 'QrtxK', 'P10xbc', 'apiKey', 'api_key', 'webApiKey'];
      for (var i = 0; i < priorityKeys.length; i++) {
        var val = wiz[priorityKeys[i]];
        if (typeof val === 'string' && keyPattern.test(val.trim())) {
          return val.trim();
        }
      }
      var allKeys = Object.keys(wiz);
      for (var j = 0; j < allKeys.length; j++) {
        var candidate = wiz[allKeys[j]];
        if (typeof candidate === 'string' && keyPattern.test(candidate.trim())) {
          return candidate.trim();
        }
      }
    }
    if (typeof window.__agCapturedRelayApiKey === 'string' && window.__agCapturedRelayApiKey.length >= 16) {
      return window.__agCapturedRelayApiKey;
    }
    var inlinePattern = new RegExp("(?:x-goog-api-key|WIu0Nc|QrtxK|P10xbc|apiKey)[\"']?\\s*[:=]\\s*[\"'](AI" + "za[0-9A-Za-z_-]{35})[\"']", "i");
    var scripts = document.scripts || [];
    for (var s = 0; s < scripts.length && s < 24; s++) {
      var text = scripts[s] && scripts[s].textContent ? scripts[s].textContent : '';
      if (text.length > 0 && text.length < 250000) {
        var m = text.match(inlinePattern);
        if (m && m[1]) {
          return m[1];
        }
      }
    }
  } catch (_) {}
  return '';
})();
"""

private const val ANDROID_API_KEY_CAPTURE_JS = """
(function() {
  if (window.__agRelayApiKeyHookInstalled) { return; }
  window.__agRelayApiKeyHookInstalled = true;
  function isRelayHost() {
    var host = (window.location && window.location.hostname ? window.location.hostname : '').toLowerCase();
    return host === 'antigravity.google.com'
      || host === 'antigravity.google'
      || host.endsWith('.antigravity.google.com')
      || host.endsWith('.antigravity.google')
      || host === '127.0.0.1'
      || host === 'localhost';
  }
  function isApiServiceUrl(rawUrl) {
    if (!rawUrl || typeof rawUrl !== 'string') { return false; }
    var lower = rawUrl.toLowerCase();
    return lower.indexOf('/${'$'}rpc/') !== -1
      || lower.indexOf('/%24rpc/') !== -1
      || lower.indexOf('devtools_jetski_boq_api_proto') !== -1
      || lower.indexOf('apiservice/listinstances') !== -1
      || lower.indexOf('apiservice/proxycommand') !== -1;
  }
  function extractQueryKey(rawUrl) {
    if (!rawUrl || typeof rawUrl !== 'string') { return ''; }
    var m = rawUrl.match(/[?&]key=([A-Za-z0-9_.-]{16,128})/i);
    return m && m[1] ? m[1] : '';
  }
  function isUnrelatedTelemetryUrl(rawUrl) {
    if (!rawUrl || typeof rawUrl !== 'string') { return false; }
    var lower = rawUrl.toLowerCase();
    return lower.indexOf('play.google.com') !== -1
      || lower.indexOf('ogs.google.com') !== -1
      || lower.indexOf('ogads-pa') !== -1
      || lower.indexOf('waa-pa') !== -1
      || lower.indexOf('people-pa') !== -1
      || lower.indexOf('accounts.google.com') !== -1;
  }
  function postSignal(kind, apiKey, authUser) {
    if (!isRelayHost()) { return; }
    var cleanKey = (typeof apiKey === 'string') ? apiKey.trim() : '';
    var cleanUser = (typeof authUser === 'string') ? authUser.trim() : '';
    if (kind === 'apiServiceKey' || kind === 'apiServiceVerified') {
      if (cleanKey.length >= 16 && cleanKey.length <= 128) {
        window.__agApiServiceKey = cleanKey;
      }
      if (cleanUser.length > 0) {
        window.__agApiServiceAuthUser = cleanUser;
      }
    } else if (cleanKey.length >= 16 && cleanKey.length <= 128) {
      window.__agCapturedRelayApiKey = cleanKey;
    }
    try {
      if (window.__agAndroidBridge && typeof window.__agAndroidBridge.postSignal === 'function') {
        window.__agAndroidBridge.postSignal(kind, cleanKey, cleanUser);
      }
    } catch (_) {}
  }
  function extractHeader(headers, targetLower) {
    if (!headers) { return ''; }
    try {
      if (typeof headers.get === 'function') {
        var direct = headers.get(targetLower);
        if (direct) { return String(direct); }
      }
      if (Array.isArray(headers)) {
        for (var i = 0; i < headers.length; i++) {
          var pair = headers[i];
          if (Array.isArray(pair) && pair.length >= 2 && String(pair[0]).toLowerCase() === targetLower) {
            return String(pair[1]);
          }
        }
      } else if (typeof headers === 'object') {
        var keys = Object.keys(headers);
        for (var j = 0; j < keys.length; j++) {
          if (keys[j].toLowerCase() === targetLower) {
            return String(headers[keys[j]]);
          }
        }
      }
    } catch (_) {}
    return '';
  }
  if (typeof window.XMLHttpRequest === 'function') {
    var origOpen = XMLHttpRequest.prototype.open;
    var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
    var origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__agReqUrl = (typeof url === 'string') ? url : '';
      this.__agReqHeaders = {};
      return origOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
      try {
        if (typeof name === 'string' && typeof value === 'string') {
          var lower = name.toLowerCase();
          if (this.__agReqHeaders) { this.__agReqHeaders[lower] = value; }
          var reqUrl = this.__agReqUrl || '';
          if (lower === 'x-goog-api-key' && isApiServiceUrl(reqUrl)) {
            postSignal('apiServiceKey', value, this.__agReqHeaders['x-goog-authuser'] || '');
          } else if (lower === 'x-goog-api-key' && !isUnrelatedTelemetryUrl(reqUrl)) {
            postSignal('candidateKey', value, this.__agReqHeaders['x-goog-authuser'] || '');
          }
        }
      } catch (_) {}
      return origSetHeader.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function() {
      var xhr = this;
      try {
        var reqUrl = xhr.__agReqUrl || '';
        if (isApiServiceUrl(reqUrl)) {
          var hdrs = xhr.__agReqHeaders || {};
          var xhrKey = hdrs['x-goog-api-key'] || extractQueryKey(reqUrl);
          if (xhrKey) {
            postSignal('apiServiceKey', xhrKey, hdrs['x-goog-authuser'] || '');
          }
          xhr.addEventListener('load', function() {
            if (xhr.status >= 200 && xhr.status < 300) {
              var h = xhr.__agReqHeaders || {};
              var verifiedKey = h['x-goog-api-key'] || extractQueryKey(reqUrl) || window.__agApiServiceKey || '';
              postSignal('apiServiceVerified', verifiedKey, h['x-goog-authuser'] || window.__agApiServiceAuthUser || '');
            }
          });
        }
      } catch (_) {}
      return origSend.apply(this, arguments);
    };
  }
  if (typeof window.fetch === 'function') {
    var origFetch = window.fetch;
    window.fetch = function(input, init) {
      var reqUrl = '';
      var apiKey = '';
      var authUser = '';
      try {
        reqUrl = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
        if (init && init.headers) {
          apiKey = extractHeader(init.headers, 'x-goog-api-key');
          authUser = extractHeader(init.headers, 'x-goog-authuser');
        }
        if (!apiKey && input && input.headers) {
          apiKey = extractHeader(input.headers, 'x-goog-api-key');
        }
        if (!authUser && input && input.headers) {
          authUser = extractHeader(input.headers, 'x-goog-authuser');
        }
        if (!apiKey) {
          apiKey = extractQueryKey(reqUrl);
        }
        if (apiKey && isApiServiceUrl(reqUrl)) {
          postSignal('apiServiceKey', apiKey, authUser);
        } else if (apiKey && !isUnrelatedTelemetryUrl(reqUrl)) {
          postSignal('candidateKey', apiKey, authUser);
        }
      } catch (_) {}
      var promise = origFetch.apply(this, arguments);
      if (isApiServiceUrl(reqUrl) && promise && typeof promise.then === 'function') {
        promise.then(function(resp) {
          if (resp && resp.ok) {
            postSignal('apiServiceVerified', apiKey || window.__agApiServiceKey || '', authUser || window.__agApiServiceAuthUser || '');
          }
        }).catch(function() {});
      }
      return promise;
    };
  }
})();
"""
