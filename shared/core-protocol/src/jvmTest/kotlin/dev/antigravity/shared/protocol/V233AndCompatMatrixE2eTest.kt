package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.DiffCompareMode
import dev.antigravity.shared.model.DiffLineComment
import dev.antigravity.shared.model.GitCommitDraft
import dev.antigravity.shared.model.PlanInlineComment
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import kotlinx.coroutines.test.runTest
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * End-to-end JVM integration suite executing KMP [AntigravityKmpRpcClient] v2.33 RPCs and
 * bidirectional compatibility behaviors against the real `verification/mock_language_server.py`.
 */
class V233AndCompatMatrixE2eTest {

    private fun locateRepoRoot(): File {
        var dir = File(System.getProperty("user.dir")).absoluteFile
        repeat(6) {
            if (File(dir, "verification/mock_language_server.py").exists()) return dir
            dir = dir.parentFile ?: return@repeat
        }
        error("Could not locate verification/mock_language_server.py from ${System.getProperty("user.dir")}")
    }

    private data class RunningMockServer(val process: Process, val port: Int)

    private fun startMockServer(): RunningMockServer {
        val repoRoot = locateRepoRoot()
        val bootstrap = """
            import sys, time
            sys.path.insert(0, 'verification')
            from mock_language_server import LiveMockServer
            with LiveMockServer() as srv:
                print(srv.port, flush=True)
                while True:
                    time.sleep(0.5)
        """.trimIndent()
        val process = ProcessBuilder("python3", "-u", "-c", bootstrap)
            .directory(repoRoot)
            .redirectErrorStream(true)
            .start()

        val reader = java.io.BufferedReader(java.io.InputStreamReader(process.inputStream))
        val firstLine = reader.readLine()?.trim()
        val port = firstLine?.toIntOrNull()
        if (port == null || port <= 0) {
            val remainder = buildString {
                if (firstLine != null) appendLine(firstLine)
                while (reader.ready()) {
                    appendLine(reader.readLine())
                }
            }.trim()
            process.destroyForcibly()
            error("mock_language_server.py failed to start cleanly; output=$remainder")
        }
        return RunningMockServer(process, port)
    }

