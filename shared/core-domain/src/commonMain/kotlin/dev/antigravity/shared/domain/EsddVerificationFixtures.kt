package dev.antigravity.shared.domain

import dev.antigravity.shared.model.AppLanguage
import dev.antigravity.shared.model.ArtifactKind
import dev.antigravity.shared.model.ArtifactSnapshot
import dev.antigravity.shared.model.AskQuestionInteractionSpec
import dev.antigravity.shared.model.AutomationItem
import dev.antigravity.shared.model.AutomationSectionKind
import dev.antigravity.shared.model.BackgroundTaskItem
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.CodeActionPayload
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.ContextCandidateCategory
import dev.antigravity.shared.model.ContextCandidateItem
import dev.antigravity.shared.model.ConversationGoalItem
import dev.antigravity.shared.model.ConversationOverviewSnapshot
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.DiffLine
import dev.antigravity.shared.model.EsddVerifySceneCase
import dev.antigravity.shared.model.FilePatchDiff
import dev.antigravity.shared.model.FilePermissionInteractionSpec
import dev.antigravity.shared.model.GitHubPullRequestInfo
import dev.antigravity.shared.model.GitHubRepoItem
import dev.antigravity.shared.model.NewProjectDraft
import dev.antigravity.shared.model.PlanInlineComment
import dev.antigravity.shared.model.PlanProposedFileChange
import dev.antigravity.shared.model.PlannerResponsePayload
import dev.antigravity.shared.model.ProjectDetailTab
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.model.RunCommandInteractionSpec
import dev.antigravity.shared.model.RunCommandPayload
import dev.antigravity.shared.model.StructuredQuestionStepItem
import dev.antigravity.shared.model.SubagentPayload
import dev.antigravity.shared.model.SwarmBoardPayload
import dev.antigravity.shared.model.SwarmBoardPost
import dev.antigravity.shared.model.SwarmMemberItem
import dev.antigravity.shared.model.TaskBoundaryPayload
import dev.antigravity.shared.model.TaskChecklistItem
import dev.antigravity.shared.model.TaskChecklistStatus
import dev.antigravity.shared.model.ViewFilePayload
import dev.antigravity.shared.model.WorkspaceInfo

/**
 * Canonical 1:1 deterministic offline ESDD verification dataset (`UE01` .. `UE13`) shared across
 * Android Compose, iOS UIKit/SwiftUI, and KMP JVM tests. Mirrors `ESDDVerificationFixtures.swift`.
 */
public object EsddVerificationFixtures {
    public const val BASE_NOW_EPOCH_MS: Long = 1_762_793_357_000L

    public const val INITIAL_COMPOSER_DRAFT: String =
        "Use 1000/s instead — staging is smaller than prod."

    public const val INITIAL_LINE_COMMENT_DRAFT: String =
        "Use l.clock.Now() — the plan says to inject the clock so tests can control time."

    public val macHost: RemoteHostInstance = RemoteHostInstance(
        instanceId = "macbook-pro-local",
        hostname = "MacBook Pro",
        version = "2.33.1",
        channel = RemoteConnectionChannel.CLOUD_RELAY,
        endpointUrl = "https://127.0.0.1:42100",
        isOnline = true,
        latencyMs = 42,
    )

    public val officeImacHost: RemoteHostInstance = RemoteHostInstance(
        instanceId = "office-imac-local",
        hostname = "Office iMac",
        version = "2.32.0",
        channel = RemoteConnectionChannel.CLOUD_RELAY,
        endpointUrl = "https://antigravity.google.com/r/office-imac-local",
        isOnline = false,
        latencyMs = 0,
    )

    public val cloudHost: RemoteHostInstance = RemoteHostInstance(
        instanceId = "cloud-vm-us-central1",
        hostname = "Cloud",
        version = "2.33.1",
        channel = RemoteConnectionChannel.CLOUD_RELAY,
        endpointUrl = "https://antigravity.google.com/r/cloud-vm-us-central1",
        isOnline = true,
        latencyMs = 24,
    )

    public val hosts: List<RemoteHostInstance> = listOf(macHost, officeImacHost, cloudHost)

    public val projects: List<ProjectWorkspace> = listOf(
        ProjectWorkspace(
            id = "ledger-svc",
            name = "ledger-svc",
            pathDisplay = "~/code/ledger-svc",
            workspaceUri = "file:///Users/wl/code/ledger-svc",
            runtime = ProjectRuntimeTarget.MAC_BOOK_PRO,
            hostName = "MacBook Pro",
            activeBranch = "main",
            worktrees = listOf("main", "feat/ratelimit", "fix/settlement-clock"),
            isExpandedInHome = true,
            rulesAndSkillsCount = 4,
            originInstanceUuid = "macbook-pro-local",
        ),
        ProjectWorkspace(
            id = "web-console",
            name = "web-console",
            pathDisplay = "cloud://acme/web-console",
            workspaceUri = "cloud://acme/web-console",
            runtime = ProjectRuntimeTarget.CLOUD,
            hostName = "Cloud",
            activeBranch = "main",
            worktrees = listOf("main", "feat/dark-mode"),
            isExpandedInHome = true,
            rulesAndSkillsCount = 3,
            originInstanceUuid = "cloud-vm-us-central1",
        ),
    )

    public val workspaces: List<WorkspaceInfo> = listOf(
        WorkspaceInfo(
            workspaceUri = "file:///Users/wl/code/ledger-svc",
            displayName = "ledger-svc",
            activeBranch = "main",
            worktrees = listOf("main", "feat/ratelimit", "fix/settlement-clock"),
            activeCascadeCount = 3,
            indexedFiles = listOf(
                "internal/middleware/ratelimit.go",
                "internal/router/transfers.go",
                "internal/settlement/batch.go",
                "internal/settlement/settlement_test.go",
                "load/transfers.txt",
            ),
            isCloud = false,
            originInstanceUuid = "macbook-pro-local",
            originHostName = "MacBook Pro",
        ),
        WorkspaceInfo(
            workspaceUri = "cloud://acme/web-console",
            displayName = "web-console",
            activeBranch = "main",
            worktrees = listOf("main", "feat/dark-mode"),
            activeCascadeCount = 2,
            indexedFiles = listOf(
                "src/pages/settings/DarkModeToggle.tsx",
                "src/theme/tokens.ts",
            ),
            isCloud = true,
            originInstanceUuid = "cloud-vm-us-central1",
            originHostName = "Cloud",
        ),
    )

