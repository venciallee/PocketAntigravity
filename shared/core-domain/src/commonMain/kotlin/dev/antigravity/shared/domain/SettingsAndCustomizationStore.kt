package dev.antigravity.shared.domain

import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AppAppearancePreferences
import dev.antigravity.shared.model.AppLanguage
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeModelConfig
import dev.antigravity.shared.model.CustomizationsCatalog
import dev.antigravity.shared.model.LiveModelCatalogResult
import dev.antigravity.shared.model.ModelUsageQuota
import dev.antigravity.shared.model.PermissionRuleEntry
import dev.antigravity.shared.model.ThinkingEffortLevel
import dev.antigravity.shared.platform.InMemoryPreferencesStore
import dev.antigravity.shared.platform.KeyValuePreferencesStore
import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.HostCapability
import dev.antigravity.shared.protocol.ProtocolCompatibilityEngine
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.Throws

public data class SettingsState(
    public val models: List<CascadeModelConfig> = CascadeModelConfig.liveDefaultCatalog,
    public val selectedMode: CascadeExecutionMode = CascadeExecutionMode.PLANNING,
    public val selectedModelId: String = "MODEL_GOOGLE_GEMINI_4_NEON",
    public val selectedEffort: ThinkingEffortLevel = ThinkingEffortLevel.EXTRA,
    public val selectedAgentPersona: String = "Default",
    public val availableAgentPersonas: List<String> = listOf("Default", "go-reviewer", "release-captain"),
    public val quota: ModelUsageQuota = ModelUsageQuota(
        planTierLabel = "Google AI Pro",
        usedPercent = 28.0,
        refreshCountdownLabel = "resets 3:40 PM",
        creditsRemaining = 820,
        isQuotaWarning = false,
        geminiWeeklyRemaining = 0.48,
        geminiFiveHourRemaining = 0.72,
        partnerWeeklyRemaining = 0.72,
        partnerFiveHourRemaining = 0.84,
        aiCreditOveragesEnabled = false,
    ),
    public val activePermissionPreset: AgentPermissionPreset = AgentPermissionPreset.DEFAULT_POLICY,
    public val localPermissionPreset: AgentPermissionPreset = AgentPermissionPreset.DEFAULT_POLICY,
    public val remotePermissionPreset: AgentPermissionPreset = AgentPermissionPreset.TURBO,
    public val permissionRules: List<PermissionRuleEntry> = emptyList(),
    public val customizations: CustomizationsCatalog = CustomizationsCatalog.defaultCatalog,
    public val appearance: AppAppearancePreferences = AppAppearancePreferences(),
    public val isRefreshingModels: Boolean = false,
    public val lastCapabilityError: String? = null,
) {
    /** Effective runtime-scoped permission preset (`Auto` is supported for local projects; remote defaults to `Turbo`). */
    public fun permissionPresetFor(isRemote: Boolean): AgentPermissionPreset =
        (if (isRemote) remotePermissionPreset else localPermissionPreset).resolveForRuntime(isRemote = isRemote)

    public val selectedModel: CascadeModelConfig?
        get() = models.firstOrNull { it.containsModelId(selectedModelId) }
            ?: if (selectedModelId == "MODEL_GOOGLE_GEMINI_3_1_PRO") {
                models.firstOrNull {
                    it.containsModelId("MODEL_PLACEHOLDER_M37") ||
                        it.displayName.contains("Gemini 3.1 Pro", ignoreCase = true)
                }
            } else {
                null
            }
            ?: models.firstOrNull()

    public val resolvedSelectedModelId: String
        get() = selectedModel?.resolvedModelId(selectedEffort) ?: selectedModelId

    public val resolvedSelectedIsModelAlias: Boolean
        get() = selectedModel?.resolvedIsModelAlias(selectedEffort) ?: (selectedModel?.isModelAlias == true)

    public val isEffortLockedForOrchestrator: Boolean
        get() = selectedModel?.isOrchestrator == true ||
            selectedModelId.contains("ORCHESTRATOR", ignoreCase = true)
}