    @Test
    fun fullV233RpcSurfacePassesAgainstMockLanguageServer() = runTest {
        val csrf = "kmp-v233-test-csrf"
        val mock = startMockServer()
        val proc = mock.process
        val port = mock.port
        try {
            val host = RemoteHostInstance(
                instanceId = "local-mock-v233",
                hostname = "MacBook Pro",
                version = "v2.33.0",
                channel = RemoteConnectionChannel.DIRECT_HOST,
                endpointUrl = "http://127.0.0.1:$port",
                certificateFingerprintSha256 = "",
            )
            val client = AntigravityKmpRpcClient(host = host, csrfToken = csrf)

            // 1. Model catalog + Gemini 4 / Orchestrator + Quota
            val catalog = client.fetchModelCatalog(forceRefresh = true)
            assertTrue(catalog.models.isNotEmpty(), "Expected live model catalog from mock server")

            // 2. Artifacts & Plan review comments
            val artifacts = client.getArtifactSnapshots("cas-rate-limiter")
            assertTrue(artifacts.isNotEmpty(), "Expected artifact snapshots")
            client.sendPlanReviewComments(
                cascadeId = "cas-flaky-settlement",
                comments = listOf(
                    PlanInlineComment(
                        id = "c-1",
                        targetFilePath = "settlement/batch.go",
                        quotedSpan = "time.Now()",
                        body = "Inject clock.Clock cleanly"
                    )
                )
            )

            // 3. Turn diff + hunk revert + diff comments + Git VCS
            val diffs = client.getTurnDiff("cas-rate-limiter", turnNumber = 3, mode = DiffCompareMode.TURN)
            assertTrue(diffs.isNotEmpty(), "Expected non-empty turn diffs")
            assertTrue(diffs.first().lines.isNotEmpty(), "Expected decoded diff lines")
            client.sendDiffReviewComments(
                cascadeId = "cas-rate-limiter",
                comments = listOf(
                    DiffLineComment(
                        id = "dc-1",
                        filePath = diffs.first().filePath,
                        lineNumber = 29,
                        body = "Use l.clock.Now()"
                    )
                )
            )
            client.revertDiffHunk("cas-rate-limiter", diffs.first().filePath, diffs.first().hunkHeader)
            client.gitStageFile("cas-rate-limiter", diffs.first().filePath)
            client.gitUnstageFile("cas-rate-limiter", diffs.first().filePath)
            val commit = client.gitCommitChanges(
                cascadeId = "cas-rate-limiter",
                draft = GitCommitDraft(message = "feat: add per-tenant rate limiter", pushAfterCommit = false)
            )
            assertTrue(commit.commitHash.isNotBlank())
            assertTrue(client.gitPushBranch("cas-rate-limiter", "main"))

            // 4. v2.33 Orchestration: Overview, Side Question (/btw), Permission Preset, Cancel/Stop, Revert
            val overview = client.fetchConversationOverview("cas-rate-limiter")
            assertTrue(overview.changedFilesCount >= 0)
            val sideAnswer = client.sendSideQuestion("cas-rate-limiter", "What is the mutex contention impact?")
            assertTrue(sideAnswer.isNotBlank())
            client.setConversationPermissionPreset("cas-rate-limiter", AgentPermissionPreset.DEFAULT_SANDBOXED)
            client.cancelBackgroundTask("cas-rate-limiter", "bg-task-1")
            client.stopSubagent("cas-rate-limiter", "sub-1")
            client.revertConversationToStep("cas-rate-limiter", 2)

            // 5. Customizations & Full-Text Search & Automations
            val customizations = client.fetchCustomizationsCatalog()
            assertTrue(customizations.skills.isNotEmpty() || customizations.mcpServers.isNotEmpty())
            client.restartMcpServer("github")
            client.togglePlugin("github", isEnabled = true)
            val hits = client.searchAllConversations("rate limiter")
            assertTrue(hits.isNotEmpty())

            val createdAuto = client.createAutomation("Every weekday at 9, audit dependencies", "ledger-svc")
            assertTrue(createdAuto.id.isNotBlank())
            client.setAutomationPaused(createdAuto.id, paused = true)

            // 6. Verify positive capability recording in HostCapabilityProfile
            val profile = client.capabilityProfile()
            assertEquals(CapabilitySupportState.SUPPORTED, profile.supportState(HostCapability.TURN_DIFF))
            assertEquals(CapabilitySupportState.SUPPORTED, profile.supportState(HostCapability.GIT_VCS))
            assertEquals(CapabilitySupportState.SUPPORTED, profile.supportState(HostCapability.SIDE_QUESTION))

            // 7. Verify >600-step binary Protobuf ceiling bypass (ATC-15)
            val allSteps = client.fetchAllTrajectorySteps("cas-large-605", knownStepCount = 605)
            assertTrue(allSteps.size >= 605, "Expected >= 605 decoded binary protobuf steps, got ${allSteps.size}")

            client.close()
        } finally {
            proc.destroyForcibly()
        }
    }

    @Test
    fun legacyHostNegativeCachesUnimplementedRpcsWithoutCrashingCoreChat() = runTest {
        val csrf = "kmp-legacy-csrf"
        val mock = startMockServer()
        val proc = mock.process
        val port = mock.port
        try {
            val host = RemoteHostInstance(
                instanceId = "legacy-mock-host",
                hostname = "Legacy Mac",
                version = "v2.30.0",
                channel = RemoteConnectionChannel.DIRECT_HOST,
                endpointUrl = "http://127.0.0.1:$port",
                certificateFingerprintSha256 = "",
            )
            val client = AntigravityKmpRpcClient(host = host, csrfToken = csrf)

            // Calling an unimplemented experimental RPC must throw HttpError(404/501) and negative-cache it
            var caughtUnimplemented = false
            try {
                client.callUnaryJson("FutureUnimplementedExperimentalRpc")
            } catch (e: AntigravityRpcError.HttpError) {
                caughtUnimplemented = ProtocolCompatibilityEngine.isMethodUnimplementedResponse(e.statusCode, e.body)
            }
            assertTrue(caughtUnimplemented, "Expected unimplemented HTTP error from mock server")
            assertTrue(client.capabilityProfile().isMethodKnownUnsupported("FutureUnimplementedExperimentalRpc"))

            // Core baseline RPCs remain completely unaffected
            val workspaces = client.getWorkspaceInfos()
            assertFalse(workspaces.isEmpty())

            client.close()
        } finally {
            proc.destroyForcibly()
        }
    }
}
