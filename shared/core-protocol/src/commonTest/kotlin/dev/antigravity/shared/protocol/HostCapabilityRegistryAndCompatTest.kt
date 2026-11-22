package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.RequestedInteraction
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HostCapabilityRegistryAndCompatTest {

    @Test
    fun semVerParsesAndOrdersCorrectly() {
        val v231 = assertNotNull(AntigravitySemVer.parse("v2.31.0"))
        val v233Rc = assertNotNull(AntigravitySemVer.parse("2.33.0-rc.1"))
        val v233 = assertNotNull(AntigravitySemVer.parse("Antigravity v2.33.0"))
        val v300 = assertNotNull(AntigravitySemVer.parse("3.0"))

        assertTrue(v231 < v233Rc)
        assertTrue(v233Rc < v233)
        assertTrue(v233 < v300)
        assertEquals("v3.0.0", v300.toString())
        assertNull(AntigravitySemVer.parse("unknown"))
        assertNull(AntigravitySemVer.parse("   "))
        assertNull(AntigravitySemVer.parse(null))
    }

    @Test
    fun hostCapabilityRegistryCoversCoreAndOptionalMethods() {
        assertEquals(16, HostCapability.entries.size)
        assertEquals(HostCapability.TURN_DIFF, HostCapability.capabilityForMethod("GetTurnDiff"))
        assertEquals(HostCapability.GIT_VCS, HostCapability.capabilityForMethod("GitCommit"))
        assertEquals(HostCapability.SIDE_QUESTION, HostCapability.capabilityForMethod("SendSideQuestion"))
        assertEquals(HostCapability.CUSTOMIZATIONS_CATALOG, HostCapability.capabilityForMethod("RestartMcpServer"))

        // Core baseline methods must NEVER be permanently negative-cached
        assertFalse(HostCapability.shouldNegativeCacheOnUnimplemented("SendUserCascadeMessage"))
        assertFalse(HostCapability.shouldNegativeCacheOnUnimplemented("GetCascadeTrajectorySteps"))
        assertFalse(HostCapability.shouldNegativeCacheOnUnimplemented("HandleCascadeUserInteraction"))

        // Non-core & future optional RPCs MUST be negative-cached on 404/501
        assertTrue(HostCapability.shouldNegativeCacheOnUnimplemented("GetTurnDiff"))
        assertTrue(HostCapability.shouldNegativeCacheOnUnimplemented("FutureV3ExperimentalRpc"))
        assertTrue(HostCapability.allRegisteredMethods.containsAll(HostCapability.coreBaselineMethods))
        assertTrue(HostCapability.allRegisteredMethods.containsAll(HostCapability.legacyAliasMethods))
    }

    @Test
    fun capabilityProfileInvalidatesCachesOnVersionUpgradeAndHonorsBridgeOverride() {
        var profile = HostCapabilityProfile(hostKey = "mac-1", reportedVersion = "v2.31.0")
        profile = profile.recordMethodUnsupported("GetTurnDiff")
            .recordStrippedField("thinkingEffort", forMethod = "SendUserCascadeMessage")
            .recordDowngradedEnum("XHIGH", "HIGH", forMethod = "SendUserCascadeMessage")
            .recordJsonStepCeiling(600)

        assertEquals(CapabilitySupportState.UNSUPPORTED, profile.supportState(HostCapability.TURN_DIFF))
        assertTrue(profile.isMethodKnownUnsupported("GetTurnDiff"))
        assertTrue(profile.shouldPreferBinaryProtobufSteps(605))
        assertFalse(profile.shouldPreferBinaryProtobufSteps(120))
        assertTrue(profile.userFacingUnsupportedMessage(HostCapability.TURN_DIFF).contains("v2.31.0"))

        // Companion Bridge polyfill supersedes negative cache
        val bridged = profile.recordBridgeCapabilities(setOf("GetTurnDiff"))
        assertEquals(CapabilitySupportState.SUPPORTED, bridged.supportState(HostCapability.TURN_DIFF))
        assertFalse(bridged.isMethodKnownUnsupported("GetTurnDiff"))

        // Upgrading Desktop version clears stale negative caches and learned ceilings
        val upgraded = profile.updateReportedVersion("v2.33.0")
        assertEquals("v2.33.0", upgraded.reportedVersion)
        assertFalse(upgraded.isMethodKnownUnsupported("GetTurnDiff"))
        assertNull(upgraded.learnedJsonStepCeiling)
        assertTrue(upgraded.strippedFieldsByMethod.isEmpty())
        assertTrue(upgraded.downgradedEnumsByMethod.isEmpty())
    }

    @Test
    fun protocolCompatibilityEngineExtractsErrorsAndStripsFieldsWithRichItemFolding() {
        assertTrue(ProtocolCompatibilityEngine.isMethodUnimplementedResponse(404, ""))
        assertTrue(ProtocolCompatibilityEngine.isMethodUnimplementedResponse(501, "not implemented"))
        assertTrue(
            ProtocolCompatibilityEngine.isMethodUnimplementedResponse(
                400,
                """{"code":"unimplemented","message":"unknown method GetTurnDiff"}"""
            )
        )
        assertFalse(ProtocolCompatibilityEngine.isMethodUnimplementedResponse(500, "internal error"))

        assertEquals(
            "thinkingEffort",
            ProtocolCompatibilityEngine.extractUnknownProtoFieldName(
                """{"code":"invalid_argument","message":"unknown field \"thinkingEffort\""}"""
            )
        )
        assertEquals(
            "XHIGH",
            ProtocolCompatibilityEngine.extractInvalidEnumValue(
                """{"code":"invalid_argument","message":"invalid value for enum type ThinkingEffort: \"XHIGH\""}"""
            )
        )

        val payload = buildJsonObject {
            put("cascadeId", "cas-1")
            put("thinkingEffort", "XHIGH")
            put(
                "items",
                buildJsonArray {
                    add(
                        buildJsonObject {
                            put(
                                "codeQuote",
                                buildJsonObject {
                                    put("label", "middleware/ratelimit.go#L29")
                                    put("snippet", "now := time.Now()")
                                }
                            )
                        }
                    )
                    add(buildJsonObject { put("text", "Please refactor") })
                }
            )
        }

        val (afterFieldStrip, removed) = ProtocolCompatibilityEngine.recursivelyRemoveField("codeQuote", payload)
        assertTrue(removed)
        val firstItemText = afterFieldStrip["items"]!!.jsonArray[0].jsonObject["text"]!!.jsonPrimitive.content
        assertTrue(firstItemText.contains("middleware/ratelimit.go#L29"))
        assertTrue(firstItemText.contains("now := time.Now()"))

        val replacement = assertNotNull(ProtocolCompatibilityEngine.downgradedEnumReplacement("XHIGH"))
        assertEquals("HIGH", replacement)
        val (afterDowngrade, replaced) = ProtocolCompatibilityEngine.recursivelyReplaceEnumValue(
            "XHIGH",
            replacement,
            afterFieldStrip
        )
        assertTrue(replaced)
        assertEquals("HIGH", afterDowngrade["thinkingEffort"]?.jsonPrimitive?.contentOrNull)

        // Unknown future enum not in map falls back to stripping the holding key
        val futurePayload = buildJsonObject {
            put("cascadeId", "cas-1")
            put("futureMode", "FUTURE_SUPER_TURBO_V9")
        }
        val (strippedFuture, removedKeys) = ProtocolCompatibilityEngine.recursivelyRemoveKeysWithValue(
            "FUTURE_SUPER_TURBO_V9",
            futurePayload
        )
        assertEquals(setOf("futureMode"), removedKeys)
        assertNull(strippedFuture["futureMode"])
        assertEquals("cas-1", strippedFuture["cascadeId"]?.jsonPrimitive?.contentOrNull)
    }

    @Test
    fun forwardCompatibleUnknownStepAndUnknownInteractionDecodeSafely() {
        val futureStepJson = buildJsonObject {
            put("type", "CORTEX_STEP_TYPE_FUTURE_QUANTUM_PLANNER")
            put("status", "CORTEX_STEP_STATUS_WAITING")
            put(
                "futureQuantumPlanner",
                buildJsonObject {
                    put("summary", "Validating cross-repo deployment graph")
                }
            )
            put(
                "requestedInteraction",
                buildJsonObject {
                    put(
                        "futureDeployApproval",
                        buildJsonObject {
                            put("target", "prod-us-central1")
                            put("reason", "Requires biometric sign-off")
                        }
                    )
                }
            )
        }

        val step = JsonStepAndSummaryDecoder.decodeSingleStepJson(
            raw = futureStepJson,
            cascadeId = "cas-future",
            stepIndex = 42,
        )
        assertNotNull(step)
        assertEquals(CortexStepType.UNSPECIFIED, step.type)
        assertEquals(CortexStepStatus.WAITING, step.status)
        assertTrue(step.isUnrecognizedForwardStep)
        assertTrue(step.rawTypeName?.contains("FUTURE_QUANTUM_PLANNER") == true)
        assertNotNull(step.requestedInteraction)
        assertEquals("futureDeployApproval", step.requestedInteraction?.rawMemberKey)
        assertEquals(RequestedInteraction.MemberKind.APPROVAL_INTERACTION, step.requestedInteraction?.kind)
    }
}