    public val availableRepos: List<GitHubRepoItem> = listOf(
        GitHubRepoItem(
            id = "repo-ledger-svc",
            fullName = "acme/ledger-svc",
            visibilityLabel = "Private",
            defaultBranch = "main",
        ),
        GitHubRepoItem(
            id = "repo-web-console",
            fullName = "acme/web-console",
            visibilityLabel = "Private",
            defaultBranch = "main",
        ),
        GitHubRepoItem(
            id = "repo-design-tokens",
            fullName = "acme/design-tokens",
            visibilityLabel = "Public",
            defaultBranch = "main",
        ),
    )

    public val summaries: List<CascadeSummary> = listOf(
        CascadeSummary(
            cascadeId = "cas-rate-limiter",
            title = "Add rate limiter to /transfers",
            projectSlug = "ledger-svc",
            workspaceUri = "file:///Users/wl/code/ledger-svc",
            branchName = "main",
            status = CortexStepStatus.IN_PROGRESS,
            stepCount = 28,
            currentStepIndex = 4,
            totalSteps = 7,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS,
            relativeTimeLabel = "now",
            statusSubtitle = "Running · Step 4 of 7 · go test ./internal/...",
            isPinned = true,
            isArchived = false,
            isUnread = false,
            modelLabel = "Gemini 4 Neon",
            pendingInteractionTitle = "Approve: vegeta attack...",
            lastMessagePreview = "Plan approved with your 2 comments. Tests pass — next is a load test, which needs your OK.",
            totalAdditions = 128,
            totalDeletions = 14,
            isCloud = false,
            originInstanceUuid = "macbook-pro-local",
            originHostName = "MacBook Pro",
        ),
        CascadeSummary(
            cascadeId = "cas-flaky-settlement",
            title = "Fix flaky TestSettlementBatch",
            projectSlug = "ledger-svc",
            workspaceUri = "file:///Users/wl/code/ledger-svc",
            branchName = "main",
            status = CortexStepStatus.WAITING,
            stepCount = 12,
            currentStepIndex = 2,
            totalSteps = 5,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 480_000L,
            relativeTimeLabel = "8m",
            statusSubtitle = "Needs review · Implementation plan ready",
            isPinned = false,
            isArchived = false,
            isUnread = true,
            modelLabel = "Gemini 4 Neon",
            pendingInteractionTitle = "Awaiting review · Implementation Plan",
            lastMessagePreview = "The flake comes from a shared fake clock across parallel subtests in settlement_test.go. I wrote a plan to isolate it per test — review it before I change anything?",
            totalAdditions = 0,
            totalDeletions = 0,
            isCloud = false,
            originInstanceUuid = "macbook-pro-local",
            originHostName = "MacBook Pro",
        ),
        CascadeSummary(
            cascadeId = "cas-release-checklist",
            title = "Release checklist v2.3",
            projectSlug = "web-console",
            workspaceUri = "cloud://acme/web-console",
            branchName = "main",
            status = CortexStepStatus.DONE,
            stepCount = 19,
            currentStepIndex = 5,
            totalSteps = 5,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 3_500_000L,
            relativeTimeLabel = "1h",
            statusSubtitle = "Done · Walkthrough ready",
            isPinned = true,
            isArchived = false,
            isUnread = false,
            modelLabel = "Gemini 3.8 Flash",
            lastMessagePreview = "All v2.3 release checks succeeded and walkthrough artifact is ready.",
            totalAdditions = 34,
            totalDeletions = 8,
            isCloud = true,
            originInstanceUuid = "cloud-vm-us-central1",
            originHostName = "Cloud",
        ),
        CascadeSummary(
            cascadeId = "cas-upgrade-go",
            title = "Upgrade to Go 1.25",
            projectSlug = "ledger-svc",
            workspaceUri = "file:///Users/wl/code/ledger-svc",
            branchName = "main",
            status = CortexStepStatus.DONE,
            stepCount = 31,
            currentStepIndex = 6,
            totalSteps = 6,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 14_400_000L,
            relativeTimeLabel = "4h",
            statusSubtitle = "Done · 6 files changed",
            isPinned = false,
            isArchived = false,
            isUnread = true,
            modelLabel = "Gemini 4 Neon",
            lastMessagePreview = "Updated go.mod toolchain to Go 1.25 across 6 packages.",
            totalAdditions = 42,
            totalDeletions = 31,
            isCloud = false,
            originInstanceUuid = "macbook-pro-local",
            originHostName = "MacBook Pro",
        ),
        CascadeSummary(
            cascadeId = "cas-dark-mode-cloud",
            title = "Dark mode for settings page",
            projectSlug = "web-console",
            workspaceUri = "cloud://acme/web-console",
            branchName = "feat/dark-mode",
            status = CortexStepStatus.IN_PROGRESS,
            stepCount = 9,
            currentStepIndex = 2,
            totalSteps = 5,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 7_200_000L,
            relativeTimeLabel = "12:04",
            statusSubtitle = "Running in cloud · Step 2 of 5",
            isPinned = false,
            isArchived = false,
            isUnread = true,
            modelLabel = "Gemini 3.8 Flash",
            lastMessagePreview = "Applying semantic obsidian tokens to SettingsView...",
            totalAdditions = 64,
            totalDeletions = 21,
            isCloud = true,
            originInstanceUuid = "cloud-vm-us-central1",
            originHostName = "Cloud",
        ),
        CascadeSummary(
            cascadeId = "cas-audit-bundle-size",
            title = "Audit bundle size",
            projectSlug = "web-console",
            workspaceUri = "cloud://acme/web-console",
            branchName = "main",
            status = CortexStepStatus.DONE,
            stepCount = 14,
            currentStepIndex = 4,
            totalSteps = 4,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 172_800_000L,
            relativeTimeLabel = "2d",
            statusSubtitle = "Done · -18KB gzipped",
            isPinned = false,
            isArchived = false,
            isUnread = false,
            modelLabel = "Gemini 3.8 Flash",
            lastMessagePreview = "Tree-shook unused icon chunks and reduced initial bundle by 18KB.",
            totalAdditions = 12,
            totalDeletions = 98,
            isCloud = true,
            originInstanceUuid = "cloud-vm-us-central1",
            originHostName = "Cloud",
        ),
        CascadeSummary(
            cascadeId = "cas-idempotency-payouts",
            title = "Idempotency keys for payouts",
            projectSlug = "ledger-svc",
            workspaceUri = "file:///Users/wl/code/ledger-svc",
            branchName = "main",
            status = CortexStepStatus.DONE,
            stepCount = 45,
            currentStepIndex = 8,
            totalSteps = 8,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 86_400_000L,
            relativeTimeLabel = "1d",
            statusSubtitle = "Done · Merged into main",
            isPinned = false,
            isArchived = false,
            isUnread = false,
            modelLabel = "Gemini 4 Neon",
            lastMessagePreview = "Merged payout idempotency key store into main.",
            totalAdditions = 210,
            totalDeletions = 19,
            isCloud = false,
            originInstanceUuid = "macbook-pro-local",
            originHostName = "MacBook Pro",
        ),
        CascadeSummary(
            cascadeId = "cas-audit-log-admin",
            title = "Audit log for admin actions",
            projectSlug = "ledger-svc",
            workspaceUri = "file:///Users/wl/code/ledger-svc",
            branchName = "main",
            status = CortexStepStatus.WAITING,
            stepCount = 3,
            currentStepIndex = 2,
            totalSteps = 3,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 172_800_000L,
            relativeTimeLabel = "2d",
            statusSubtitle = "Archived · /plan interview",
            isPinned = false,
            isArchived = true,
            isUnread = false,
            modelLabel = "Gemini 4 Neon",
            lastMessagePreview = "Before I draft the plan I need three decisions. Tap to answer — you can also reply in your own words.",
            isCloud = false,
            originInstanceUuid = "macbook-pro-local",
            originHostName = "MacBook Pro",
        ),
        CascadeSummary(
            cascadeId = "cas-pgx-v5-migration",
            title = "Migrate settlement store to pgx v5",
            projectSlug = "ledger-svc",
            workspaceUri = "file:///Users/wl/code/ledger-svc",
            branchName = "main",
            status = CortexStepStatus.DONE,
            stepCount = 37,
            currentStepIndex = 6,
            totalSteps = 6,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 345_600_000L,
            relativeTimeLabel = "4d",
            statusSubtitle = "Archived · Merged",
            isPinned = false,
            isArchived = true,
            isUnread = false,
            modelLabel = "Gemini 4 Neon",
            lastMessagePreview = "Completed pgxpool v5 batch migration.",
            isCloud = false,
            originInstanceUuid = "macbook-pro-local",
            originHostName = "MacBook Pro",
        ),
    )

