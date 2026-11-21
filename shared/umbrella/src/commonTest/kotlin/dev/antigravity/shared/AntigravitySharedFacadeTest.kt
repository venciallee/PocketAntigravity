package dev.antigravity.shared

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
        assertEquals(600, AntigravitySharedFacade.PROTOBUF_STEP_THRESHOLD)
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
}
