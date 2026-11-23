package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

@Serializable(with = PrimaryTabSerializer::class)
public enum class PrimaryTab(public val displayTitle: String) {
    AGENTS("Agents"),
    AUTOMATIONS("Automations"),
    SETTINGS("Settings"),
}

public object PrimaryTabSerializer : ResilientEnumSerializer<PrimaryTab>(
    serialName = "dev.antigravity.shared.model.PrimaryTab",
    entriesProvider = { PrimaryTab.entries },
    fallbackProvider = { PrimaryTab.AGENTS },
)

@Serializable(with = EsddVerifySceneCaseSerializer::class)
public enum class EsddVerifySceneCase(public val rawValue: String) {
    AGENTS_HOME("UE01_AGENTS_HOME"),
    DISPLAY_OPTIONS("UE02_DISPLAY_OPTIONS"),
    CONTEXT_MENU_PIN("UE03_CONTEXT_MENU_PIN"),
    PROJECT_DETAIL("UE04_PROJECT_DETAIL"),
    CREATE_PROJECT("UE05_CREATE_PROJECT"),
    AUTOMATIONS("UE06_AUTOMATIONS"),
    CHAT_AND_COMPOSER("UE07_CHAT_AND_COMPOSER"),
    ADD_CONTEXT("UE08_ADD_CONTEXT"),
    MODEL_AND_MODE("UE09_MODEL_AND_MODE"),
    STRUCTURED_QUESTION("UE10_STRUCTURED_QUESTION"),
    PLAN_REVIEW("UE11_PLAN_REVIEW"),
    TURN_DIFF_REVIEW("UE12_TURN_DIFF_REVIEW"),
    LIVE_ACTIVITY_SPEC("UE13_LIVE_ACTIVITY_SPEC"),
}

public object EsddVerifySceneCaseSerializer : ResilientEnumSerializer<EsddVerifySceneCase>(
    serialName = "dev.antigravity.shared.model.EsddVerifySceneCase",
    entriesProvider = { EsddVerifySceneCase.entries },
    fallbackProvider = { EsddVerifySceneCase.AGENTS_HOME },
    extraMatcher = { raw -> EsddVerifySceneCase.entries.firstOrNull { it.rawValue.equals(raw, ignoreCase = true) } },
)

@Serializable(with = AgentsQuickFilterSerializer::class)
public enum class AgentsQuickFilter(public val displayTitle: String) {
    ALL("All"),
    RUNNING("Running"),
    NEEDS_YOU("Needs you"),
    UNREAD("Unread"),
}

public object AgentsQuickFilterSerializer : ResilientEnumSerializer<AgentsQuickFilter>(
    serialName = "dev.antigravity.shared.model.AgentsQuickFilter",
    entriesProvider = { AgentsQuickFilter.entries },
    fallbackProvider = { AgentsQuickFilter.ALL },
)

@Serializable(with = DisplayGroupBySerializer::class)
public enum class DisplayGroupBy(public val displayTitle: String) {
    PROJECT("Project"),
    HOST("Host"),
    NONE("None"),
}

public object DisplayGroupBySerializer : ResilientEnumSerializer<DisplayGroupBy>(
    serialName = "dev.antigravity.shared.model.DisplayGroupBy",
    entriesProvider = { DisplayGroupBy.entries },
    fallbackProvider = { DisplayGroupBy.PROJECT },
)

@Serializable(with = ConversationSortFieldSerializer::class)
public enum class ConversationSortField(public val displayTitle: String) {
    LAST_UPDATED("Last Updated"),
    DATE_CREATED("Date Created"),
    TITLE("Title"),
}

public object ConversationSortFieldSerializer : ResilientEnumSerializer<ConversationSortField>(
    serialName = "dev.antigravity.shared.model.ConversationSortField",
    entriesProvider = { ConversationSortField.entries },
    fallbackProvider = { ConversationSortField.LAST_UPDATED },
)

@Serializable
public data class AgentDisplayOptions(
    public val groupBy: DisplayGroupBy = DisplayGroupBy.PROJECT,
    public val sortBy: ConversationSortField = ConversationSortField.LAST_UPDATED,
    public val newestFirst: Boolean = true,
    public val sortProjectsOrder: String = "Custom Order",
    public val filterScopeLabel: String = "All conversations",
    public val densityLabel: String = "Comfortable · Previews",
    public val autoPinOnMessage: Boolean = false,
    public val archivedOnly: Boolean = false,
)

@Serializable(with = ProjectRuntimeTargetSerializer::class)
public enum class ProjectRuntimeTarget(public val displayTitle: String) {
    MAC_BOOK_PRO("MacBook Pro"),
    CLOUD("Cloud");

    public val descriptionText: String
        get() = when (this) {
            MAC_BOOK_PRO -> "Runs locally on your paired workstation with direct filesystem access."
            CLOUD -> "Runs in its own cloud VM and keeps working while your computer sleeps."
        }
}

public object ProjectRuntimeTargetSerializer : ResilientEnumSerializer<ProjectRuntimeTarget>(
    serialName = "dev.antigravity.shared.model.ProjectRuntimeTarget",
    entriesProvider = { ProjectRuntimeTarget.entries },
    fallbackProvider = { ProjectRuntimeTarget.CLOUD },
)

@Serializable(with = ProjectSourceKindSerializer::class)
public enum class ProjectSourceKind(public val displayTitle: String) {
    GITHUB_REPO("GitHub repository"),
    DRIVE_FOLDER("Drive folder"),
}

public object ProjectSourceKindSerializer : ResilientEnumSerializer<ProjectSourceKind>(
    serialName = "dev.antigravity.shared.model.ProjectSourceKind",
    entriesProvider = { ProjectSourceKind.entries },
    fallbackProvider = { ProjectSourceKind.GITHUB_REPO },
)

@Serializable(with = ProjectDetailTabSerializer::class)
public enum class ProjectDetailTab(public val displayTitle: String) {
    ACTIVE("Active"),
    ARCHIVED("Archived"),
    AUTOMATIONS("Automations"),
}

public object ProjectDetailTabSerializer : ResilientEnumSerializer<ProjectDetailTab>(
    serialName = "dev.antigravity.shared.model.ProjectDetailTab",
    entriesProvider = { ProjectDetailTab.entries },
    fallbackProvider = { ProjectDetailTab.ACTIVE },
)

@Serializable
public data class GitHubRepoItem(
    public val id: String,
    public val fullName: String,
    public val visibilityLabel: String,
    public val defaultBranch: String = "main",
)

@Serializable
public data class NewProjectDraft(
    public val runsOn: ProjectRuntimeTarget = ProjectRuntimeTarget.CLOUD,
    public val source: ProjectSourceKind = ProjectSourceKind.GITHUB_REPO,
    public val repoSearchQuery: String = "",
    public val selectedRepo: GitHubRepoItem? = null,
    public val branchWorktree: String = "main · New worktree",
    public val projectName: String = "ledger-svc-cloud",
    public val driveResourceLinks: List<String> = emptyList(),
    public val uploadedFilePaths: List<String> = emptyList(),
    public val envSetupScript: String = "",
)