    public val automations: List<AutomationItem> = listOf(
        AutomationItem(
            id = "auto-nightly-audit",
            title = "Nightly dependency audit",
            projectSlug = "ledger-svc",
            scheduleSummary = "ledger-svc · Daily at 02:00 · Flash",
            section = AutomationSectionKind.SCHEDULED,
            nextRunText = "Tonight, 02:00",
            lastRunText = "Succeeded · 22h ago",
            needsReview = false,
            isRunningNow = false,
            prompt = "Check go.mod for outdated or vulnerable modules. Open a PR for patch bumps only and summarize the rest.",
            modelLabel = "Flash",
            repeatsLabel = "Every day · 2:00 AM",
            timeLabel = "2:00 AM",
            timezoneLabel = "GMT+8:00",
            recentRuns = listOf(
                dev.antigravity.shared.model.AutomationRunRecord(
                    id = "run-1",
                    status = dev.antigravity.shared.model.AutomationRunStatus.SUCCEEDED,
                    timestampLabel = "Succeeded · 22h ago",
                    summary = "No vulnerable modules · 2 patch bumps",
                    canRetry = false,
                ),
                dev.antigravity.shared.model.AutomationRunRecord(
                    id = "run-2",
                    status = dev.antigravity.shared.model.AutomationRunStatus.NEEDS_REVIEW,
                    timestampLabel = "Needs review · 2d ago",
                    summary = "PR for golang.org/x/net waiting",
                    canRetry = false,
                ),
                dev.antigravity.shared.model.AutomationRunRecord(
                    id = "run-3",
                    status = dev.antigravity.shared.model.AutomationRunStatus.FAILED,
                    timestampLabel = "Failed · 3d ago",
                    summary = "Google sign-in expired",
                    canRetry = true,
                ),
            ),
        ),
        AutomationItem(
            id = "auto-weekly-flaky",
            title = "Weekly flaky-test report",
            projectSlug = "ledger-svc",
            scheduleSummary = "ledger-svc · Mondays at 09:00 · Pro",
            section = AutomationSectionKind.SCHEDULED,
            nextRunText = "Mon, 09:00",
            lastRunText = "Needs review · 2d",
            needsReview = true,
            isRunningNow = false,
            prompt = "Analyze CI test flake trends from the past 7 days and open a prioritized summary.",
            modelLabel = "Pro",
            repeatsLabel = "Every week · 9:00 AM",
            timeLabel = "9:00 AM",
            timezoneLabel = "GMT+8:00",
        ),
        AutomationItem(
            id = "auto-pr-triage",
            title = "Triage new pull requests",
            projectSlug = "web-console",
            scheduleSummary = "web-console · On PR opened · Flash Lite",
            section = AutomationSectionKind.ALWAYS_ON,
            nextRunText = "On PR opened",
            lastRunText = "Last run 14m ago",
            needsReview = false,
            isRunningNow = false,
            prompt = "Label incoming pull requests, verify required checks, and summarize diff risk.",
            modelLabel = "Flash Lite",
            repeatsLabel = "Always on",
            timeLabel = "On PR opened",
            timezoneLabel = "GMT+8:00",
        ),
        AutomationItem(
            id = "auto-bundle-size",
            title = "Bundle size watch",
            projectSlug = "web-console",
            scheduleSummary = "web-console · Daily at 08:00 · Flash",
            section = AutomationSectionKind.PAUSED,
            nextRunText = "Paused",
            lastRunText = "Paused · 5d ago",
            needsReview = false,
            isRunningNow = false,
            prompt = "Measure production web bundle gzipped size and alert if main chunk grows > 10KB.",
            modelLabel = "Flash",
            repeatsLabel = "Every day · 8:00 AM",
            timeLabel = "8:00 AM",
            timezoneLabel = "GMT+8:00",
        ),
    )

