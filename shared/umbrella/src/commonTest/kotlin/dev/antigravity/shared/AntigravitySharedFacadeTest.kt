package dev.antigravity.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class AntigravitySharedFacadeTest {
    @Test
    fun testUmbrellaFacadeExportsAllCoreModules() {
        assertEquals(600, AntigravitySharedFacade.PROTOBUF_STEP_THRESHOLD)
        assertTrue(AntigravitySharedFacade.parseMarkdown("# Hello KMP").isNotEmpty())
        assertEquals(5 + 2, AntigravitySharedFacade.encodeConnectFrame("{}".encodeToByteArray()).size)
        assertNotNull(
            AntigravitySharedFacade.computeSapisidAuthHeader(
                cookieHeader = "SAPISID=test123",
                timestampSeconds = 1_700_000_000L,
            )
        )
    }
}