/**
 * Pure Kotlin Multiplatform detector & URI normalizer for Antigravity Cloud VM (`Jetski Remote Agents`),
 * GitHub Cloud Projects (`cloud://`, `vscode-vfs://`), and Remote-SSH / Tunnel / Devbox workspaces.
 */
public object AntigravityCloudDetector {
    public val cloudUriPrefixes: List<String> = listOf(
        "cloud://",
        "https://github.com/",
        "http://github.com/",
        "vscode-remote://",
        "vscode-vfs://",
        "ssh://",
        "remote://",
        "jetski://",
        "antigravity-cloud://",
        "antigravity-remote://",
        "devbox://",
        "codespace://",
    )

    public const val NO_PROJECT_DISPLAY_NAME: String = "No Project"

    public val genericContainerRoots: Set<String> = setOf(
        "/home/antigravity",
        "/workspace",
        "/workspaces",
        "/root",
    )

    public fun isNoProjectSlug(rawSlug: String): Boolean {
        var cleaned = rawSlug.trim()
        if (cleaned.lowercase().startsWith("cloud:")) {
            cleaned = cleaned.drop("cloud:".length).trim()
        }
        val lower = cleaned.lowercase()
        return lower.isEmpty() ||
            lower == "no project" ||
            lower == "no-project" ||
            lower == "noproject" ||
            lower == "unassigned" ||
            lower == "workspace" ||
            lower == "antigravity" ||
            lower == "antigravity-cloud"
    }

    public fun isGenericContainerUri(rawUri: String): Boolean {
        val trimmed = rawUri.trim()
        if (trimmed.isEmpty()) return true
        val decoded = percentDecodeUtf8(trimmed).trim('/')
        val lower = decoded.lowercase()
        if (lower == "cloud://workspace" ||
            lower == "cloud://antigravity" ||
            lower == "cloud://antigravity-cloud" ||
            lower == "cloud://no-project" ||
            lower == "cloud://no project" ||
            lower == "file:///users/wl/code/workspace"
        ) {
            return true
        }
        if (lower.startsWith("file://")) {
            val tail = decoded.drop("file://".length).trim('/')
            val fsPath = if (tail.isEmpty()) "/" else "/$tail"
            return genericContainerRoots.contains(fsPath.lowercase()) || genericContainerRoots.contains(fsPath)
        }
        if (decoded.startsWith("/")) {
            val fsPath = "/${decoded.trim('/')}"
            return genericContainerRoots.contains(fsPath)
        }
        return false
    }

    public fun isPlaygroundScratchUri(rawUri: String): Boolean {
        val decoded = percentDecodeUtf8(rawUri).trim().lowercase()
        return decoded.contains("/.gemini/antigravity/playground/") ||
            decoded.endsWith("/.gemini/antigravity/playground") ||
            decoded.contains("/.gemini/antigravity/scratch/") ||
            decoded.endsWith("/.gemini/antigravity/scratch") ||
            decoded.contains("/.antigravity/playground/") ||
            decoded.endsWith("/.antigravity/playground") ||
            decoded.contains("/.gemini/jetski/playground/") ||
            decoded.endsWith("/.gemini/jetski/playground")
    }

    public fun isCloudWorkspaceUri(
        rawUri: String,
        cascadeId: String = "",
        sourceHint: String = "",
    ): Boolean {
        val cid = cascadeId.trim().lowercase()
        if (cid.startsWith("v1/") || cid.contains("jetski_remote_agents") || cid.contains("remote_agent")) {
            return true
        }
        val src = sourceHint.trim().lowercase()
        if (src.contains("cloud") || src.contains("remote") || src.contains("jetski") || src.contains("github")) {
            return true
        }
        val decoded = percentDecodeUtf8(rawUri.trim())
        val lower = decoded.lowercase()
        if (cloudUriPrefixes.any { lower.startsWith(it) }) {
            return true
        }
        if (decoded == "file:///home/antigravity" || decoded.startsWith("file:///home/antigravity/")) {
            return true
        }
        return false
    }

    public fun normalizeWorkspaceUri(rawUri: String, isCloud: Boolean): String {
        val trimmed = rawUri.trim()
        if (trimmed.isEmpty() || isGenericContainerUri(trimmed)) return ""
        val decoded = percentDecodeUtf8(trimmed)
        val lower = decoded.lowercase()

        if (lower.startsWith("https://github.com/") || lower.startsWith("http://github.com/")) {
            val prefixLen = if (lower.startsWith("https://")) "https://github.com/".length else "http://github.com/".length
            var tail = decoded.drop(prefixLen).trim('/')
            if (tail.endsWith(".git")) tail = tail.dropLast(4)
            val parts = tail.split('/').filter { it.isNotEmpty() }
            if (parts.size >= 2) return "cloud://${parts[0]}/${parts[1]}"
            return if (tail.isEmpty()) "" else "cloud://$tail"
        }

        if (lower.startsWith("vscode-vfs://")) {
            val afterScheme = decoded.drop("vscode-vfs://".length)
            val slashIdx = afterScheme.indexOf('/')
            if (slashIdx >= 0) {
                val parts = afterScheme.substring(slashIdx + 1).split('/').filter { it.isNotEmpty() }
                if (parts.size >= 2) return "cloud://${parts[0]}/${parts[1]}"
            }
            return trimmed
        }

        if (decoded == "file:///home/antigravity" || decoded.startsWith("file:///home/antigravity/")) {
            val suffix = decoded.drop("file:///home/antigravity".length).trim('/')
            val parts = suffix.split('/').filter { it.isNotEmpty() }
            if (parts.size >= 2) return "cloud://${parts[0]}/${parts[1]}"
            val first = parts.firstOrNull()
            return if (!first.isNullOrEmpty()) "cloud://$first" else ""
        }

        if (isCloud && decoded.startsWith("file://")) {
            val fsPath = decoded.drop("file://".length).trim('/')
            val slug = fsPath.split('/').lastOrNull { it.isNotEmpty() }
            return if (!slug.isNullOrEmpty() && !isNoProjectSlug(slug)) "cloud://$slug" else ""
        }

        return trimmed
    }

    public fun extractCloudLocationLabel(workspaceUri: String): String? {
        val decoded = percentDecodeUtf8(workspaceUri).trim()
        val lower = decoded.lowercase()
        if (lower.startsWith("cloud://")) {
            val tail = decoded.drop("cloud://".length).trim('/')
            return if (tail.isNotEmpty() && !isNoProjectSlug(tail)) tail else null
        }
        if (lower.startsWith("https://github.com/") || lower.startsWith("http://github.com/")) {
            return extractCloudLocationLabel(normalizeWorkspaceUri(decoded, isCloud = true))
        }
        if (lower.startsWith("vscode-remote://")) {
            val authority = decoded.drop("vscode-remote://".length).substringBefore('/')
            return authority.takeIf { it.isNotEmpty() }
        }
        return null
    }
}