    public val contextCandidates: List<ContextCandidateItem> = listOf(
        ContextCandidateItem(
            id = "ctx-ratelimit",
            category = ContextCandidateCategory.FILES,
            title = "ratelimit.go",
            subtitle = "internal/middleware · changed this turn",
            chipLabel = "@ratelimit.go",
            isActionTrigger = false,
            isSelected = true,
        ),
        ContextCandidateItem(
            id = "ctx-load-folder",
            category = ContextCandidateCategory.FOLDER,
            title = "load/",
            subtitle = "Folder · 3 files",
            chipLabel = "@load/",
            isActionTrigger = false,
            isSelected = false,
        ),
        ContextCandidateItem(
            id = "ctx-idempotency-conv",
            category = ContextCandidateCategory.MENTIONS,
            title = "Idempotency keys for payouts",
            subtitle = "Conversation · ledger-svc",
            chipLabel = "@Idempotency keys for payouts",
            isActionTrigger = false,
            isSelected = true,
        ),
        ContextCandidateItem(
            id = "ctx-terminal-last-test",
            category = ContextCandidateCategory.MENTIONS,
            title = "Terminal · last test run",
            subtitle = "Output · 214 lines",
            chipLabel = "@terminal:last-test",
            isActionTrigger = false,
            isSelected = false,
        ),
        ContextCandidateItem(
            id = "ctx-action-boost",
            category = ContextCandidateCategory.ACTIONS,
            title = "/boost",
            subtitle = "Action · extra multi-agent reasoning pass",
            chipLabel = "/boost",
            isActionTrigger = true,
            isSelected = false,
        ),
        ContextCandidateItem(
            id = "ctx-skill-go-testing",
            category = ContextCandidateCategory.SKILLS,
            title = "go-testing",
            subtitle = "Skill · table-driven tests, -race, golden files",
            chipLabel = "Skill · go-testing",
            isActionTrigger = false,
            isSelected = true,
        ),
    )

    public val initialComposerChips: List<ComposerAttachmentChip> = listOf(
        ComposerAttachmentChip(
            id = "chip-ratelimit",
            kind = ComposerAttachmentChip.Kind.FILE_MENTION,
            label = "@ratelimit.go",
            targetUri = "file:///Users/wl/code/ledger-svc/internal/middleware/ratelimit.go",
        ),
    )

    public val questionSteps: List<StructuredQuestionStepItem> = listOf(
        StructuredQuestionStepItem(
            id = "q-step-1-storage",
            stepNumber = 1,
            shortTabTitle = "Storage",
            questionTitle = "Where should admin audit events be persisted?",
            options = listOf(
                "Dedicated audit_events Postgres table",
                "Append-only Kafka audit topic",
                "Daily S3 Parquet archive",
            ),
            selectedOptions = setOf("Dedicated audit_events Postgres table"),
            customWriteIn = "",
            isCompleted = true,
            isMultiSelect = false,
        ),
        StructuredQuestionStepItem(
            id = "q-step-2-actions",
            stepNumber = 2,
            shortTabTitle = "Actions",
            questionTitle = "Which admin actions should be audited?",
            options = listOf(
                "Account freeze / unfreeze",
                "Limit changes",
                "Manual ledger adjustments",
                "Role & permission changes",
            ),
            selectedOptions = setOf(
                "Account freeze / unfreeze",
                "Limit changes",
                "Manual ledger adjustments",
            ),
            customWriteIn = "",
            isCompleted = false,
            isMultiSelect = true,
        ),
        StructuredQuestionStepItem(
            id = "q-step-3-retention",
            stepNumber = 3,
            shortTabTitle = "Retention",
            questionTitle = "How long should audit entries be retained?",
            options = listOf(
                "90 days hot + 7 years cold compliance archive",
                "1 year hot Postgres",
                "Indefinite immutable retention",
            ),
            selectedOptions = setOf("90 days hot + 7 years cold compliance archive"),
            customWriteIn = "",
            isCompleted = false,
            isMultiSelect = false,
        ),
    )

    public val planChanges: List<PlanProposedFileChange> = listOf(
        PlanProposedFileChange(
            id = "plan-change-batch",
            changeKind = "MODIFY",
            filePath = "settlement/batch.go",
            summaryText = "Accept a clock.Clock through BatchOptions instead of calling time.Now() directly.",
            highlightedSpan = "instead of calling time.Now() directly",
            isSelectedForCallout = false,
        ),
        PlanProposedFileChange(
            id = "plan-change-test",
            changeKind = "MODIFY",
            filePath = "settlement/settlement_test.go",
            summaryText = "Create one clock per subtest; remove the package-level clk variable.",
            highlightedSpan = "remove the package-level clk variable",
            isSelectedForCallout = true,
        ),
        PlanProposedFileChange(
            id = "plan-change-clock",
            changeKind = "NEW",
            filePath = "testutil/clock.go",
            summaryText = "NewTestClock(t) helper, released with t.Cleanup.",
            highlightedSpan = null,
            isSelectedForCallout = false,
        ),
    )

