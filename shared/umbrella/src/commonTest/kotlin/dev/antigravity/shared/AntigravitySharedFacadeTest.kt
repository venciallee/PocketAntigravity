package dev.antigravity.shared

import dev.antigravity.shared.protocol.AntigravityRpcError
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class AntigravitySharedFacadeTest {
    @Test
    fun testUmbrellaFacadeExportsAllCoreModulesAndCoordinator() = runTest {
        assertEquals("2.33.0-kmp-phase2", AntigravitySharedFacade.CORE_VERSION)
        assertEquals("binary-first-adaptive-json", AntigravitySharedFacade.TRAJECTORY_SYNC_STRATEGY)
        assertTrue(AntigravitySharedFacade.parseMarkdown("# Hello KMP Phase 2").isNotEmpty())
        assertEquals(5 + 2, AntigravitySharedFacade.encodeConnectFrame("{}".encodeToByteArray()).size)
        assertNotNull(
            AntigravitySharedFacade.computeSapisidAuthHeader(
                cookieHeader = "SAPISID=test123",
                timestampSeconds = 1_700_000_000L,
            )
        )

        val coordinator = AntigravitySharedFacade.createCoordinator()
        assertFalse(coordinator.connectionState.value.isConnected)
        assertTrue(coordinator.parseMarkdown("Use `Ktor` + **SKIE**").isNotEmpty())
        coordinator.close()
    }

    @Test
    fun testKmpBridgeHelpersErrorDetailMessageReturnsRawHttpBodyWithoutPrefix() {
        val rawBody = """[5,"not_found: trajectory not found (error ID: 721ffeb9b0bb4fb6b2a971dfa56087e2)"]"""
        val err = AntigravityRpcError.HttpError(404, rawBody)
        assertEquals("http:404", KmpBridgeHelpers.errorKindTag(err))
        assertEquals(rawBody, KmpBridgeHelpers.errorDetailMessage(err))
        assertFalse(KmpBridgeHelpers.errorDetailMessage(err).startsWith("HTTP 404:"))
    }
}