@Serializable
public data class ProjectWorkspace(
    public val id: String,
    public val name: String,
    public val pathDisplay: String,
    public val workspaceUri: String,
    public val runtime: ProjectRuntimeTarget = ProjectRuntimeTarget.MAC_BOOK_PRO,
    public val hostName: String = "MacBook Pro",
    public val activeBranch: String = "main",
    public val worktrees: List<String> = listOf("main"),
    public val isExpandedInHome: Boolean = true,
    public val rulesAndSkillsCount: Int = 4,
    public val cloudProjectId: String? = null,
    public val originInstanceUuid: String? = null,
) {
    public val isNoProject: Boolean
        get() = AntigravityCloudDetector.isNoProjectSlug(name) || AntigravityCloudDetector.isNoProjectSlug(id)

    public fun homeSubtitle(isHostOnline: Boolean = true): String {
        if (isNoProject) {
            return when (runtime) {
                ProjectRuntimeTarget.MAC_BOOK_PRO -> "${if (isHostOnline) "Local" else "Offline"} · $hostName"
                ProjectRuntimeTarget.CLOUD -> "Antigravity Cloud"
            }
        }
        val branchSuffix = activeBranch.trim().let { if (it.isEmpty()) "" else " · $it" }
        return when (runtime) {
            ProjectRuntimeTarget.MAC_BOOK_PRO -> "${if (isHostOnline) "Local" else "Offline"} · $hostName$branchSuffix"
            ProjectRuntimeTarget.CLOUD -> {
                val cloudLabel = AntigravityCloudDetector.extractCloudLocationLabel(workspaceUri)
                if (cloudLabel != null && !cloudLabel.equals(name, ignoreCase = true)) {
                    "Cloud · $cloudLabel$branchSuffix"
                } else {
                    "Cloud$branchSuffix"
                }
            }
        }
    }
}

@Serializable(with = RemoteConnectionChannelSerializer::class)
public enum class RemoteConnectionChannel(public val displayName: String) {
    CLOUD_RELAY("Google Cloud Relay"),
    DIRECT_HOST("Direct LAN / Tailscale"),
}

public object RemoteConnectionChannelSerializer : ResilientEnumSerializer<RemoteConnectionChannel>(
    serialName = "dev.antigravity.shared.model.RemoteConnectionChannel",
    entriesProvider = { RemoteConnectionChannel.entries },
    fallbackProvider = { RemoteConnectionChannel.CLOUD_RELAY },
)