    public val planComments: List<PlanInlineComment> = listOf(
        PlanInlineComment(
            id = "plan-comment-1",
            authorInitials = "WL",
            authorName = "You",
            statusLabel = "Pending",
            targetFilePath = "settlement/batch.go",
            quotedSpan = "instead of calling time.Now() directly",
            body = "Default to the real clock when Clock is nil, so existing callers don't break.",
        ),
        PlanInlineComment(
            id = "plan-comment-2",
            authorInitials = "WL",
            authorName = "You",
            statusLabel = "Pending",
            targetFilePath = "Verification",
            quotedSpan = "go test -race -count=100 ./internal/settlement/...",
            body = "Run with -count=100 and -race to confirm the 3% flake is gone.",
        ),
    )

    public const val VEGETA_COMMAND_LINE: String =
        "vegeta attack -rate=2000/s -duration=30s \\\n  -targets=load/transfers.txt | vegeta report"

    public val rateLimiterSteps: List<CascadeStep> = listOf(
        CascadeStep(
            cascadeId = "cas-rate-limiter",
            stepIndex = 0,
            type = CortexStepType.USER_INPUT,
            status = CortexStepStatus.DONE,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 161_000L,
            userInput = "Add a per-tenant token-bucket rate limiter to POST /transfers and run load tests.",
            attachedMentions = listOf("@transfers.go", "Skill · go-testing"),
        ),
        CascadeStep(
            cascadeId = "cas-rate-limiter",
            stepIndex = 1,
            type = CortexStepType.VIEW_FILE,
            status = CortexStepStatus.DONE,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 140_000L,
            viewFile = ViewFilePayload(
                fileUri = "file:///Users/wl/code/ledger-svc/internal/router/transfers.go",
                startLine = 1,
                endLine = 96,
                totalLines = 148,
            ),
        ),
        CascadeStep(
            cascadeId = "cas-rate-limiter",
            stepIndex = 2,
            type = CortexStepType.CODE_ACTION,
            status = CortexStepStatus.DONE,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 95_000L,
            codeAction = CodeActionPayload(
                targetFileUri = "file:///Users/wl/code/ledger-svc/internal/middleware/ratelimit.go",
                description = "Add per-tenant sync.Mutex and configurable BucketTTL to Limiter.Allow",
                additions = 96,
                deletions = 4,
                startLine = 18,
                endLine = 44,
                diffPreviewLines = listOf(
                    "+    mu     sync.Mutex",
                    "+ const ttl = cfg.BucketTTL",
                    "+    b.mu.Lock(); defer b.mu.Unlock()",
                ),
            ),
        ),
        CascadeStep(
            cascadeId = "cas-rate-limiter",
            stepIndex = 3,
            type = CortexStepType.PLANNER_RESPONSE,
            status = CortexStepStatus.DONE,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 35_000L,
            plannerResponse = PlannerResponsePayload(
                response = "Plan approved with your 2 comments. Tests pass — next is a load test, which needs your OK.",
                thinking = "Addressed both review comments on Implementation Plan v2 (configurable BucketTTL and per-tenant mutex lock). Ran go test ./internal/... with 42/42 passing. Preparing vegeta load test against load/transfers.txt.",
                thinkingDurationSeconds = 14.0,
                referencedFiles = listOf("/brain/rate_limiter_plan.md", "middleware/ratelimit.go"),
            ),
        ),
        CascadeStep(
            cascadeId = "cas-rate-limiter",
            stepIndex = 4,
            type = CortexStepType.TASK_BOUNDARY,
            status = CortexStepStatus.IN_PROGRESS,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 12_000L,
            taskBoundary = TaskBoundaryPayload(
                taskName = "Task · 4 of 7 done",
                taskStatus = "Waiting for your approval · Step 5 of 7",
                taskSummary = "42 unit tests passed; awaiting Face ID confirmation for vegeta load test.",
                completedCount = 4,
                totalCount = 7,
                elapsedLabel = "2m 41s",
                checklist = listOf(
                    TaskChecklistItem(
                        id = "chk-wire-router",
                        title = "Wire limiter into router",
                        status = TaskChecklistStatus.DONE,
                        trailingBadge = null,
                    ),
                    TaskChecklistItem(
                        id = "chk-go-test",
                        title = "go test ./internal/...",
                        status = TaskChecklistStatus.DONE,
                        trailingBadge = "42 passed",
                    ),
                    TaskChecklistItem(
                        id = "chk-vegeta-load",
                        title = "Load test with vegeta",
                        status = TaskChecklistStatus.WAITING,
                        trailingBadge = null,
                    ),
                ),
            ),
        ),
        CascadeStep(
            cascadeId = "cas-rate-limiter",
            stepIndex = 5,
            type = CortexStepType.RUN_COMMAND,
            status = CortexStepStatus.WAITING,
            createdAtEpochMs = BASE_NOW_EPOCH_MS,
            runCommand = RunCommandPayload(
                commandId = "cmd-vegeta-01",
                commandLine = VEGETA_COMMAND_LINE,
                proposedCommandLine = VEGETA_COMMAND_LINE,
                cwd = "~/code/ledger-svc",
            ),
            requestedInteraction = RequestedInteraction(
                kind = RequestedInteraction.MemberKind.RUN_COMMAND,
                runCommand = RunCommandInteractionSpec(
                    proposedCommandLine = VEGETA_COMMAND_LINE,
                    cwd = "~/code/ledger-svc",
                    isDaemon = false,
                ),
                rawMemberKey = "runCommand",
            ),
        ),
    )

