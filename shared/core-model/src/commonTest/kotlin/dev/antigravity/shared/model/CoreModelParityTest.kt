package dev.antigravity.shared.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CoreModelParityTest {

    @Test
    fun testSemanticIconCoverageAndSlashCommands() {
        assertEquals(AgentPermissionPreset.entries.size, AgentPermissionPreset.entries.map { it.semanticIcon }.toSet().size)
        assertEquals(listOf(AgentPermissionPreset.REQUEST_REVIEW, AgentPermissionPreset.TURBO), AgentPermissionPreset.availablePresets(isRemote = true))
        assertEquals(AgentPermissionPreset.TURBO, AgentPermissionPreset.defaultPreset(isRemote = true))
        assertEquals(AgentPermissionPreset.DEFAULT_POLICY, AgentPermissionPreset.defaultPreset(isRemote = false))

        assertTrue(SlashCommandItem.allCommands.isNotEmpty())
        assertEquals(SemanticIcon.COMMAND_PLAN, SlashCommandItem.allCommands.first { it.command == "/plan" }.icon)

        val cmds = SlashCommandItem.commands(
            isRemoteAgent = false,
            customSkills = listOf(SkillSummary(name = "kmp-sync", description = "Sync KMP core", isEnabled = true)),
        )
        assertEquals(SemanticIcon.COMMAND_CUSTOM_SKILL, cmds.first { it.command == "/kmp-sync" }.icon)
    }

    @Test
    fun testCloudDetectorUriNormalization() {
        assertTrue(AntigravityCloudDetector.isCloudWorkspaceUri("https://github.com/venciallee/iOSAntigravity"))
        assertTrue(AntigravityCloudDetector.isCloudWorkspaceUri("", cascadeId = "v1/jetski_remote_agents/123"))
        assertEquals(
            "cloud://venciallee/iOSAntigravity",
            AntigravityCloudDetector.normalizeWorkspaceUri("https://github.com/venciallee/iOSAntigravity.git", isCloud = true),
        )
        assertEquals(
            "cloud://venciallee/iOSAntigravity",
            AntigravityCloudDetector.normalizeWorkspaceUri("file:///home/antigravity/venciallee/iOSAntigravity", isCloud = true),
        )
        assertEquals("", AntigravityCloudDetector.normalizeWorkspaceUri("file:///home/antigravity", isCloud = true))
        assertTrue(AntigravityCloudDetector.isPlaygroundScratchUri("file:///Users/dev/.gemini/antigravity/playground/test"))
    }

    @Test
    fun testRemoteControlTargetParserParity() {
        // Direct official QR URL with conversation query param
        val direct = RemoteHostInstance.parseRemoteControlTarget(
            "https://antigravity.google.com/r/lt74xt6l0m-golden-star?p=c%2Fcas-123&authuser=2"
        )
        assertNotNull(direct)
        assertEquals("lt74xt6l0m-golden-star", direct.instanceId)
        assertEquals("cas-123", direct.conversationId)
        assertEquals("2", direct.authUser)
        assertEquals("https://antigravity.google.com/r/lt74xt6l0m-golden-star", direct.canonicalRelayUrlString)

        // Google AccountChooser redirect wrapper
        val wrapped = RemoteHostInstance.parseRemoteControlTarget(
            "https://accounts.google.com/AccountChooser?continue=https%3A%2F%2Fantigravity.google.com%2Fu%2F1%2Fr%2Fmac-mini-01"
        )
        assertNotNull(wrapped)
        assertEquals("mac-mini-01", wrapped.instanceId)
        assertEquals("1", wrapped.authUser)

        // Shortlink requires redirect resolution
        val shortlink = RemoteHostInstance.parseRemoteControlTarget("https://g.co/antigravity/xyz")
        assertNotNull(shortlink)
        assertTrue(shortlink.requiresRedirectResolution)

        // Bare slug
        val bare = RemoteHostInstance.parseRemoteControlTarget("lt74xt6l0m-golden-star")
        assertNotNull(bare)
        assertEquals("lt74xt6l0m-golden-star", bare.instanceId)

        // Direct LAN pairing URI must not be parsed as Cloud Relay target
        val lanUri = "antigravity://pair?url=http://192.168.1.5:8787&csrf=secret-token"
        assertTrue(RemoteHostInstance.isDirectLanPairingUri(lanUri))
        assertNull(RemoteHostInstance.parseRemoteControlTarget(lanUri))
    }

    @Test
    fun testCascadeDisplayItemsEvidenceGroupingAndDataUri() {
        val steps = listOf(
            CascadeStep("cas-1", 0, CortexStepType.CHECKPOINT, CortexStepStatus.DONE),
            CascadeStep("cas-1", 1, CortexStepType.USER_INPUT, CortexStepStatus.DONE, userInput = "Audit rate limiter"),
            CascadeStep("cas-1", 2, CortexStepType.VIEW_FILE, CortexStepStatus.DONE, viewFile = ViewFilePayload("file:///a.go")),
            CascadeStep("cas-1", 3, CortexStepType.SEARCH, CortexStepStatus.DONE, search = SearchPayload("Allow", "/src", 4)),
            CascadeStep("cas-1", 4, CortexStepType.PLANNER_RESPONSE, CortexStepStatus.IN_PROGRESS, plannerResponse = PlannerResponsePayload("")),
        )
        val items = CascadeDisplayItem.buildDisplayItems(steps)
        assertEquals(3, items.size)
        assertTrue(items[0] is CascadeDisplayItem.Single)
        val group = items[1] as CascadeDisplayItem.EvidenceGroup
        assertEquals(2, group.steps.size)
        assertEquals("cas-1-group-2-3", group.id)
        assertTrue(items[2] is CascadeDisplayItem.Single)

        // Status mapping parity
        assertEquals(CortexStepStatus.IN_PROGRESS, CortexStepStatus.fromJsonName("CORTEX_STEP_STATUS_GENERATING"))
        assertEquals(CortexStepStatus.CANCELLED, CortexStepStatus.fromJsonName("CORTEX_STEP_STATUS_INTERRUPTED"))

        // Data URI decoding parity
        val svgDataUri = "data:image/svg+xml;base64,PHN2Zz48Y2lyY2xlLz48L3N2Zz4="
        val resolved = ResolvedEmbedResource.decodeDataUri(svgDataUri)
        assertNotNull(resolved)
        assertTrue(resolved.isSvg)
        assertEquals("<svg><circle/></svg>", resolved.textContent)
    }
}