@Serializable
public data class RemoteHostInstance(
    public val instanceId: String,
    public val hostname: String,
    public val version: String = "v2.32.0",
    public val channel: RemoteConnectionChannel = RemoteConnectionChannel.CLOUD_RELAY,
    public val endpointUrl: String,
    public val isOnline: Boolean = true,
    public val latencyMs: Int = 18,
    public val certificateFingerprintSha256: String = "SHA256:9F:86:D0:81:88:4C:7D:65:9A:2F:EA:A0:C5:5A:D0:15",
) {
    public val id: String get() = instanceId

    public data class ParsedRemoteControlTarget(
        public val instanceId: String,
        public val conversationId: String? = null,
        public val authUser: String? = null,
        public val relayOrigin: String = "https://antigravity.google.com",
        public val originalUrlString: String? = null,
        public val requiresRedirectResolution: Boolean = false,
    ) {
        public val canonicalRelayUrlString: String
            get() {
                val trimmedOrigin = relayOrigin.trimEnd('/')
                return if (instanceId.isEmpty()) trimmedOrigin else "$trimmedOrigin/r/$instanceId"
            }
    }

    public companion object {
        public fun isAntigravityRelayHost(rawHost: String): Boolean {
            val host = rawHost.lowercase()
            if (host == "accounts.google.com" || host == "www.google.com" || host == "google.com") {
                return false
            }
            if (host == "antigravity.google.com" || host == "antigravity.google" ||
                host.endsWith(".antigravity.google.com") || host.endsWith(".antigravity.google")
            ) {
                return true
            }
            if ((host.startsWith("antigravity.") || host.contains(".antigravity.") || host.contains("jetski")) &&
                (host.endsWith(".google.com") || host.endsWith(".google") || host.endsWith(".corp.google.com"))
            ) {
                return true
            }
            if (host == "antigravity.dev" || host.endsWith(".antigravity.dev") ||
                host == "antigravity.app" || host.endsWith(".antigravity.app")
            ) {
                return true
            }
            return false
        }

        public fun isGoogleShortlinkHost(rawHost: String): Boolean {
            val host = rawHost.lowercase()
            return host == "g.co" || host == "c.gle" || host == "goo.gl" ||
                host.endsWith(".goo.gl") || host.endsWith(".page.link")
        }

        public fun isLoopbackHost(rawHost: String): Boolean {
            val host = rawHost.lowercase()
            return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
        }

        public fun isDirectLanPairingUri(rawInput: String): Boolean {
            val parsed = SimpleUriParts.parse(rawInput.trim()) ?: return false
            val scheme = parsed.scheme.lowercase()
            if (scheme != "agpocket" && scheme != "antigravity" && scheme != "agy" && scheme != "google-antigravity") return false
            val targetUrl = parsed.queryParams.firstOrNull { it.first == "url" }?.second
            if (targetUrl.isNullOrEmpty()) return false
            if (parsed.host.lowercase() == "pair") return true
            val csrf = parsed.queryParams.firstOrNull { it.first == "csrf" }?.second
            return !csrf.isNullOrEmpty()
        }

        public fun canonicalizeRelayHost(rawHost: String): String {
            val host = rawHost.trim().lowercase()
            if (host == "antigravity.google") {
                return "antigravity.google.com"
            }
            if (host.endsWith(".antigravity.google")) {
                return "${host.removeSuffix(".antigravity.google")}.antigravity.google.com"
            }
            return host
        }

        public fun resolveEffectiveRelayTarget(
            scannedInput: String,
            webViewFinalUrl: String?,
        ): String {
            val trimmedScanned = scannedInput.trim()
            val trimmedFinal = webViewFinalUrl?.trim().orEmpty()
            val scannedTarget = parseRemoteControlTarget(trimmedScanned)
            val finalTarget = if (trimmedFinal.isEmpty()) null else parseRemoteControlTarget(trimmedFinal)

            if (finalTarget != null && finalTarget.instanceId.isNotEmpty()) {
                if (scannedTarget == null || scannedTarget.instanceId.isEmpty() || scannedTarget.requiresRedirectResolution) {
                    return trimmedFinal
                }
                val scannedHost = SimpleUriParts.parse(trimmedScanned)?.host?.lowercase().orEmpty()
                val finalHost = SimpleUriParts.parse(trimmedFinal)?.host?.lowercase().orEmpty()
                if (scannedHost.isNotEmpty() && finalHost.isNotEmpty() && scannedHost != finalHost &&
                    (scannedHost == "antigravity.google" || scannedHost.endsWith(".antigravity.google") ||
                        scannedHost == "antigravity.dev" || scannedHost == "antigravity.app")
                ) {
                    return trimmedFinal
                }
            }
            if (trimmedScanned.isNotEmpty()) {
                if (scannedTarget != null && !scannedTarget.requiresRedirectResolution) {
                    val scannedHost = SimpleUriParts.parse(trimmedScanned)?.host?.lowercase().orEmpty()
                    if (scannedHost == "antigravity.google" || scannedHost.endsWith(".antigravity.google")) {
                        return scannedTarget.canonicalRelayUrlString
                    }
                    return trimmedScanned
                }
                if (trimmedFinal.isNotEmpty()) return trimmedFinal
                return trimmedScanned
            }
            return trimmedFinal.ifEmpty { "https://antigravity.google.com" }
        }

        public fun parseRemoteControlTarget(rawInput: String): ParsedRemoteControlTarget? =
            parseRemoteControlTargetInternal(rawInput, depth = 0)

        private fun parseRemoteControlTargetInternal(
            rawInput: String,
            depth: Int,
        ): ParsedRemoteControlTarget? {
            if (depth > 4) return null
            val trimmed = rawInput.trim()
            if (trimmed.isEmpty() || isDirectLanPairingUri(trimmed)) return null

            // 1. Multi-word pasted prose containing embedded URL
            if (trimmed.any { it.isWhitespace() }) {
                val punct = setOf('"', '\'', '<', '>', '(', ')', '[', ']', '{', '}', ',', ';')
                for (rawToken in trimmed.split(Regex("\\s+"))) {
                    if (rawToken.isEmpty()) continue
                    var token = rawToken.trim { it in punct }
                    while (token.endsWith(".")) token = token.dropLast(1)
                    val lower = token.lowercase()
                    if (lower.contains("://") || lower.contains("antigravity.") ||
                        lower.contains(".google") || lower.startsWith("g.co/") || lower.startsWith("c.gle/")
                    ) {
                        parseRemoteControlTargetInternal(token, depth + 1)?.let { return it }
                    }
                }
                return null
            }

            // 2. Scheme-less URLs vs bare device slugs/UUIDs
            if (!trimmed.contains("://")) {
                val lower = trimmed.lowercase()
                val looksLikeSchemelessUrl = trimmed.contains("/") || trimmed.contains("?") ||
                    lower.startsWith("antigravity.") || lower.contains(".google.com") ||
                    lower.endsWith(".google") || lower.startsWith("g.co") ||
                    lower.startsWith("c.gle") || lower.startsWith("goo.gl") || lower.contains(".page.link")
                if (looksLikeSchemelessUrl) {
                    return parseRemoteControlTargetInternal("https://$trimmed", depth + 1)
                }
                val isBareSlug = trimmed.length in 3..128 &&
                    trimmed.all { it.isLetterOrDigit() || it == '-' || it == '_' }
                return if (isBareSlug) ParsedRemoteControlTarget(instanceId = trimmed) else null
            }

            val uri = SimpleUriParts.parse(trimmed) ?: return null
            val scheme = uri.scheme.lowercase()

            // 3. Custom AG Pocket / Antigravity deep-link schemes
            if (scheme == "agpocket" || scheme == "antigravity" || scheme == "agy" || scheme == "google-antigravity") {
                val hostLower = uri.host.lowercase()
                if ((scheme == "agpocket" || scheme == "antigravity") && (hostLower == "verify" || hostLower == "share")) return null
                unwrapRedirectQueryParameter(uri, depth)?.let { return it }
                val parts = uri.pathSegments
                var meta = extractMetadata(parts, uri.queryParams, uri.fragment)
                if (meta.instanceId.isEmpty()) {
                    val containerHosts = setOf("remote", "remote-control", "connect", "instance", "host", "open", "")
                    val reserved = setOf("c", "u")
                    val resolvedId = when {
                        hostLower == "r" && parts.isNotEmpty() -> parts[0]
                        hostLower in containerHosts && parts.isNotEmpty() && parts[0].lowercase() !in reserved -> parts[0]
                        hostLower.isNotEmpty() && hostLower !in containerHosts && hostLower !in reserved && parts.isEmpty() -> uri.host
                        else -> ""
                    }
                    meta = meta.copy(instanceId = resolvedId)
                }
                return ParsedRemoteControlTarget(
                    instanceId = meta.instanceId,
                    conversationId = meta.conversationId,
                    authUser = meta.authUser,
                    relayOrigin = "https://antigravity.google.com",
                    originalUrlString = trimmed,
                )
            }

            // 4. Standard https:// / http:// URLs
            if ((scheme != "https" && scheme != "http") || uri.host.isEmpty()) return null
            val host = uri.host.lowercase()
            val parts = uri.pathSegments

            unwrapRedirectQueryParameter(uri, depth)?.let { nested ->
                val mergedAuth = nested.authUser ?: extractMetadata(parts, uri.queryParams, uri.fragment).authUser
                return nested.copy(authUser = mergedAuth, originalUrlString = trimmed)
            }

            if (isGoogleShortlinkHost(host)) {
                if (parts.isEmpty()) return null
                return ParsedRemoteControlTarget(
                    instanceId = "",
                    relayOrigin = "https://antigravity.google.com",
                    originalUrlString = trimmed,
                    requiresRedirectResolution = true,
                )
            }
            if (host == "accounts.google.com" &&
                (trimmed.lowercase().contains("antigravity") || trimmed.lowercase().contains("jetski"))
            ) {
                return ParsedRemoteControlTarget(
                    instanceId = "",
                    relayOrigin = "https://antigravity.google.com",
                    originalUrlString = trimmed,
                    requiresRedirectResolution = true,
                )
            }

            val isAntigravity = isAntigravityRelayHost(host)
            val isLoopback = isLoopbackHost(host)
            if (isLoopback) {
                val lowerParts = parts.map { it.lowercase() }
                if ("r" !in lowerParts && "remote" !in lowerParts && "remote-control" !in lowerParts) {
                    return null
                }
            } else if (!isAntigravity) {
                return null
            }

            val extracted = extractMetadata(parts, uri.queryParams, uri.fragment)
            val canonicalHost = canonicalizeRelayHost(host)
            val origin = if (uri.port != null) "$scheme://$canonicalHost:${uri.port}" else "$scheme://$canonicalHost"
            return ParsedRemoteControlTarget(
                instanceId = extracted.instanceId,
                conversationId = extracted.conversationId,
                authUser = extracted.authUser,
                relayOrigin = origin,
                originalUrlString = trimmed,
                requiresRedirectResolution = false,
            )
        }

        private data class ExtractedMeta(
            val instanceId: String,
            val conversationId: String?,
            val authUser: String?,
        )

        private fun unwrapRedirectQueryParameter(
            uri: SimpleUriParts,
            depth: Int,
        ): ParsedRemoteControlTarget? {
            val redirectKeys = setOf(
                "continue", "url", "q", "redirect_uri", "redirect",
                "target", "link", "deep_link_id", "dest", "destination",
                "next", "followup",
            )
            val candidates = uri.queryParams.toMutableList()
            val frag = uri.fragment
            if (!frag.isNullOrEmpty() && frag.contains('=')) {
                candidates.addAll(SimpleUriParts.parseQuery(frag))
            }
            for ((k, v) in candidates) {
                if (k.lowercase() !in redirectKeys) continue
                val rawValue = v.trim()
                if (rawValue.isEmpty()) continue
                parseRemoteControlTargetInternal(rawValue, depth + 1)?.let { return it }
                val decoded = percentDecodeUtf8(rawValue)
                if (decoded != rawValue) {
                    parseRemoteControlTargetInternal(decoded, depth + 1)?.let { return it }
                }
            }
            return null
        }

        private fun extractMetadata(
            parts: List<String>,
            queryParams: List<Pair<String, String>>,
            fragment: String?,
        ): ExtractedMeta {
            val markerPrefixes = setOf("r", "remote", "remote-control", "instances", "instance", "host", "hosts", "d")
            val reservedSegments = setOf("c", "u", "login", "signin", "settings", "auth")

            var instanceId = ""
            val markerIdx = parts.indexOfFirst { it.lowercase() in markerPrefixes }
            if (markerIdx >= 0 && parts.size > markerIdx + 1) {
                val candidate = parts[markerIdx + 1]
                if (candidate.lowercase() !in reservedSegments) {
                    instanceId = candidate
                }
            }

            var authUser: String? = null
            val qAuth = queryParams.firstOrNull { it.first.equals("authuser", ignoreCase = true) }?.second
            if (!qAuth.isNullOrEmpty() && qAuth.all { it.isDigit() }) {
                authUser = qAuth
            } else {
                val uIdx = parts.indexOfFirst { it.equals("u", ignoreCase = true) }
                if (uIdx >= 0 && parts.size > uIdx + 1 && parts[uIdx + 1].isNotEmpty() && parts[uIdx + 1].all { it.isDigit() }) {
                    authUser = parts[uIdx + 1]
                }
            }

            var conversationId: String? = null
            val rawP = queryParams.firstOrNull { it.first.equals("p", ignoreCase = true) }?.second
            if (rawP != null) {
                val normalizedP = percentDecodeUtf8(rawP).removePrefix("/")
                if (normalizedP.startsWith("c/")) {
                    val cid = normalizedP.drop(2)
                    if (cid.isNotEmpty()) conversationId = cid
                }
            }
            if (conversationId == null) {
                val convKeys = setOf("c", "cascade", "cascade_id", "cascadeid", "conversation", "conversation_id", "conversationid")
                val rawConv = queryParams.firstOrNull { it.first.lowercase() in convKeys }?.second
                if (!rawConv.isNullOrBlank()) {
                    conversationId = percentDecodeUtf8(rawConv).trim().takeIf { it.isNotEmpty() }
                }
            }
            if (instanceId.isEmpty()) {
                val idKeys = setOf("instance", "instance_id", "instanceid", "host", "host_id", "hostid", "device", "device_id", "deviceid", "uuid", "r", "id", "slug")
                val rawInst = queryParams.firstOrNull { it.first.lowercase() in idKeys }?.second
                if (!rawInst.isNullOrBlank()) {
                    instanceId = percentDecodeUtf8(rawInst).trim()
                }
            }
            if (conversationId == null) {
                val cIdx = parts.indexOfFirst { it.equals("c", ignoreCase = true) }
                if (cIdx >= 0 && parts.size > cIdx + 1) {
                    val joined = parts.subList(cIdx + 1, parts.size).joinToString("/")
                    if (joined.isNotEmpty()) conversationId = joined
                }
            }

            if (!fragment.isNullOrEmpty() && (instanceId.isEmpty() || conversationId == null || authUser == null)) {
                val splitIdx = fragment.indexOf('?')
                val fragPath = if (splitIdx >= 0) fragment.substring(0, splitIdx) else fragment
                val fragQuery = when {
                    splitIdx >= 0 -> fragment.substring(splitIdx + 1)
                    !fragPath.contains('/') && fragPath.contains('=') -> fragPath
                    else -> null
                }
                val fragParts = if (fragPath.contains('=') && !fragPath.contains('/')) {
                    emptyList()
                } else {
                    fragPath.split('/').filter { it.isNotEmpty() }
                }
                val fragParams = fragQuery?.let { SimpleUriParts.parseQuery(it) } ?: emptyList()
                if (fragParts.isNotEmpty() || fragParams.isNotEmpty()) {
                    val fragMeta = extractMetadata(fragParts, fragParams, null)
                    if (instanceId.isEmpty()) instanceId = fragMeta.instanceId
                    if (conversationId == null) conversationId = fragMeta.conversationId
                    if (authUser == null) authUser = fragMeta.authUser
                }
            }

            return ExtractedMeta(instanceId, conversationId, authUser)
        }
    }
}