    public val auditQuestionSteps: List<CascadeStep> = listOf(
        CascadeStep(
            cascadeId = "cas-audit-log-admin",
            stepIndex = 0,
            type = CortexStepType.USER_INPUT,
            status = CortexStepStatus.DONE,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 600_000L,
            userInput = "Design an immutable audit log for privileged admin actions in ledger-svc.",
        ),
        CascadeStep(
            cascadeId = "cas-audit-log-admin",
            stepIndex = 1,
            type = CortexStepType.PLANNER_RESPONSE,
            status = CortexStepStatus.DONE,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 580_000L,
            plannerResponse = PlannerResponsePayload(
                response = "Before I draft the plan I need three decisions. Tap to answer — you can also reply in your own words.",
                thinking = "Identifying storage sink, auditable admin mutations, and compliance retention window.",
                thinkingDurationSeconds = 6.0,
            ),
        ),
        CascadeStep(
            cascadeId = "cas-audit-log-admin",
            stepIndex = 2,
            type = CortexStepType.EPHEMERAL_MESSAGE,
            status = CortexStepStatus.WAITING,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 575_000L,
            requestedInteraction = RequestedInteraction(
                kind = RequestedInteraction.MemberKind.ASK_QUESTION,
                askQuestion = AskQuestionInteractionSpec(
                    question = "Which admin actions should be audited?",
                    options = listOf(
                        "Account freeze / unfreeze",
                        "Limit changes",
                        "Manual ledger adjustments",
                        "Role & permission changes",
                    ),
                    isMultiSelect = true,
                ),
                rawMemberKey = "askQuestion",
            ),
        ),
    )

    public val flakySettlementSteps: List<CascadeStep> = listOf(
        CascadeStep(
            cascadeId = "cas-flaky-settlement",
            stepIndex = 0,
            type = CortexStepType.USER_INPUT,
            status = CortexStepStatus.DONE,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 520_000L,
            userInput = "Fix flaky TestSettlementBatch in CI without disabling t.Parallel().",
        ),
        CascadeStep(
            cascadeId = "cas-flaky-settlement",
            stepIndex = 1,
            type = CortexStepType.PLANNER_RESPONSE,
            status = CortexStepStatus.WAITING,
            createdAtEpochMs = BASE_NOW_EPOCH_MS - 480_000L,
            plannerResponse = PlannerResponsePayload(
                response = "The flake comes from a shared fake clock across parallel subtests in settlement_test.go. I wrote a plan to isolate it per test — review it before I change anything?",
                thinking = "Traced ~3% failure in TestSettlementBatch to concurrent Advance() calls on package-level clk.",
                thinkingDurationSeconds = 9.0,
                referencedFiles = listOf("/brain/implementation_plan.md"),
            ),
            requestedInteraction = RequestedInteraction(
                kind = RequestedInteraction.MemberKind.FILE_PERMISSION,
                filePermission = FilePermissionInteractionSpec(
                    absolutePathUri = "file:///brain/implementation_plan.md",
                    isDirectory = false,
                ),
                rawMemberKey = "filePermission",
            ),
        ),
    )

    public val artifacts: List<ArtifactSnapshot> = listOf(
        ArtifactSnapshot(
            artifactPath = "/brain/implementation_plan.md",
            title = "Implementation Plan",
            summary = "Isolate the fake clock in settlement tests",
            kind = ArtifactKind.IMPLEMENTATION_PLAN,
            content = """
                # Isolate the fake clock in settlement tests

                TestSettlementBatch fails in ~3% of CI runs. Parallel subtests share one fake clock, so `Advance()` in one subtest moves time for the others.

                ## Proposed changes
                - **MODIFY** `settlement/batch.go` — Accept a `clock.Clock` through BatchOptions instead of calling time.Now() directly.
                - **MODIFY** `settlement/settlement_test.go` — Create one clock per subtest; remove the package-level clk variable.
                - **NEW** `testutil/clock.go` — NewTestClock(t) helper, released with t.Cleanup.

                ## Verification
                - `go test -race -count=100 ./internal/settlement/...`
            """.trimIndent(),
            requestFeedback = true,
            userFacing = true,
            version = 2,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 480_000L,
        ),
        ArtifactSnapshot(
            artifactPath = "/brain/rate_limiter_plan.md",
            title = "Implementation Plan",
            summary = "Approved · 2 comments addressed",
            kind = ArtifactKind.IMPLEMENTATION_PLAN,
            content = "# Per-Tenant Rate Limiter Plan\n\nApproved · 2 comments addressed.",
            requestFeedback = false,
            userFacing = true,
            version = 2,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 120_000L,
        ),
        ArtifactSnapshot(
            artifactPath = "/brain/release_walkthrough_v2_3.md",
            title = "Walkthrough · v2.3",
            summary = "Walkthrough ready",
            kind = ArtifactKind.WALKTHROUGH,
            content = "# Release v2.3 Walkthrough\n\nAll staging verification checks passed.",
            requestFeedback = false,
            userFacing = true,
            version = 1,
            updatedAtEpochMs = BASE_NOW_EPOCH_MS - 3_500_000L,
        ),
    )

