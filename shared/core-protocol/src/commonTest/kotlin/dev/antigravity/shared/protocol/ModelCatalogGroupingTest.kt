package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.CascadeModelConfig
import dev.antigravity.shared.model.ThinkingEffortLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class ModelCatalogGroupingTest {

    @Test
    fun parseClientModelConfigsGroupsFlatDesktopEffortVariantsAndPreservesValidIds() {
        val payload = Json.parseToJsonElement(
            """
            {
              "clientModelConfigs": [
                {
                  "label": "Gemini 4 Neon (High)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M41" },
                  "tagTitle": "New",
                  "isRecommended": true
                },
                {
                  "label": "Gemini 4 Neon (XHigh)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M42" },
                  "tagTitle": "New"
                },
                {
                  "label": "Gemini 4 Neon (Medium)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M40" },
                  "tagTitle": "New"
                },
                {
                  "label": "Gemini 4 Neon (Low)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M39" },
                  "tagTitle": "New"
                },
                {
                  "label": "Gemini 4 Carbon (Medium)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M44" },
                  "tagTitle": "New"
                },
                {
                  "label": "Gemini 4 Carbon (High)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M45" },
                  "tagTitle": "New"
                },
                {
                  "label": "Gemini 4 Carbon (Low)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M43" },
                  "tagTitle": "New"
                },
                {
                  "label": "Gemini 4 Argon (Medium)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M47" },
                  "tagTitle": "Leaving Soon"
                },
                {
                  "label": "Gemini 4 Argon (Low)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M46" },
                  "tagTitle": "Leaving Soon"
                },
                {
                  "label": "Gemini 4 Argon (High)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M48" },
                  "tagTitle": "Leaving Soon"
                },
                {
                  "label": "Orchestrator (Neon)",
                  "modelOrAlias": { "alias": "ORCHESTRATOR_NEON" },
                  "isOrchestrator": true,
                  "tagTitle": "New"
                },
                {
                  "label": "Orchestrator (Carbon)",
                  "modelOrAlias": { "alias": "ORCHESTRATOR_CARBON" },
                  "isOrchestrator": true,
                  "tagTitle": "New"
                },
                {
                  "label": "Orchestrator (Argon)",
                  "modelOrAlias": { "alias": "ORCHESTRATOR_ARGON" },
                  "isOrchestrator": true,
                  "tagTitle": "New"
                },
                {
                  "label": "Claude Opus 5.5 (Low)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M51" },
                  "tagTitle": "New"
                },
                {
                  "label": "Claude Opus 5.5 (Medium)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M52" },
                  "tagTitle": "New"
                },
                {
                  "label": "Claude Opus 5.5 (High)",
                  "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M53" },
                  "tagTitle": "New"
                },
                {
                  "label": "GPT-OSS 120B (Medium)",
                  "modelOrAlias": { "model": "MODEL_OPENAI_GPT_OSS_120B_MEDIUM" },
                  "tagTitle": "Notice"
                }
              ],
              "defaultOverrideModelConfig": {
                "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M42" }
              }
            }
            """.trimIndent(),
        ).jsonObject

        val slice = V233RpcPayloadCodec.parseClientModelConfigsResponse(payload)
        assertNotNull(slice)

        // All 17 raw upstream IDs are preserved in validIds
        assertEquals(17, slice.validIds.size)
        assertTrue("MODEL_PLACEHOLDER_M39" in slice.validIds)
        assertTrue("MODEL_PLACEHOLDER_M42" in slice.validIds)
        assertTrue("ORCHESTRATOR_NEON" in slice.validIds)
        assertEquals("MODEL_PLACEHOLDER_M42", slice.defaultModelId)

        // Flat effort variants are collapsed into clean model families (zero duplicate Neon/Carbon rows)
        assertEquals(
            listOf(
                "Gemini 4 Neon",
                "Gemini 4 Carbon",
                "Gemini 4 Argon",
                "Orchestrator (Neon)",
                "Orchestrator (Carbon)",
                "Orchestrator (Argon)",
                "Claude Opus 5.5",
                "GPT-OSS 120B (Medium)",
            ),
            slice.models.map { it.displayName },
        )

        // Gemini 4 Neon has all 4 levels in canonical order and honors defaultOverrideModelConfig (XHigh)
        val neon = slice.models.first { it.displayName == "Gemini 4 Neon" }
        assertEquals(
            listOf(
                ThinkingEffortLevel.LOW,
                ThinkingEffortLevel.MEDIUM,
                ThinkingEffortLevel.HIGH,
                ThinkingEffortLevel.EXTRA,
            ),
            neon.supportedEfforts,
        )
        assertEquals(ThinkingEffortLevel.EXTRA, neon.thinkingEffort)
        assertEquals("MODEL_PLACEHOLDER_M42", neon.modelId)
        assertEquals("MODEL_PLACEHOLDER_M39", neon.resolvedModelId(ThinkingEffortLevel.LOW))
        assertEquals("MODEL_PLACEHOLDER_M40", neon.resolvedModelId(ThinkingEffortLevel.MEDIUM))
        assertEquals("MODEL_PLACEHOLDER_M41", neon.resolvedModelId(ThinkingEffortLevel.HIGH))
        assertEquals("MODEL_PLACEHOLDER_M42", neon.resolvedModelId(ThinkingEffortLevel.EXTRA))
        assertTrue(neon.containsModelId("MODEL_PLACEHOLDER_M39"))
        assertTrue(neon.isNewBadge)

        // Gemini 4 Carbon has ONLY 3 levels (Low, Medium, High) — NO Extra High
        val carbon = slice.models.first { it.displayName == "Gemini 4 Carbon" }
        assertEquals(
            listOf(ThinkingEffortLevel.LOW, ThinkingEffortLevel.MEDIUM, ThinkingEffortLevel.HIGH),
            carbon.supportedEfforts,
        )
        assertEquals(ThinkingEffortLevel.MEDIUM, carbon.thinkingEffort)
        assertEquals("MODEL_PLACEHOLDER_M44", carbon.modelId)
        assertEquals("MODEL_PLACEHOLDER_M45", carbon.resolvedModelId(ThinkingEffortLevel.HIGH))

        // Gemini 4 Argon carries "Leaving Soon" and is NOT marked New
        val argon = slice.models.first { it.displayName == "Gemini 4 Argon" }
        assertEquals("Leaving Soon", argon.badgeTag)
        assertFalse(argon.isNewBadge)

        // Orchestrator presets remain distinct with empty supportedEfforts
        val orchestrators = slice.models.filter { it.isOrchestrator }
        assertEquals(3, orchestrators.size)
        assertTrue(orchestrators.all { it.supportedEfforts.isEmpty() && !it.supportsEffortAdjustment })
        assertEquals("Carbon plans · Hydrogen executes", orchestrators[1].orchestratorSubtitle)

        // Single-variant GPT-OSS 120B (Medium) keeps its full title and hides effort selector
        val gptOss = slice.models.first { it.displayName == "GPT-OSS 120B (Medium)" }
        assertTrue(gptOss.supportedEfforts.isEmpty())
        assertFalse(gptOss.supportsEffortAdjustment)
        assertEquals("Notice", gptOss.badgeTag)

        // Partitioning primary vs extra works cleanly with live MODEL_PLACEHOLDER_Mxx IDs
        val (primary, extra) = CascadeModelConfig.partitionPrimaryAndExtraModels(slice.models)
        assertEquals(
            listOf("Gemini 4 Neon", "Gemini 4 Carbon", "Gemini 4 Argon", "Claude Opus 5.5", "GPT-OSS 120B (Medium)"),
            primary.map { it.displayName },
        )
        assertTrue(extra.isEmpty())
    }
}