internal data class SimpleUriParts(
    val scheme: String,
    val host: String,
    val port: Int?,
    val pathSegments: List<String>,
    val queryParams: List<Pair<String, String>>,
    val fragment: String?,
) {
    companion object {
        fun parse(raw: String): SimpleUriParts? {
            val schemeEnd = raw.indexOf("://")
            if (schemeEnd <= 0) return null
            val scheme = raw.substring(0, schemeEnd)
            var rest = raw.substring(schemeEnd + 3)

            var fragment: String? = null
            val hashIdx = rest.indexOf('#')
            if (hashIdx >= 0) {
                fragment = rest.substring(hashIdx + 1)
                rest = rest.substring(0, hashIdx)
            }

            var queryStr: String? = null
            val qIdx = rest.indexOf('?')
            if (qIdx >= 0) {
                queryStr = rest.substring(qIdx + 1)
                rest = rest.substring(0, qIdx)
            }

            val slashIdx = rest.indexOf('/')
            val authority = if (slashIdx >= 0) rest.substring(0, slashIdx) else rest
            val path = if (slashIdx >= 0) rest.substring(slashIdx) else ""

            val (host, port) = if (authority.startsWith("[")) {
                val closeBracket = authority.indexOf(']')
                if (closeBracket >= 0) {
                    val h = authority.substring(0, closeBracket + 1)
                    val p = authority.substring(closeBracket + 1).removePrefix(":").toIntOrNull()
                    h to p
                } else {
                    authority to null
                }
            } else {
                val colonIdx = authority.lastIndexOf(':')
                if (colonIdx > 0) {
                    val p = authority.substring(colonIdx + 1).toIntOrNull()
                    if (p != null) authority.substring(0, colonIdx) to p else authority to null
                } else {
                    authority to null
                }
            }

            val segments = path.split('/').filter { it.isNotEmpty() }.map { percentDecodeUtf8(it) }
            val queryParams = queryStr?.let { parseQuery(it) } ?: emptyList()
            return SimpleUriParts(scheme, host, port, segments, queryParams, fragment)
        }

        fun parseQuery(rawQuery: String): List<Pair<String, String>> =
            rawQuery.split('&').mapNotNull { entry ->
                if (entry.isEmpty()) return@mapNotNull null
                val eqIdx = entry.indexOf('=')
                if (eqIdx < 0) {
                    percentDecodeUtf8(entry) to ""
                } else {
                    percentDecodeUtf8(entry.substring(0, eqIdx)) to
                        percentDecodeUtf8(entry.substring(eqIdx + 1).replace('+', ' '))
                }
            }
    }
}

@Serializable
public data class WorkspaceInfo(
    public val workspaceUri: String,
    public val displayName: String,
    public val activeBranch: String = "main",
    public val worktrees: List<String> = listOf("main"),
    public val activeCascadeCount: Int = 0,
    public val indexedFiles: List<String> = emptyList(),
    public val isCloud: Boolean = AntigravityCloudDetector.isCloudWorkspaceUri(workspaceUri),
    public val originInstanceUuid: String? = null,
    public val originHostName: String? = null,
) {
    public val id: String get() = workspaceUri
}