    public val diffs: List<FilePatchDiff> = listOf(
        FilePatchDiff(
            turnNumber = 3,
            filePath = "middleware/ratelimit.go",
            additions = 96,
            deletions = 4,
            hunkHeader = "@@ -18,9 +18,27 @@ Allow",
            isReviewed = false,
            lines = listOf(
                DiffLine(id = 1, kind = DiffLine.Kind.HUNK_HEADER, text = "@@ -18,9 +18,27 @@ Allow"),
                DiffLine(id = 18, kind = DiffLine.Kind.CONTEXT, oldLineNumber = 18, newLineNumber = 18, text = "type bucket struct {"),
                DiffLine(id = 19, kind = DiffLine.Kind.CONTEXT, oldLineNumber = 19, newLineNumber = 19, text = "    tokens float64"),
                DiffLine(id = 20, kind = DiffLine.Kind.CONTEXT, oldLineNumber = 20, newLineNumber = 20, text = "    last   time.Time"),
                DiffLine(id = 21, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 21, text = "    mu     sync.Mutex", wordHighlightRange = "sync.Mutex"),
                DiffLine(id = 22, kind = DiffLine.Kind.CONTEXT, oldLineNumber = 21, newLineNumber = 22, text = "}"),
                DiffLine(id = 23, kind = DiffLine.Kind.CONTEXT, oldLineNumber = 22, newLineNumber = 23, text = ""),
                DiffLine(id = 240, kind = DiffLine.Kind.DELETION, oldLineNumber = 24, newLineNumber = null, text = "const ttl = 5 * time.Minute", wordHighlightRange = "5 * time.Minute"),
                DiffLine(id = 241, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 24, text = "const ttl = cfg.BucketTTL", wordHighlightRange = "cfg.BucketTTL"),
                DiffLine(id = 25, kind = DiffLine.Kind.CONTEXT, oldLineNumber = 25, newLineNumber = 25, text = ""),
                DiffLine(id = 26, kind = DiffLine.Kind.CONTEXT, oldLineNumber = 26, newLineNumber = 26, text = "func (l *Limiter) Allow(tenant string) bool {"),
                DiffLine(id = 27, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 27, text = "    b := l.bucketFor(tenant)"),
                DiffLine(id = 28, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 28, text = "    b.mu.Lock(); defer b.mu.Unlock()"),
                DiffLine(id = 29, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 29, text = "    now := time.Now()"),
                DiffLine(id = 30, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 30, text = "    elapsed := now.Sub(b.last).Seconds()"),
                DiffLine(id = 31, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 31, text = "    b.tokens = min(l.burst, b.tokens+elapsed*l.rate)"),
            ),
        ),
        FilePatchDiff(
            turnNumber = 3,
            filePath = "router/transfers.go",
            additions = 18,
            deletions = 6,
            hunkHeader = "@@ -42,8 +42,20 @@ RegisterTransferRoutes",
            isReviewed = true,
            lines = listOf(
                DiffLine(id = 101, kind = DiffLine.Kind.HUNK_HEADER, text = "@@ -42,8 +42,20 @@ RegisterTransferRoutes"),
                DiffLine(id = 102, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 45, text = "    r.Use(middleware.RateLimit(limiter))"),
            ),
        ),
        FilePatchDiff(
            turnNumber = 2,
            filePath = "middleware/ratelimit_test.go",
            additions = 10,
            deletions = 2,
            hunkHeader = "@@ -1,6 +1,14 @@ TestLimiterAllow",
            isReviewed = true,
            lines = listOf(
                DiffLine(id = 201, kind = DiffLine.Kind.HUNK_HEADER, text = "@@ -1,6 +1,14 @@ TestLimiterAllow"),
                DiffLine(id = 202, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 12, text = "    require.True(t, lim.Allow(\"tenant-acme\"))"),
            ),
        ),
        FilePatchDiff(
            turnNumber = 1,
            filePath = "config/limits.yaml",
            additions = 4,
            deletions = 2,
            hunkHeader = "@@ -8,4 +8,6 @@ transfers:",
            isReviewed = false,
            lines = listOf(
                DiffLine(id = 301, kind = DiffLine.Kind.HUNK_HEADER, text = "@@ -8,4 +8,6 @@ transfers:"),
                DiffLine(id = 302, kind = DiffLine.Kind.ADDITION, oldLineNumber = null, newLineNumber = 10, text = "  bucket_ttl: 10m"),
            ),
        ),
    )

    public val overviewSnapshot: ConversationOverviewSnapshot = ConversationOverviewSnapshot(
        goals = listOf(
            ConversationGoalItem(
                id = "goal-ratelimit-impl",
                title = "Implement per-tenant token-bucket limiter on POST /transfers",
                isCompleted = true,
            ),
            ConversationGoalItem(
                id = "goal-vegeta-load",
                title = "Run vegeta load test and verify p99 latency < 25ms",
                isCompleted = false,
            ),
        ),
        activeSubagents = listOf(
            SubagentPayload(
                subagentId = "sub-load-analyst",
                role = "Load Test Analyst",
                typeName = "research",
                modelLabel = "Gemini 4 Hydrogen",
                status = CortexStepStatus.IN_PROGRESS,
                summary = "Preparing vegeta latency report against load/transfers.txt",
                waitingApprovalTitle = "Approve: vegeta attack...",
            ),
        ),
        backgroundTasks = listOf(
            BackgroundTaskItem(
                id = "bg-go-test-race",
                title = "go test -race ./internal/...",
                commandOrKind = "go test -race ./internal/...",
                status = CortexStepStatus.IN_PROGRESS,
                elapsedLabel = "42s",
            ),
        ),
        linkedPullRequests = listOf(
            GitHubPullRequestInfo(
                number = 418,
                title = "feat(transfers): add per-tenant rate limiter",
                url = "https://github.com/acme/ledger-svc/pull/418",
                state = "OPEN",
                checksStatus = "PASSING",
            ),
        ),
        changedFilesCount = 4,
        totalAdditions = 128,
        totalDeletions = 14,
        modifiedFiles = diffs.map { it.filePath },
        artifacts = artifacts,
        documentLinks = listOf("/brain/implementation_plan.md", "/brain/rate_limiter_plan.md"),
    )

    public val swarmBoard: SwarmBoardPayload = SwarmBoardPayload(
        swarmId = "swarm-rate-limiter",
        title = "Rate Limiter Swarm",
        members = listOf(
            SwarmMemberItem(
                name = "Lead",
                role = "Architect",
                status = CortexStepStatus.DONE,
                currentTask = "Approved token-bucket design",
            ),
            SwarmMemberItem(
                name = "Worker-Go",
                role = "Implementer",
                status = CortexStepStatus.IN_PROGRESS,
                currentTask = "Tuning per-tenant sync.Mutex & BucketTTL",
            ),
            SwarmMemberItem(
                name = "Verifier",
                role = "QA Auditor",
                status = CortexStepStatus.WAITING,
                currentTask = "Awaiting vegeta load test approval",
            ),
        ),
        posts = listOf(
            SwarmBoardPost(
                id = "post-1",
                author = "Worker-Go",
                channel = "impl",
                body = "42/42 unit tests pass under go test -race ./internal/...",
                timestampLabel = "2m ago",
            ),
            SwarmBoardPost(
                id = "post-2",
                author = "Verifier",
                channel = "qa",
                body = "Standing by to verify p99 latency once vegeta load test is approved.",
                timestampLabel = "just now",
            ),
        ),
    )

    public fun createVerificationCoordinator(): AntigravityCoreCoordinator {
        val coordinator = AntigravityCoreCoordinator()
        seedCoordinator(coordinator)
        return coordinator
    }