/**
 * Shared KMP domain store for Model/Mode/Effort/Agent selection (`UE09`), Dual-Pool Usage Quota,
 * Permission Presets & Allow/Deny Rules, Customizations/MCP/Plugins, and Appearance/Theme preferences.
 */
public class SettingsAndCustomizationStore(
    private val preferencesStore: KeyValuePreferencesStore = InMemoryPreferencesStore(),
    private val onCapabilityError: (String) -> Unit = {},
) {
    public var persistPreferences: Boolean = true

    private val _state: MutableStateFlow<SettingsState> = run {
        val loadedAppearance = loadPersistedAppearance(preferencesStore)
        val loadedLocalPreset = loadPersistedLocalPermissionPreset(preferencesStore, loadedAppearance)
        val loadedRemotePreset = loadPersistedRemotePermissionPreset(preferencesStore)
        MutableStateFlow(
            SettingsState(
                activePermissionPreset = loadedLocalPreset,
                localPermissionPreset = loadedLocalPreset,
                remotePermissionPreset = loadedRemotePreset,
                appearance = loadedAppearance.copy(
                    globalPermissionPreset = loadedLocalPreset,
                    terminalSandboxEnabled = loadedLocalPreset.usesTerminalSandbox,
                ),
            ),
        )
    }
    public val state: StateFlow<SettingsState> = _state.asStateFlow()

    @Throws(Throwable::class)
    public suspend fun refreshModelCatalog(
        client: AntigravityKmpRpcClient?,
        forceRefresh: Boolean = false,
    ): LiveModelCatalogResult? {
        if (client == null) return null
        _state.update { it.copy(isRefreshingModels = true, lastCapabilityError = null) }
        return try {
            val result = client.fetchModelCatalog(forceRefresh = forceRefresh)
            applyModelCatalog(result)
            result
        } catch (c: CancellationException) {
            throw c
        } catch (e: Throwable) {
            _state.update { it.copy(isRefreshingModels = false) }
            recordCapabilityError(e.message ?: "Failed to refresh model catalog")
            null
        }
    }

    public fun applyModelCatalog(result: LiveModelCatalogResult) {
        val defaultId = result.defaultModelId
        _state.update { prev ->
            val nextModels = result.models.ifEmpty { prev.models }
            val matchedByPrevId = nextModels.firstOrNull { it.containsModelId(prev.selectedModelId) }
            val matchedByDefault = defaultId?.let { defId ->
                nextModels.firstOrNull { it.containsModelId(defId) }
            }
            val prevDisplayName = prev.selectedModel?.canonicalDisplayName
            val matchedByName = prevDisplayName?.let { name ->
                nextModels.firstOrNull { it.canonicalDisplayName.equals(name, ignoreCase = true) }
            }
            val matched = matchedByPrevId ?: matchedByDefault ?: matchedByName ?: nextModels.firstOrNull()

            val nextEffort = when {
                matched == null -> prev.selectedEffort
                matched.isOrchestrator || matched.supportedEfforts.isEmpty() -> matched.thinkingEffort
                matchedByPrevId != null -> {
                    matched.effortForVariantModelId(prev.selectedModelId)
                        ?: prev.selectedEffort.takeIf { it in matched.supportedEfforts }
                        ?: matched.clampedEffort(matched.thinkingEffort)
                }
                matchedByDefault != null && defaultId != null -> {
                    matched.effortForVariantModelId(defaultId)
                        ?: matched.clampedEffort(matched.thinkingEffort)
                }
                matchedByName != null && prev.selectedEffort in matched.supportedEfforts -> prev.selectedEffort
                else -> matched.clampedEffort(matched.thinkingEffort)
            }

            val nextSelectedModelId = matched?.resolvedModelId(nextEffort)
                ?: defaultId
                ?: prev.selectedModelId

            prev.copy(
                models = nextModels,
                selectedModelId = nextSelectedModelId,
                selectedEffort = nextEffort,
                quota = result.quota ?: prev.quota,
                availableAgentPersonas = result.customAgents.ifEmpty { prev.availableAgentPersonas },
                isRefreshingModels = false,
                lastCapabilityError = null,
            )
        }
    }

    public fun selectMode(mode: CascadeExecutionMode) {
        _state.update { it.copy(selectedMode = mode) }
    }

    public fun selectModel(modelId: String) {
        _state.update { prev ->
            val target = prev.models.firstOrNull { it.containsModelId(modelId) }
            if (target == null) {
                prev.copy(selectedModelId = modelId)
            } else {
                val isSameFamily = prev.selectedModel?.modelId == target.modelId
                val nextEffort = when {
                    target.isOrchestrator || target.supportedEfforts.isEmpty() -> target.thinkingEffort
                    else -> {
                        val explicitVariantEffort = target.effortForVariantModelId(modelId)
                        when {
                            explicitVariantEffort != null && (!isSameFamily || modelId != target.modelId) -> explicitVariantEffort
                            isSameFamily && prev.selectedEffort in target.supportedEfforts -> prev.selectedEffort
                            target.thinkingEffort in target.supportedEfforts -> target.thinkingEffort
                            else -> target.supportedEfforts.first()
                        }
                    }
                }
                val resolvedId = target.resolvedModelId(nextEffort)
                prev.copy(
                    selectedModelId = resolvedId,
                    selectedEffort = nextEffort,
                )
            }
        }
    }

    public fun selectThinkingEffort(effort: ThinkingEffortLevel) {
        _state.update { prev ->
            if (prev.isEffortLockedForOrchestrator) return@update prev
            val model = prev.selectedModel
            if (model != null && model.supportedEfforts.isNotEmpty() && effort !in model.supportedEfforts) {
                return@update prev
            }
            val nextModelId = model?.resolvedModelId(effort) ?: prev.selectedModelId
            prev.copy(
                selectedModelId = nextModelId,
                selectedEffort = effort,
            )
        }
    }

    public fun selectAgentPersona(persona: String) {
        _state.update { it.copy(selectedAgentPersona = persona) }
    }

    public fun selectPermissionPreset(
        preset: AgentPermissionPreset,
        isRemote: Boolean = false,
    ) {
        val resolved = preset.resolveForRuntime(isRemote = isRemote)
        if (isRemote) {
            _state.update { prev ->
                prev.copy(
                    remotePermissionPreset = resolved,
                    lastCapabilityError = null,
                )
            }
            if (persistPreferences) {
                preferencesStore.putString(KEY_REMOTE_PERMISSION_PRESET, resolved.rawValue)
            }
        } else {
            var updatedAppearance: AppAppearancePreferences? = null
            _state.update { prev ->
                val nextAppearance = prev.appearance.copy(
                    globalPermissionPreset = resolved,
                    terminalSandboxEnabled = resolved.usesTerminalSandbox,
                )
                updatedAppearance = nextAppearance
                prev.copy(
                    activePermissionPreset = resolved,
                    localPermissionPreset = resolved,
                    appearance = nextAppearance,
                    lastCapabilityError = null,
                )
            }
            if (persistPreferences) {
                preferencesStore.putString(KEY_LOCAL_PERMISSION_PRESET, resolved.rawValue)
                updatedAppearance?.let(::persistAppearanceIfEnabled)
            }
        }
    }

    @Throws(Throwable::class)
    public suspend fun setPermissionPreset(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        preset: AgentPermissionPreset,
    ) {
        val previousState = _state.value
        val resolved = preset.resolveForRuntime(isRemote = false)
        _state.update {
            it.copy(
                activePermissionPreset = resolved,
                localPermissionPreset = resolved,
                appearance = it.appearance.copy(
                    globalPermissionPreset = resolved,
                    terminalSandboxEnabled = resolved.usesTerminalSandbox,
                ),
                lastCapabilityError = null,
            )
        }
        var rolledBack = false
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.PERMISSION_PRESET,
            onUnsupported = ::recordCapabilityError,
            rollback = {
                rolledBack = true
                _state.update {
                    it.copy(
                        activePermissionPreset = previousState.activePermissionPreset,
                        localPermissionPreset = previousState.localPermissionPreset,
                        appearance = previousState.appearance,
                    )
                }
            },
        ) { rpc ->
            rpc.setConversationPermissionPreset(cascadeId = cascadeId, preset = resolved)
        }
        if (!rolledBack && persistPreferences) {
            preferencesStore.putString(KEY_LOCAL_PERMISSION_PRESET, resolved.rawValue)
            persistAppearanceIfEnabled(_state.value.appearance)
        }
    }

    public fun addPermissionRule(rule: PermissionRuleEntry) {
        _state.update { prev ->
            prev.copy(
                permissionRules = prev.permissionRules.filterNot { it.id == rule.id } + rule,
            )
        }
    }

    public fun removePermissionRule(ruleId: String) {
        _state.update { prev ->
            prev.copy(
                permissionRules = prev.permissionRules.filterNot { it.id == ruleId },
            )
        }
    }

    public suspend fun refreshCustomizations(
        client: AntigravityKmpRpcClient?,
    ): CustomizationsCatalog {
        if (client == null) return _state.value.customizations
        return try {
            val catalog = client.fetchCustomizationsCatalog()
            _state.update { prev ->
                prev.copy(
                    customizations = catalog,
                    availableAgentPersonas = catalog.customAgents.ifEmpty { prev.availableAgentPersonas },
                    lastCapabilityError = null,
                )
            }
            catalog
        } catch (c: CancellationException) {
            throw c
        } catch (e: Throwable) {
            val msg = if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                client.capabilityProfile().userFacingUnsupportedMessage(HostCapability.CUSTOMIZATIONS_CATALOG)
            } else {
                e.message ?: "Failed to refresh customizations"
            }
            recordCapabilityError(msg)
            _state.value.customizations
        }
    }

    public suspend fun restartMcpServer(
        client: AntigravityKmpRpcClient?,
        serverName: String,
    ) {
        val previous = _state.value.customizations
        _state.update { prev ->
            prev.copy(
                customizations = prev.customizations.copy(
                    mcpServers = prev.customizations.mcpServers.map { server ->
                        if (server.name == serverName) {
                            server.copy(isConnected = true, errorMessage = null)
                        } else {
                            server
                        }
                    },
                ),
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.CUSTOMIZATIONS_CATALOG,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(customizations = previous) } },
        ) { rpc ->
            rpc.restartMcpServer(serverName = serverName)
        }
    }

    public suspend fun togglePlugin(
        client: AntigravityKmpRpcClient?,
        pluginId: String,
        isEnabled: Boolean? = null,
    ) {
        val previous = _state.value.customizations
        val currentPlugin = previous.plugins.firstOrNull { it.id == pluginId }
        val targetEnabled = isEnabled ?: !(currentPlugin?.isEnabled ?: false)

        _state.update { prev ->
            prev.copy(
                customizations = prev.customizations.copy(
                    plugins = prev.customizations.plugins.map { plugin ->
                        if (plugin.id == pluginId) plugin.copy(isEnabled = targetEnabled) else plugin
                    },
                ),
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.CUSTOMIZATIONS_CATALOG,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(customizations = previous) } },
        ) { rpc ->
            rpc.togglePlugin(pluginId = pluginId, isEnabled = targetEnabled)
        }
    }

    public suspend fun installPlugin(
        client: AntigravityKmpRpcClient?,
        pluginId: String,
    ) {
        val previous = _state.value.customizations
        _state.update { prev ->
            prev.copy(
                customizations = prev.customizations.copy(
                    plugins = prev.customizations.plugins.map { plugin ->
                        if (plugin.id == pluginId) {
                            plugin.copy(isInstalled = true, isEnabled = true)
                        } else {
                            plugin
                        }
                    },
                ),
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.CUSTOMIZATIONS_CATALOG,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(customizations = previous) } },
        ) { rpc ->
            rpc.installMarketplacePlugin(pluginId = pluginId)
        }
    }

    public fun updateAppearance(transform: (AppAppearancePreferences) -> AppAppearancePreferences) {
        var updated: AppAppearancePreferences? = null
        _state.update { prev ->
            val next = transform(prev.appearance)
            updated = next
            prev.copy(appearance = next)
        }
        updated?.let(::persistAppearanceIfEnabled)
    }

    public fun setAppLanguage(language: AppLanguage) {
        updateAppearance { it.copy(language = language) }
    }

    public fun clearCapabilityError() {
        _state.update { it.copy(lastCapabilityError = null) }
    }

    private fun persistAppearanceIfEnabled(appearance: AppAppearancePreferences) {
        if (!persistPreferences) return
        preferencesStore.putString(KEY_APP_LANGUAGE, appearance.language.languageTag)
        runCatching {
            preferencesStore.putString(KEY_APPEARANCE_PREFERENCES, persistenceJson.encodeToString(appearance))
        }
    }

    private fun recordCapabilityError(message: String) {
        _state.update { it.copy(lastCapabilityError = message) }
        onCapabilityError(message)
    }

    public companion object {
        public const val KEY_APP_LANGUAGE: String = "antigravity.kmp.appLanguage.v1"
        public const val KEY_APPEARANCE_PREFERENCES: String = "antigravity.kmp.appearancePreferences.v1"
        public const val KEY_LOCAL_PERMISSION_PRESET: String = "antigravity.kmp.permissionPreset.local.v1"
        public const val KEY_REMOTE_PERMISSION_PRESET: String = "antigravity.kmp.permissionPreset.remote.v1"

        private val persistenceJson: Json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        private fun loadPersistedLocalPermissionPreset(
            preferencesStore: KeyValuePreferencesStore,
            appearance: AppAppearancePreferences,
        ): AgentPermissionPreset {
            val savedRaw = preferencesStore.getString(KEY_LOCAL_PERMISSION_PRESET)
            if (!savedRaw.isNullOrBlank()) {
                val parsed = AgentPermissionPreset.fromRaw(savedRaw)
                if (parsed != null && parsed != AgentPermissionPreset.INHERIT_GLOBAL) {
                    return parsed.resolveForRuntime(isRemote = false)
                }
            }
            return appearance.globalPermissionPreset.resolveForRuntime(isRemote = false)
        }

        private fun loadPersistedRemotePermissionPreset(
            preferencesStore: KeyValuePreferencesStore,
        ): AgentPermissionPreset {
            val savedRaw = preferencesStore.getString(KEY_REMOTE_PERMISSION_PRESET)
            if (!savedRaw.isNullOrBlank()) {
                val parsed = AgentPermissionPreset.fromRaw(savedRaw)
                if (parsed != null && parsed != AgentPermissionPreset.INHERIT_GLOBAL) {
                    return parsed.resolveForRuntime(isRemote = true)
                }
            }
            return AgentPermissionPreset.defaultPreset(isRemote = true)
        }

        private fun loadPersistedAppearance(preferencesStore: KeyValuePreferencesStore): AppAppearancePreferences {
            val rawJson = preferencesStore.getString(KEY_APPEARANCE_PREFERENCES)
            val decoded = if (!rawJson.isNullOrBlank()) {
                runCatching {
                    persistenceJson.decodeFromString<AppAppearancePreferences>(rawJson)
                }.getOrNull()
            } else {
                null
            }
            val rawLang = preferencesStore.getString(KEY_APP_LANGUAGE)
            if (decoded != null) {
                return if (!rawLang.isNullOrBlank()) {
                    decoded.copy(language = AppLanguage.fromTag(rawLang))
                } else {
                    decoded
                }
            }
            return if (!rawLang.isNullOrBlank()) {
                AppAppearancePreferences(language = AppLanguage.fromTag(rawLang))
            } else {
                AppAppearancePreferences()
            }
        }
    }
}