@Serializable(with = ThinkingEffortLevelSerializer::class)
public enum class ThinkingEffortLevel(
    public val displayTitle: String,
    public val cliValue: String,
    public val protoWireValue: String,
) {
    LOW("Low", "low", "LOW"),
    MEDIUM("Medium", "medium", "MEDIUM"),
    HIGH("High", "high", "HIGH"),
    EXTRA("Extra", "xhigh", "XHIGH"),
}

public object ThinkingEffortLevelSerializer : ResilientEnumSerializer<ThinkingEffortLevel>(
    serialName = "dev.antigravity.shared.model.ThinkingEffortLevel",
    entriesProvider = { ThinkingEffortLevel.entries },
    fallbackProvider = { ThinkingEffortLevel.HIGH },
    extraMatcher = { raw ->
        val norm = normalizeResilientEnumToken(raw)
        ThinkingEffortLevel.entries.firstOrNull {
            normalizeResilientEnumToken(it.cliValue) == norm ||
                normalizeResilientEnumToken(it.protoWireValue) == norm ||
                normalizeResilientEnumToken(it.displayTitle) == norm
        }
    },
)

@Serializable(with = CascadeExecutionModeSerializer::class)
public enum class CascadeExecutionMode(
    public val displayTitle: String,
    public val summaryDescription: String,
) {
    PLANNING("Planning", "Plans first and writes artifacts for you to review"),
    FAST("Fast", "Acts directly — best for small, local edits"),
}

public object CascadeExecutionModeSerializer : ResilientEnumSerializer<CascadeExecutionMode>(
    serialName = "dev.antigravity.shared.model.CascadeExecutionMode",
    entriesProvider = { CascadeExecutionMode.entries },
    fallbackProvider = { CascadeExecutionMode.PLANNING },
)

@Serializable(with = AgentPermissionPresetSerializer::class)
public enum class AgentPermissionPreset(
    public val rawValue: String,
    public val displayTitle: String,
    public val wireValue: String,
    public val semanticIcon: SemanticIcon,
) {
    REQUEST_REVIEW("request_review", "Request Review", "PERMISSION_PRESET_REQUEST_REVIEW", SemanticIcon.PERMISSION_REVIEW),
    DEFAULT_POLICY("default", "Default", "PERMISSION_PRESET_DEFAULT", SemanticIcon.PERMISSION_SANDBOX),
    AUTO("auto", "Auto", "PERMISSION_PRESET_AUTO", SemanticIcon.PERMISSION_AUTO),
    TURBO("turbo", "Turbo", "PERMISSION_PRESET_TURBO", SemanticIcon.PERMISSION_TURBO),
    INHERIT_GLOBAL("inherit_global", "Inherit Global", "PERMISSION_PRESET_INHERIT_GLOBAL", SemanticIcon.PERMISSION_INHERIT_GLOBAL);

    public val usesTerminalSandbox: Boolean
        get() = this == DEFAULT_POLICY || this == AUTO

    public companion object {
        /** Alias for [DEFAULT_POLICY] matching desktop & v2.33 sandboxed default terminology. */
        public val DEFAULT_SANDBOXED: AgentPermissionPreset
            get() = DEFAULT_POLICY

        public fun fromRaw(raw: String): AgentPermissionPreset? =
            entries.firstOrNull {
                it.rawValue.equals(raw, ignoreCase = true) ||
                    it.wireValue.equals(raw, ignoreCase = true) ||
                    it.name.equals(raw, ignoreCase = true)
            }

        public fun availablePresets(isRemote: Boolean): List<AgentPermissionPreset> =
            if (isRemote) listOf(REQUEST_REVIEW, TURBO)
            else listOf(REQUEST_REVIEW, DEFAULT_POLICY, AUTO, TURBO)

        public fun defaultPreset(isRemote: Boolean): AgentPermissionPreset =
            if (isRemote) TURBO else DEFAULT_POLICY
    }
}

public object AgentPermissionPresetSerializer : ResilientEnumSerializer<AgentPermissionPreset>(
    serialName = "dev.antigravity.shared.model.AgentPermissionPreset",
    entriesProvider = { AgentPermissionPreset.entries },
    fallbackProvider = { AgentPermissionPreset.DEFAULT_POLICY },
    extraMatcher = { raw -> AgentPermissionPreset.fromRaw(raw) },
)