    public fun seedCoordinator(coordinator: AntigravityCoreCoordinator) {
        coordinator.isVerificationMode = true
        coordinator.settingsStore.setAppLanguage(AppLanguage.ENGLISH)
        coordinator.connectionStore.seedVerificationConnection(
            activeHost = macHost,
            knownHosts = hosts,
            statusText = "Demo Sandbox · Offline ESDD Fixtures",
        )
        coordinator.conversationSyncStore.seedFixtureData(
            workspaces = workspaces,
            projects = projects,
            summaries = summaries,
        )
        coordinator.chatStore.seedFixtureSteps(
            stepsByCascade = mapOf(
                "cas-rate-limiter" to rateLimiterSteps,
                "cas-audit-log-admin" to auditQuestionSteps,
                "cas-flaky-settlement" to flakySettlementSteps,
            ),
            questions = questionSteps,
            activeQuestionStepIndex = 1,
        )
        coordinator.chatStore.setActiveCascade("cas-rate-limiter")
        coordinator.chatStore.setDraftInputText(INITIAL_COMPOSER_DRAFT)
        coordinator.workspaceStore.seedFixture(
            projects = projects,
            automations = automations,
            availableRepos = availableRepos,
            contextCandidates = contextCandidates,
            attachedComposerChips = initialComposerChips,
            selectedProjectId = "ledger-svc",
            selectedProjectTab = ProjectDetailTab.ACTIVE,
        )
        coordinator.reviewStore.seedFixture(
            artifacts = artifacts,
            planChanges = planChanges,
            planComments = planComments,
            diffs = diffs,
            selectedArtifactPath = "/brain/implementation_plan.md",
            selectedDiffTurn = 3,
            selectedDiffFileIndex = 0,
            selectedDiffLineNumber = 29,
        )
        coordinator.orchestrationStore.seedFixture(
            overview = overviewSnapshot,
            swarmBoard = swarmBoard,
        )
    }

    public fun configureCoordinatorForVerifyScene(
        coordinator: AntigravityCoreCoordinator,
        scene: EsddVerifySceneCase,
    ) {
        coordinator.isVerificationMode = true
        when (scene) {
            EsddVerifySceneCase.AGENTS_HOME,
            EsddVerifySceneCase.SIDEBAR_DRAWER,
            -> {
                coordinator.chatStore.setActiveCascade("cas-rate-limiter")
                coordinator.workspaceStore.clearComposerChips()
            }
            EsddVerifySceneCase.DISPLAY_OPTIONS -> {
                coordinator.chatStore.setActiveCascade("cas-rate-limiter")
                coordinator.workspaceStore.updateDisplayOptions { it.copy(autoPinOnMessage = true) }
            }
            EsddVerifySceneCase.CONTEXT_MENU_PIN -> {
                coordinator.chatStore.setActiveCascade("cas-flaky-settlement")
            }
            EsddVerifySceneCase.PROJECT_DETAIL -> {
                coordinator.workspaceStore.selectProject("ledger-svc")
                coordinator.workspaceStore.selectProjectTab(ProjectDetailTab.ACTIVE)
                // Align ledger-svc to Active 4 / Archived 2 as depicted in UE04 (ios-project-detail / and-project)
            }
            EsddVerifySceneCase.CREATE_PROJECT -> {
                coordinator.workspaceStore.updateNewProjectDraft {
                    NewProjectDraft(selectedRepo = availableRepos.firstOrNull())
                }
            }
            EsddVerifySceneCase.AUTOMATIONS -> {
                // Uses seeded 4 automations across SCHEDULED, ALWAYS ON, and PAUSED sections
            }
            EsddVerifySceneCase.AUTOMATION_DETAIL,
            EsddVerifySceneCase.AUTOMATION_EDIT,
            -> {
                coordinator.workspaceStore.selectAutomation("auto-nightly-audit")
            }
            EsddVerifySceneCase.CHAT_AND_COMPOSER -> {
                coordinator.chatStore.setActiveCascade("cas-rate-limiter")
            }
            EsddVerifySceneCase.PERMISSIONS_PRESET,
            EsddVerifySceneCase.ADD_CONTEXT,
            -> {
                coordinator.chatStore.setActiveCascade("cas-rate-limiter")
                coordinator.workspaceStore.clearComposerChips()
            }
            EsddVerifySceneCase.SLASH_MENU -> {
                coordinator.chatStore.setActiveCascade("cas-rate-limiter")
                coordinator.workspaceStore.clearComposerChips()
                coordinator.chatStore.setDraftInputText("/")
            }
            EsddVerifySceneCase.MODEL_AND_MODE -> {
                coordinator.chatStore.setActiveCascade("cas-rate-limiter")
            }
            EsddVerifySceneCase.STRUCTURED_QUESTION -> {
                coordinator.chatStore.setActiveCascade("cas-audit-log-admin")
                coordinator.chatStore.setActiveQuestionStepIndex(1)
            }
            EsddVerifySceneCase.PLAN_REVIEW -> {
                coordinator.chatStore.setActiveCascade("cas-flaky-settlement")
                coordinator.reviewStore.selectArtifact("/brain/implementation_plan.md")
            }
            EsddVerifySceneCase.TURN_DIFF_REVIEW -> {
                coordinator.chatStore.setActiveCascade("cas-rate-limiter")
                coordinator.reviewStore.selectDiffTurn(3)
                coordinator.reviewStore.selectDiffFile(0)
                coordinator.reviewStore.selectDiffLine(29)
            }
            EsddVerifySceneCase.LIVE_ACTIVITY_SPEC -> {
                coordinator.chatStore.setActiveCascade("cas-rate-limiter")
            }
            EsddVerifySceneCase.RULES_AND_SKILLS -> {
                coordinator.workspaceStore.selectProject("ledger-svc")
            }
            EsddVerifySceneCase.SETTINGS -> {
                coordinator.chatStore.setActiveCascade("cas-rate-limiter")
            }
        }
    }
}
