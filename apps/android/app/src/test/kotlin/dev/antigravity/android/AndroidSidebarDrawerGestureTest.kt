package dev.antigravity.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import androidx.compose.ui.unit.dp
import dev.antigravity.android.ui.AntigravityAppRoot
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.EsddVerifySceneCase
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Interactive Compose E2E tests verifying Left Sidebar Drawer (`UE01B_SIDEBAR_DRAWER`)
 * left-to-right swipe-to-open, right-to-left swipe-to-close, tap-to-open/close animation,
 * long host pill bounds safety, device-switch repo scoping, underlying screen preservation,
 * and isolation on pushed sub-screens.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-xxhdpi")
class AndroidSidebarDrawerGestureTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun sidebarDrawerOpensOnLeftToRightSwipeAndClosesOnRightToLeftSwipe() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AGENTS_HOME,
            )
        }

        assertEquals(0, composeRule.onAllNodesWithTag("sidebar-drawer").fetchSemanticsNodes().size)

        // Swipe left-to-right from the left edge on Home -> opens Sidebar Drawer
        composeRule.onRoot().performTouchInput {
            swipeRight(startX = width * 0.03f, endX = width * 0.85f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("sidebar-drawer").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-new-conversation").assertIsDisplayed()

        // Swipe right-to-left on the open Sidebar Drawer -> closes cleanly back to Home
        composeRule.onRoot().performTouchInput {
            swipeLeft(startX = width * 0.72f, endX = width * 0.08f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        assertEquals(0, composeRule.onAllNodesWithTag("sidebar-drawer").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("home-greeting").assertIsDisplayed()
    }

    @Test
    fun sidebarDrawerSwipeInChatPreservesActiveConversationOnDismiss() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CHAT_AND_COMPOSER,
            )
        }

        composeRule.onNodeWithTag("chat-diff-pill").assertIsDisplayed()

        // Swipe left-to-right inside CascadeChat -> opens Sidebar Drawer over active conversation
        composeRule.onRoot().performTouchInput {
            swipeRight(startX = width * 0.03f, endX = width * 0.85f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("sidebar-drawer").assertIsDisplayed()

        // Swipe right-to-left -> closes drawer without losing the active conversation
        composeRule.onRoot().performTouchInput {
            swipeLeft(startX = width * 0.72f, endX = width * 0.08f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        assertEquals(0, composeRule.onAllNodesWithTag("sidebar-drawer").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("chat-diff-pill").assertIsDisplayed()
    }

    @Test
    fun pushedProjectDetailDoesNotOpenSidebarOnLeftSwipe() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.PROJECT_DETAIL,
            )
        }

        composeRule.onNodeWithTag("project-tab-active").assertIsDisplayed()
        composeRule.onRoot().performTouchInput {
            swipeRight(startX = width * 0.03f, endX = width * 0.85f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        assertEquals(0, composeRule.onAllNodesWithTag("sidebar-drawer").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("project-tab-active").assertIsDisplayed()
    }

    @Test
    fun longHostNameDoesNotOverlapTopBarButtonsAndTapOpensAndClosesDrawer() {
        val longHostName = "huangjiafandemac-mini-local-swift-vapor"
        val miniHost = RemoteHostInstance(
            instanceId = "uuid-macmini",
            hostname = longHostName,
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = "https://antigravity.google.com/r/uuid-macmini",
            isOnline = true,
        )
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        coordinator.connectionStore.seedVerificationConnection(
            activeHost = miniHost,
            knownHosts = listOf(miniHost),
            userDisplayName = "Vencial",
        )
        coordinator.selectHostScope(AgentsHostFilterScope.LocalHost(miniHost.instanceId, longHostName))

        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = null,
            )
        }
        composeRule.waitForIdle()

        val sidebarNode = composeRule.onNodeWithTag("btn-sidebar").assertIsDisplayed()
        val pillNode = composeRule.onNodeWithTag("host-switcher-pill").assertIsDisplayed()
        val searchNode = composeRule.onNodeWithTag("btn-search").assertIsDisplayed()

        val sidebarBounds = sidebarNode.getUnclippedBoundsInRoot()
        val pillBounds = pillNode.getUnclippedBoundsInRoot()
        val searchBounds = searchNode.getUnclippedBoundsInRoot()

        assertTrue(
            "Long host pill (${pillBounds.left}) must not overlap left sidebar button (${sidebarBounds.right})",
            sidebarBounds.right <= pillBounds.left + 1.dp,
        )
        assertTrue(
            "Long host pill (${pillBounds.right}) must not overlap right search button (${searchBounds.left})",
            pillBounds.right <= searchBounds.left + 1.dp,
        )

        // Tap top-left button -> opens drawer smoothly, tap scrim -> closes back to 0 drawer nodes
        sidebarNode.performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("sidebar-drawer").assertIsDisplayed()

        composeRule.onNodeWithTag("sidebar-scrim").performClick()
        composeRule.waitForIdle()
        assertEquals(0, composeRule.onAllNodesWithTag("sidebar-drawer").fetchSemanticsNodes().size)
    }

    @Test
    fun switchingHostScopeUpdatesHomeRepoPickerAndSidebarProjects() {
        val mbpHost = RemoteHostInstance(
            instanceId = "uuid-mbp",
            hostname = "MacBook Pro",
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = "https://antigravity.google.com/r/uuid-mbp",
            isOnline = true,
        )
        val miniHost = RemoteHostInstance(
            instanceId = "uuid-macmini",
            hostname = "huangjiafandemac-mini-local-swift-vapor",
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = "https://antigravity.google.com/r/uuid-macmini",
            isOnline = true,
        )
        val mbpProject = ProjectWorkspace(
            id = "mbp-ios-app",
            name = "mbp-ios-app",
            pathDisplay = "~/mbp-ios-app",
            workspaceUri = "file:///Users/mbp/mbp-ios-app",
            runtime = ProjectRuntimeTarget.MAC_BOOK_PRO,
            hostName = mbpHost.hostname,
            originInstanceUuid = mbpHost.instanceId,
        )
        val miniProject = ProjectWorkspace(
            id = "vapor-backend",
            name = "vapor-backend",
            pathDisplay = "~/vapor-backend",
            workspaceUri = "file:///Users/mini/vapor-backend",
            runtime = ProjectRuntimeTarget.MAC_BOOK_PRO,
            hostName = miniHost.hostname,
            originInstanceUuid = miniHost.instanceId,
        )
        val cloudProject = ProjectWorkspace(
            id = "cloud-pocket",
            name = "venciallee/PocketAntigravity",
            pathDisplay = "Cloud · venciallee/PocketAntigravity",
            workspaceUri = "cloud://venciallee/PocketAntigravity",
            runtime = ProjectRuntimeTarget.CLOUD,
            hostName = "Cloud",
            cloudProjectId = "cloud-pocket",
        )
        val allProjects = listOf(mbpProject, miniProject, cloudProject)
        val summaries = listOf(
            CascadeSummary(
                cascadeId = "cas-mbp",
                title = "MBP Task",
                projectSlug = mbpProject.id,
                workspaceUri = mbpProject.workspaceUri,
                status = CortexStepStatus.DONE,
                stepCount = 2,
                originInstanceUuid = mbpHost.instanceId,
                originHostName = mbpHost.hostname,
            ),
            CascadeSummary(
                cascadeId = "cas-mini",
                title = "Mini Vapor Task",
                projectSlug = miniProject.id,
                workspaceUri = miniProject.workspaceUri,
                status = CortexStepStatus.DONE,
                stepCount = 3,
                originInstanceUuid = miniHost.instanceId,
                originHostName = miniHost.hostname,
            ),
        )

        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        coordinator.connectionStore.seedVerificationConnection(
            activeHost = mbpHost,
            knownHosts = listOf(mbpHost, miniHost),
            userDisplayName = "Vencial",
        )
        coordinator.workspaceStore.seedFixture(
            projects = allProjects,
            automations = emptyList(),
            availableRepos = emptyList(),
            contextCandidates = emptyList(),
            selectedProjectId = mbpProject.id,
        )
        coordinator.conversationSyncStore.seedFixtureData(
            workspaces = emptyList(),
            projects = allProjects,
            summaries = summaries,
        )
        coordinator.selectHostScope(AgentsHostFilterScope.LocalHost(mbpHost.instanceId, mbpHost.hostname))

        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = null,
            )
        }
        composeRule.waitForIdle()

        // Initially scoped to MacBook Pro -> repo picker displays mbp-ios-app
        composeRule.onNodeWithTag("home-project-picker").assertTextContains("mbp-ios-app", substring = true)

        // Switch to Mac mini via top Host Switcher menu -> repo picker must switch to vapor-backend
        composeRule.onNodeWithTag("host-switcher-pill").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("host-option-uuid-macmini").performClick()
        composeRule.waitForIdle()

        composeRule.onNodeWithTag("home-project-picker").assertTextContains("vapor-backend", substring = true)
        composeRule.onNodeWithTag("home-project-picker").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("home-project-option-vapor-backend").assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithTag("home-project-option-mbp-ios-app").fetchSemanticsNodes().size)
        assertEquals(0, composeRule.onAllNodesWithTag("home-project-option-cloud-pocket").fetchSemanticsNodes().size)
        // Select vapor-backend to close repo dropdown cleanly
        composeRule.onNodeWithTag("home-project-option-vapor-backend").performClick()
        composeRule.waitForIdle()

        // Sidebar drawer must also scope to Mac mini projects/conversations
        composeRule.onNodeWithTag("btn-sidebar").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("project-header-vapor-backend").assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithTag("project-header-mbp-ios-app").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("sidebar-scrim").performClick()
        composeRule.waitForIdle()

        // Switch to Antigravity Cloud -> repo picker updates to venciallee/PocketAntigravity
        composeRule.onNodeWithTag("host-switcher-pill").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("host-option-cloud").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("home-project-picker")
            .assertTextContains("venciallee/PocketAntigravity", substring = true)
    }
}