@Serializable
public data class CascadeModelConfig(
    public val modelId: String,
    public val displayName: String,
    public val subtitle: String,
    public val mode: CascadeExecutionMode = CascadeExecutionMode.PLANNING,
    public val supportsThinking: Boolean = true,
    public val isThinkingEnabled: Boolean = true,
    public val thinkingEffort: ThinkingEffortLevel = ThinkingEffortLevel.HIGH,
    public val badgeTag: String? = null,
    public val agentPersona: String = "Default",
    public val isDefault: Boolean = false,
    public val isOrchestrator: Boolean = false,
    public val plannerModelName: String? = null,
    public val executorModelName: String? = null,
    public val supportedEfforts: List<ThinkingEffortLevel> =
        if (isOrchestrator) emptyList() else listOf(ThinkingEffortLevel.LOW, ThinkingEffortLevel.MEDIUM, ThinkingEffortLevel.HIGH),
    public val isNewBadge: Boolean = false,
    public val requiresUpgradeNote: String? = null,
    public val isModelAlias: Boolean = false,
) {
    public val id: String get() = modelId

    public val hasThinkingBadge: Boolean get() = supportsThinking

    public val supportsEffortAdjustment: Boolean
        get() = !isOrchestrator && supportedEfforts.isNotEmpty()

    public companion object {
        public val availableAgents: List<String> = listOf(
            "Default",
            "go-reviewer",
            "release-captain",
        )

        public fun isGenericBadgeLabel(text: String): Boolean {
            return when (text.trim().lowercase()) {
                "new", "beta", "preview", "alpha", "experimental", "recommended", "legacy" -> true
                else -> false
            }
        }

        public fun descriptiveSubtitle(modelLabel: String): String {
            val lower = modelLabel.lowercase()
            return when {
                lower.contains("flash") -> "Fastest responses and lightweight edits"
                lower.contains("opus") -> "Frontier Anthropic reasoning for complex architecture"
                lower.contains("sonnet") -> "Balanced Anthropic coding & reasoning"
                lower.contains("(xhigh)") || lower.contains("(x-high)") ||
                    lower.contains("(extra high)") || lower.contains("(max)") ->
                    "Maximum reasoning depth for the hardest tasks"
                lower.contains("(high)") -> "Deep reasoning for complex, multi-step tasks"
                lower.contains("(medium)") || lower.contains("(med)") ->
                    "Balanced speed and reasoning for daily work"
                lower.contains("(low)") || lower.contains("(minimal)") ->
                    "Faster responses for quick, everyday edits"
                lower.contains("gpt") || lower.contains("o3") || lower.contains("o4") ->
                    "OpenAI coding & reasoning model"
                else -> "Deep reasoning for long, multi-step tasks"
            }
        }

        /**
         * Live Antigravity 2.33+ default model catalog (Gemini 4 Neon default, Carbon, Argon,
         * Hydrogen, Orchestrator dual-model presets, Gemini 3.8 Flash, Claude 5.5, and Gemini 3.1/3).
         */
        public val liveDefaultCatalog: List<CascadeModelConfig> = listOf(
            CascadeModelConfig(
                modelId = "MODEL_GOOGLE_GEMINI_4_NEON",
                displayName = "Gemini 4 Neon",
                subtitle = "Default frontier reasoning · 512K context · 4 thinking levels",
                mode = CascadeExecutionMode.PLANNING,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                badgeTag = "New",
                isDefault = true,
                supportedEfforts = listOf(
                    ThinkingEffortLevel.LOW,
                    ThinkingEffortLevel.MEDIUM,
                    ThinkingEffortLevel.HIGH,
                    ThinkingEffortLevel.EXTRA,
                ),
                isNewBadge = true,
            ),
            CascadeModelConfig(
                modelId = "MODEL_ORCHESTRATOR_NEON",
                displayName = "Orchestrator (Neon)",
                subtitle = "Plans with Gemini 4 Neon · implements with Gemini 4 Hydrogen",
                mode = CascadeExecutionMode.PLANNING,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                badgeTag = "New",
                isOrchestrator = true,
                plannerModelName = "Gemini 4 Neon",
                executorModelName = "Gemini 4 Hydrogen",
                supportedEfforts = emptyList(),
                isNewBadge = true,
                isModelAlias = true,
            ),
            CascadeModelConfig(
                modelId = "MODEL_ORCHESTRATOR_CARBON",
                displayName = "Orchestrator (Carbon)",
                subtitle = "Plans with Gemini 4 Carbon · implements with Gemini 4 Hydrogen",
                mode = CascadeExecutionMode.PLANNING,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                badgeTag = "New",
                isOrchestrator = true,
                plannerModelName = "Gemini 4 Carbon",
                executorModelName = "Gemini 4 Hydrogen",
                supportedEfforts = emptyList(),
                isNewBadge = true,
                requiresUpgradeNote = "Google AI Ultra",
                isModelAlias = true,
            ),
            CascadeModelConfig(
                modelId = "MODEL_ORCHESTRATOR_ARGON",
                displayName = "Orchestrator (Argon)",
                subtitle = "Plans with Gemini 4 Argon · implements with Gemini 4 Hydrogen",
                mode = CascadeExecutionMode.PLANNING,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                badgeTag = "New",
                isOrchestrator = true,
                plannerModelName = "Gemini 4 Argon",
                executorModelName = "Gemini 4 Hydrogen",
                supportedEfforts = emptyList(),
                isNewBadge = true,
                isModelAlias = true,
            ),
            CascadeModelConfig(
                modelId = "MODEL_GOOGLE_GEMINI_4_CARBON",
                displayName = "Gemini 4 Carbon",
                subtitle = "Strongest long-horizon SWE, scientific & security reasoning",
                mode = CascadeExecutionMode.PLANNING,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                badgeTag = "New",
                supportedEfforts = listOf(
                    ThinkingEffortLevel.LOW,
                    ThinkingEffortLevel.MEDIUM,
                    ThinkingEffortLevel.HIGH,
                ),
                isNewBadge = true,
                requiresUpgradeNote = "Google AI Ultra",
            ),
            CascadeModelConfig(
                modelId = "MODEL_GOOGLE_GEMINI_4_ARGON",
                displayName = "Gemini 4 Argon",
                subtitle = "High-depth architecture & multi-file debugging",
                mode = CascadeExecutionMode.PLANNING,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                badgeTag = "New",
                supportedEfforts = listOf(
                    ThinkingEffortLevel.LOW,
                    ThinkingEffortLevel.MEDIUM,
                    ThinkingEffortLevel.HIGH,
                ),
                isNewBadge = true,
            ),
            CascadeModelConfig(
                modelId = "MODEL_GOOGLE_GEMINI_4_HYDROGEN",
                displayName = "Gemini 4 Hydrogen",
                subtitle = "Fast, dependable coding & agentic execution · 4 thinking levels",
                mode = CascadeExecutionMode.FAST,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                badgeTag = "New",
                supportedEfforts = listOf(
                    ThinkingEffortLevel.LOW,
                    ThinkingEffortLevel.MEDIUM,
                    ThinkingEffortLevel.HIGH,
                    ThinkingEffortLevel.EXTRA,
                ),
                isNewBadge = true,
            ),
            CascadeModelConfig(
                modelId = "MODEL_GOOGLE_GEMINI_3_8_FLASH",
                displayName = "Gemini 3.8 Flash",
                subtitle = "Fastest responses across all plans",
                mode = CascadeExecutionMode.FAST,
                supportsThinking = false,
                isThinkingEnabled = false,
                thinkingEffort = ThinkingEffortLevel.MEDIUM,
                supportedEfforts = listOf(
                    ThinkingEffortLevel.LOW,
                    ThinkingEffortLevel.MEDIUM,
                    ThinkingEffortLevel.HIGH,
                ),
            ),
            CascadeModelConfig(
                modelId = "MODEL_CLAUDE_5_5_OPUS_THINKING",
                displayName = "Claude Opus 5.5 (Thinking)",
                subtitle = "Frontier Anthropic reasoning for complex architecture",
                mode = CascadeExecutionMode.PLANNING,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                badgeTag = "New",
                supportedEfforts = listOf(
                    ThinkingEffortLevel.LOW,
                    ThinkingEffortLevel.MEDIUM,
                    ThinkingEffortLevel.HIGH,
                ),
                isNewBadge = true,
                requiresUpgradeNote = "Google AI Pro or Ultra",
            ),
            CascadeModelConfig(
                modelId = "MODEL_CLAUDE_5_5_SONNET_THINKING",
                displayName = "Claude Sonnet 5.5 (Thinking)",
                subtitle = "Balanced Anthropic coding & extended thinking",
                mode = CascadeExecutionMode.PLANNING,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                badgeTag = "New",
                supportedEfforts = listOf(
                    ThinkingEffortLevel.LOW,
                    ThinkingEffortLevel.MEDIUM,
                    ThinkingEffortLevel.HIGH,
                ),
                isNewBadge = true,
                requiresUpgradeNote = "Google AI Pro or Ultra",
            ),
            CascadeModelConfig(
                modelId = "MODEL_PLACEHOLDER_M37",
                displayName = "Gemini 3.1 Pro",
                subtitle = "Deep reasoning for long, multi-step tasks",
                mode = CascadeExecutionMode.PLANNING,
                supportsThinking = true,
                thinkingEffort = ThinkingEffortLevel.HIGH,
                supportedEfforts = listOf(
                    ThinkingEffortLevel.LOW,
                    ThinkingEffortLevel.MEDIUM,
                    ThinkingEffortLevel.HIGH,
                ),
            ),
            CascadeModelConfig(
                modelId = "MODEL_PLACEHOLDER_M18",
                displayName = "Gemini 3 Flash",
                subtitle = "Legacy Gemini 3 fast execution model",
                mode = CascadeExecutionMode.FAST,
                supportsThinking = false,
                isThinkingEnabled = false,
                thinkingEffort = ThinkingEffortLevel.MEDIUM,
                supportedEfforts = listOf(
                    ThinkingEffortLevel.LOW,
                    ThinkingEffortLevel.MEDIUM,
                    ThinkingEffortLevel.HIGH,
                ),
            ),
        )
    }
}

@Serializable
public data class LiveModelCatalogResult(
    public val models: List<CascadeModelConfig>,
    public val quota: ModelUsageQuota? = null,
    public val customAgents: List<String> = emptyList(),
    public val defaultModelId: String? = models.firstOrNull()?.modelId,
)

@Serializable(with = SlashCommandCategorySerializer::class)
public enum class SlashCommandCategory {
    FEATURED,
    APP_AND_CLI,
    APP_ONLY,
    CUSTOM_SKILL,
}

public object SlashCommandCategorySerializer : ResilientEnumSerializer<SlashCommandCategory>(
    serialName = "dev.antigravity.shared.model.SlashCommandCategory",
    entriesProvider = { SlashCommandCategory.entries },
    fallbackProvider = { SlashCommandCategory.APP_AND_CLI },
)

@Serializable
public data class SlashCommandItem(
    public val command: String,
    public val title: String,
    public val summary: String,
    public val icon: SemanticIcon,
    public val category: SlashCommandCategory = SlashCommandCategory.FEATURED,
    public val availableInRemoteAgent: Boolean = true,
    public val requiresPaidPlan: Boolean = false,
) {
    public val id: String get() = command

    public companion object {
        public val allCommands: List<SlashCommandItem> = listOf(
            SlashCommandItem("/plan", "Implementation Plan", "Draft a reviewable step-by-step architecture & verification plan before coding", SemanticIcon.COMMAND_PLAN, SlashCommandCategory.FEATURED),
            SlashCommandItem("/grill-me", "Design Alignment Interview", "Clarify ambiguous trade-offs via structured interactive question cards", SemanticIcon.COMMAND_GRILL_ME, SlashCommandCategory.FEATURED),
            SlashCommandItem("/goal", "Autonomous Goal Loop", "Run thorough multi-turn execution until all acceptance criteria pass", SemanticIcon.COMMAND_GOAL, SlashCommandCategory.FEATURED),
            SlashCommandItem("/boost", "Deep Reasoning Boost", "Iterative multi-agent deep reasoning & adversarial verification pass", SemanticIcon.COMMAND_BOOST, SlashCommandCategory.FEATURED, requiresPaidPlan = true),
            SlashCommandItem("/swarm", "Agent Swarm Board", "Coordinate named parallel workers & a verifier over a shared message board", SemanticIcon.COMMAND_SWARM, SlashCommandCategory.FEATURED, requiresPaidPlan = true),
            SlashCommandItem("/teamwork", "Collaborative Agent Team", "Multi-milestone agent team with scoping interview, Orchestrator & Auditor gates", SemanticIcon.COMMAND_TEAMWORK, SlashCommandCategory.FEATURED, requiresPaidPlan = true),
            SlashCommandItem("/run-workflow", "Dynamic Python Workflow", "Generate & approve a Python script orchestrating parallel() / pipeline() agents", SemanticIcon.COMMAND_WORKFLOW, SlashCommandCategory.FEATURED, requiresPaidPlan = true),
            SlashCommandItem("/schedule", "In-Conversation Schedule", "Set a timer or recurring cron check-in inside the active conversation", SemanticIcon.COMMAND_SCHEDULE, SlashCommandCategory.APP_AND_CLI),
            SlashCommandItem("/browser", "Browser Subagent", "Launch a browser subagent to playtest pages, inspect console/network & capture screenshots", SemanticIcon.COMMAND_BROWSER, SlashCommandCategory.APP_AND_CLI, availableInRemoteAgent = false),
            SlashCommandItem("/learn", "Learn Rules & Skills", "Capture corrections from this session into persistent rules and skills", SemanticIcon.COMMAND_LEARN, SlashCommandCategory.APP_AND_CLI),
            SlashCommandItem("/agy-customizations", "Manage Customizations", "Inspect and author rules, skills, plugins, hooks, and MCP servers", SemanticIcon.COMMAND_CUSTOMIZATIONS, SlashCommandCategory.APP_AND_CLI),
            SlashCommandItem("/antigravity-guide", "Antigravity Guide", "Interactive built-in guide to Antigravity 2.0 features and workflows", SemanticIcon.COMMAND_GUIDE, SlashCommandCategory.APP_AND_CLI),
            SlashCommandItem("/automation", "Create Automation", "Walk through creating a recurring scheduled automation across projects", SemanticIcon.COMMAND_AUTOMATION, SlashCommandCategory.APP_ONLY),
            SlashCommandItem("/generative_ui", "Interactive Generative UI", "Render rich interactive HTML charts, diagrams, and control widgets inline", SemanticIcon.COMMAND_GENERATIVE_UI, SlashCommandCategory.APP_ONLY),
            SlashCommandItem("/voice", "Voice Mode", "Start Gemini Live interactive voice session with your agent", SemanticIcon.COMMAND_VOICE, SlashCommandCategory.APP_ONLY, availableInRemoteAgent = true),
        )

        public fun commands(isRemoteAgent: Boolean, customSkills: List<SkillSummary> = emptyList()): List<SlashCommandItem> {
            val list = allCommands.filter { !isRemoteAgent || it.availableInRemoteAgent }.toMutableList()
            for (skill in customSkills) {
                if (!skill.isEnabled) continue
                val cmd = "/${skill.name}"
                if (list.none { it.command.equals(cmd, ignoreCase = true) }) {
                    list.add(
                        SlashCommandItem(
                            command = cmd,
                            title = skill.name,
                            summary = skill.description,
                            icon = SemanticIcon.COMMAND_CUSTOM_SKILL,
                            category = SlashCommandCategory.CUSTOM_SKILL,
                        )
                    )
                }
            }
            return list
        }
    }
}

@Serializable
public data class ComposerAttachmentChip(
    public val id: String,
    public val kind: Kind,
    public val label: String,
    public val targetUri: String? = null,
    public val mimeType: String? = null,
    public val inlinePayload: String? = null,
) {
    @Serializable(with = KindSerializer::class)
    public enum class Kind {
        FILE_MENTION,
        FOLDER,
        CONVERSATION_MENTION,
        IMAGE_SCREENSHOT,
        TERMINAL_LOG,
        SKILL,
        WORKFLOW,
        AUDIO_CLIP,
        PDF_DOCUMENT,
        VIDEO_CLIP,
        DIFF_QUOTE,
    }

    public object KindSerializer : ResilientEnumSerializer<Kind>(
        serialName = "dev.antigravity.shared.model.ComposerAttachmentChip.Kind",
        entriesProvider = { Kind.entries },
        fallbackProvider = { Kind.FILE_MENTION },
    )
}

@Serializable
public data class PendingDraftConversation(
    public val projectId: String,
    public val projectName: String,
    public val workspaceUri: String,
    public val isCloud: Boolean,
    public val cloudProjectId: String? = null,
    public val originInstanceUuid: String? = null,
)

@Serializable
public sealed interface AgentsHostFilterScope {
    @Serializable
    public data object AllHosts : AgentsHostFilterScope

    @Serializable
    public data object AntigravityCloud : AgentsHostFilterScope

    @Serializable
    public data class LocalHost(
        public val id: String,
        public val name: String,
    ) : AgentsHostFilterScope
}
