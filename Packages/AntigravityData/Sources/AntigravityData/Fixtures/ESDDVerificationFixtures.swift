import Foundation

/// Deterministic offline ESDD fixtures and scene routing for UE01..UE13 verification.
extension AntigravitySessionStore {
    internal static let esddFixtureProjectIds: Set<String> = ["ledger-svc", "web-console"]
    internal static let esddFixtureCascadeIds: Set<String> = [
        "cas-rate-limiter",
        "cas-release-checklist",
        "cas-flaky-settlement",
        "cas-upgrade-go",
        "cas-idempotency-payouts",
        "cas-pgx-v5-migration",
        "cas-audit-csp-headers",
        "cas-audit-log-admin"
    ]
    internal static let esddFixtureAutomationIds: Set<String> = [
        "auto-nightly-audit",
        "auto-weekly-flaky",
        "auto-pr-triage",
        "auto-bundle-size"
    ]


    // MARK: - Deterministic Scene Routing Helper (`UE01` .. `UE13`)

    public func configureForVerifyScene(_ scene: ESDDVerifySceneCase) {
        isVerificationMode = true
        isInitialSessionCheckComplete = true
        presentedSheet = nil
        switch scene {
        case .agentsHome:
            selectedTab = .agents
            activeRoute = .tabRoot
        case .displayOptions:
            selectedTab = .agents
            activeRoute = .tabRoot
            presentedSheet = .displayOptions
            isSortPopoverPresented = true
        case .contextMenuPin:
            selectedTab = .agents
            activeRoute = .tabRoot
            contextMenuTargetCascadeId = "cas-flaky-settlement"
            swipePreviewCascadeId = "cas-upgrade-go"
            presentedSheet = .contextMenuPreview(cascadeId: "cas-flaky-settlement")
        case .projectDetail:
            selectedTab = .agents
            selectedProjectId = "ledger-svc"
            selectedProjectTab = .active
            // Align ledger-svc to Active 3 / Archived 2 (5 conversations) as depicted in UE04
            if let idx = summaries.firstIndex(where: { $0.cascadeId == "cas-idempotency-payouts" }) {
                summaries[idx].isArchived = true
            }
            summaries.removeAll { $0.cascadeId == "cas-pgx-v5-migration" }
            activeRoute = .projectDetail("ledger-svc")
        case .createProject:
            selectedTab = .agents
            activeRoute = .tabRoot
            presentedSheet = .createProject
        case .automations:
            selectedTab = .automations
            activeRoute = .tabRoot
        case .chatAndComposer:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            activeRoute = .cascadeChat("cas-rate-limiter")
        case .addContext:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            activeRoute = .cascadeChat("cas-rate-limiter")
            presentedSheet = .addContext
        case .modelAndMode:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            activeRoute = .cascadeChat("cas-rate-limiter")
            presentedSheet = .modelAndMode
        case .structuredQuestion:
            selectedTab = .agents
            activeCascadeId = "cas-audit-log-admin"
            activeQuestionStepIndex = 1
            activeRoute = .cascadeChat("cas-audit-log-admin")
        case .planReview:
            selectedTab = .agents
            activeCascadeId = "cas-flaky-settlement"
            selectedArtifactPath = "/brain/implementation_plan.md"
            activeRoute = .planReview
        case .turnDiffReview:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            selectedDiffTurn = 3
            selectedDiffFileIndex = 0
            selectedDiffLineNumber = 29
            activeRoute = .turnDiffReview
        case .liveActivitySpec:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            activeRoute = .cascadeChat("cas-rate-limiter")
        }
    }

    // MARK: - Deterministic 1:1 UE Fixture Factory (`UE01` .. `UE13`)

    public static func makeESDDVerificationStore() -> AntigravitySessionStore {
        let macHost = RemoteHostInstance(
            instanceId: "macbook-pro-local",
            hostname: "MacBook Pro",
            version: "v2.32.0",
            channel: .directHost,
            endpointURL: URL(string: "https://127.0.0.1:42100")!,
            isOnline: true,
            latencyMs: 6
        )
        let cloudHost = RemoteHostInstance(
            instanceId: "cloud-vm-us-central1",
            hostname: "Cloud",
            version: "v2.32.0",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/cloud-vm-us-central1")!,
            isOnline: true,
            latencyMs: 24
        )

        let projects: [ProjectWorkspace] = [
            ProjectWorkspace(
                id: "ledger-svc",
                name: "ledger-svc",
                pathDisplay: "~/code/ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                runtime: .macBookPro,
                hostName: "MacBook Pro",
                activeBranch: "main",
                worktrees: ["main", "feat/ratelimit", "fix/settlement-clock"],
                isExpandedInHome: true,
                rulesAndSkillsCount: 4
            ),
            ProjectWorkspace(
                id: "web-console",
                name: "web-console",
                pathDisplay: "cloud://acme/web-console",
                workspaceUri: "cloud://acme/web-console",
                runtime: .cloud,
                hostName: "Cloud",
                activeBranch: "main",
                worktrees: ["main", "feat/dark-mode"],
                isExpandedInHome: true,
                rulesAndSkillsCount: 3
            )
        ]

        let workspaces: [WorkspaceInfo] = [
            WorkspaceInfo(
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                displayName: "ledger-svc",
                activeBranch: "main",
                worktrees: ["main", "feat/ratelimit", "fix/settlement-clock"],
                activeCascadeCount: 3,
                indexedFiles: [
                    "internal/middleware/ratelimit.go",
                    "internal/router/transfers.go",
                    "internal/settlement/batch.go",
                    "internal/settlement/settlement_test.go",
                    "load/transfers.txt"
                ]
            ),
            WorkspaceInfo(
                workspaceUri: "cloud://acme/web-console",
                displayName: "web-console",
                activeBranch: "main",
                worktrees: ["main", "feat/dark-mode"],
                activeCascadeCount: 2,
                indexedFiles: [
                    "src/pages/settings/DarkModeToggle.tsx",
                    "src/theme/tokens.ts"
                ]
            )
        ]

        let baseNow = Date(timeIntervalSince1970: 1_762_793_357)
        let summaries: [CascadeSummary] = [
            CascadeSummary(
                cascadeId: "cas-rate-limiter",
                title: "Add rate limiter to /transfers",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .inProgress,
                stepCount: 28,
                currentStepIndex: 4,
                totalSteps: 7,
                updatedAt: baseNow,
                relativeTimeLabel: "now",
                statusSubtitle: "Running · Step 4 of 7 · go test ./internal/...",
                isPinned: true,
                isArchived: false,
                isUnread: false,
                modelLabel: "Gemini 3.1 Pro",
                pendingInteractionTitle: "Approve: vegeta attack...",
                lastMessagePreview: "Plan approved with your 2 comments. Tests pass — next is a load test, which needs your OK.",
                totalAdditions: 128,
                totalDeletions: 14
            ),
            CascadeSummary(
                cascadeId: "cas-flaky-settlement",
                title: "Fix flaky TestSettlementBatch",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .waiting,
                stepCount: 12,
                currentStepIndex: 2,
                totalSteps: 5,
                updatedAt: baseNow.addingTimeInterval(-480),
                relativeTimeLabel: "8m",
                statusSubtitle: "Needs review · Implementation plan ready",
                isPinned: false,
                isArchived: false,
                isUnread: true,
                modelLabel: "Gemini 3.1 Pro",
                pendingInteractionTitle: "Awaiting review · Implementation Plan",
                lastMessagePreview: "The flake comes from a shared fake clock across parallel subtests in settlement_test.go. I wrote a plan to isolate it per test — review it before I change anything?",
                totalAdditions: 0,
                totalDeletions: 0
            ),
            CascadeSummary(
                cascadeId: "cas-release-checklist",
                title: "Release checklist v2.3",
                projectSlug: "web-console",
                workspaceUri: "cloud://acme/web-console",
                branchName: "main",
                status: .done,
                stepCount: 19,
                currentStepIndex: 5,
                totalSteps: 5,
                updatedAt: baseNow.addingTimeInterval(-3500),
                relativeTimeLabel: "1h",
                statusSubtitle: "Done · Walkthrough ready",
                isPinned: true,
                isArchived: false,
                isUnread: false,
                modelLabel: "Gemini 3.8 Flash",
                lastMessagePreview: "All v2.3 release checks succeeded and walkthrough artifact is ready.",
                totalAdditions: 34,
                totalDeletions: 8
            ),
            CascadeSummary(
                cascadeId: "cas-upgrade-go",
                title: "Upgrade to Go 1.25",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .done,
                stepCount: 31,
                currentStepIndex: 6,
                totalSteps: 6,
                updatedAt: baseNow.addingTimeInterval(-3600),
                relativeTimeLabel: "1h",
                statusSubtitle: "Done · 6 files changed",
                isPinned: false,
                isArchived: false,
                isUnread: true,
                modelLabel: "Gemini 3.1 Pro",
                lastMessagePreview: "Updated go.mod toolchain to Go 1.25 across 6 packages.",
                totalAdditions: 42,
                totalDeletions: 31
            ),
            CascadeSummary(
                cascadeId: "cas-dark-mode-cloud",
                title: "Dark mode for settings page",
                projectSlug: "web-console",
                workspaceUri: "cloud://acme/web-console",
                branchName: "feat/dark-mode",
                status: .inProgress,
                stepCount: 9,
                currentStepIndex: 2,
                totalSteps: 5,
                updatedAt: baseNow.addingTimeInterval(-7200),
                relativeTimeLabel: "12:04",
                statusSubtitle: "Running in cloud · Step 2 of 5",
                isPinned: false,
                isArchived: false,
                isUnread: true,
                modelLabel: "Gemini 3.8 Flash",
                lastMessagePreview: "Applying semantic obsidian tokens to SettingsView...",
                totalAdditions: 64,
                totalDeletions: 21
            ),
            CascadeSummary(
                cascadeId: "cas-idempotency-payouts",
                title: "Idempotency keys for payouts",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .done,
                stepCount: 45,
                currentStepIndex: 8,
                totalSteps: 8,
                updatedAt: baseNow.addingTimeInterval(-86400),
                relativeTimeLabel: "Yesterday",
                statusSubtitle: "Done · Merged into main",
                isPinned: false,
                isArchived: false,
                isUnread: false,
                modelLabel: "Gemini 3.1 Pro",
                lastMessagePreview: "Merged payout idempotency key store into main.",
                totalAdditions: 210,
                totalDeletions: 19
            ),
            CascadeSummary(
                cascadeId: "cas-audit-log-admin",
                title: "Audit log for admin actions",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .waiting,
                stepCount: 3,
                currentStepIndex: 2,
                totalSteps: 3,
                updatedAt: baseNow.addingTimeInterval(-172_800),
                relativeTimeLabel: "2d",
                statusSubtitle: "Archived · Planning",
                isPinned: false,
                isArchived: true,
                isUnread: false,
                modelLabel: "Gemini 3.1 Pro",
                lastMessagePreview: "Before I draft the plan I need three decisions. Tap to answer — you can also reply in your own words."
            ),
            CascadeSummary(
                cascadeId: "cas-pgx-v5-migration",
                title: "Migrate settlement store to pgx v5",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .done,
                stepCount: 37,
                currentStepIndex: 6,
                totalSteps: 6,
                updatedAt: baseNow.addingTimeInterval(-345_600),
                relativeTimeLabel: "4d",
                statusSubtitle: "Archived · Merged",
                isPinned: false,
                isArchived: true,
                isUnread: false,
                modelLabel: "Gemini 3.1 Pro",
                lastMessagePreview: "Completed pgxpool v5 batch migration."
            )
        ]

        let automations: [AutomationItem] = [
            AutomationItem(
                id: "auto-nightly-audit",
                title: "Nightly dependency audit",
                projectSlug: "ledger-svc",
                scheduleSummary: "ledger-svc · Daily at 02:00 · Flash",
                section: .scheduled,
                nextRunText: "Tonight, 02:00",
                lastRunText: "Succeeded · 22h ago",
                needsReview: false,
                isRunningNow: false
            ),
            AutomationItem(
                id: "auto-weekly-flaky",
                title: "Weekly flaky-test report",
                projectSlug: "ledger-svc",
                scheduleSummary: "ledger-svc · Mondays at 09:00 · Pro",
                section: .scheduled,
                nextRunText: "Mon, 09:00",
                lastRunText: "Needs review · 2d",
                needsReview: true,
                isRunningNow: false
            ),
            AutomationItem(
                id: "auto-pr-triage",
                title: "Triage new pull requests",
                projectSlug: "web-console",
                scheduleSummary: "web-console · On PR opened · Flash Lite",
                section: .alwaysOn,
                nextRunText: "On PR opened",
                lastRunText: "Last run 14m ago",
                needsReview: false,
                isRunningNow: false
            ),
            AutomationItem(
                id: "auto-bundle-size",
                title: "Bundle size watch",
                projectSlug: "web-console",
                scheduleSummary: "web-console · Daily at 08:00 · Flash",
                section: .paused,
                nextRunText: "Paused",
                lastRunText: "Paused · 5d ago",
                needsReview: false,
                isRunningNow: false
            )
        ]

        let contextCandidates: [ContextCandidateItem] = [
            ContextCandidateItem(
                id: "ctx-ratelimit",
                category: .files,
                title: "ratelimit.go",
                subtitle: "internal/middleware · changed this turn",
                chipLabel: "@ratelimit.go",
                isActionTrigger: false,
                isSelected: true
            ),
            ContextCandidateItem(
                id: "ctx-load-folder",
                category: .folder,
                title: "load/",
                subtitle: "Folder · 3 files",
                chipLabel: "@load/",
                isActionTrigger: false,
                isSelected: false
            ),
            ContextCandidateItem(
                id: "ctx-idempotency-conv",
                category: .mentions,
                title: "Idempotency keys for payouts",
                subtitle: "Conversation · ledger-svc",
                chipLabel: "@Idempotency keys for payouts",
                isActionTrigger: false,
                isSelected: true
            ),
            ContextCandidateItem(
                id: "ctx-terminal-last-test",
                category: .mentions,
                title: "Terminal · last test run",
                subtitle: "Output · 214 lines",
                chipLabel: "@terminal:last-test",
                isActionTrigger: false,
                isSelected: false
            ),
            ContextCandidateItem(
                id: "ctx-action-boost",
                category: .actions,
                title: "/boost",
                subtitle: "Action · extra multi-agent reasoning pass",
                chipLabel: "/boost",
                isActionTrigger: true,
                isSelected: false
            ),
            ContextCandidateItem(
                id: "ctx-skill-go-testing",
                category: .skills,
                title: "go-testing",
                subtitle: "Skill · table-driven tests, -race, golden files",
                chipLabel: "Skill · go-testing",
                isActionTrigger: false,
                isSelected: true
            )
        ]

        let questionSteps: [StructuredQuestionStepItem] = [
            StructuredQuestionStepItem(
                id: "q-step-1-storage",
                stepNumber: 1,
                shortTabTitle: "Storage",
                questionTitle: "Where should admin audit events be persisted?",
                options: [
                    "Dedicated audit_events Postgres table",
                    "Append-only Kafka audit topic",
                    "Daily S3 Parquet archive"
                ],
                selectedOptions: ["Dedicated audit_events Postgres table"],
                customWriteIn: "",
                isCompleted: true,
                isMultiSelect: false
            ),
            StructuredQuestionStepItem(
                id: "q-step-2-actions",
                stepNumber: 2,
                shortTabTitle: "Actions",
                questionTitle: "Which admin actions should be audited?",
                options: [
                    "Account freeze / unfreeze",
                    "Limit changes",
                    "Manual ledger adjustments",
                    "Role & permission changes"
                ],
                selectedOptions: [
                    "Account freeze / unfreeze",
                    "Limit changes",
                    "Manual ledger adjustments"
                ],
                customWriteIn: "",
                isCompleted: false,
                isMultiSelect: true
            ),
            StructuredQuestionStepItem(
                id: "q-step-3-retention",
                stepNumber: 3,
                shortTabTitle: "Retention",
                questionTitle: "How long should audit entries be retained?",
                options: [
                    "90 days hot + 7 years cold compliance archive",
                    "1 year hot Postgres",
                    "Indefinite immutable retention"
                ],
                selectedOptions: ["90 days hot + 7 years cold compliance archive"],
                customWriteIn: "",
                isCompleted: false,
                isMultiSelect: false
            )
        ]

        let planChanges: [PlanProposedFileChange] = [
            PlanProposedFileChange(
                id: "plan-change-batch",
                changeKind: "MODIFY",
                filePath: "settlement/batch.go",
                summaryText: "Accept a clock.Clock through BatchOptions instead of calling time.Now() directly.",
                highlightedSpan: "instead of calling time.Now() directly",
                isSelectedForCallout: false
            ),
            PlanProposedFileChange(
                id: "plan-change-test",
                changeKind: "MODIFY",
                filePath: "settlement/settlement_test.go",
                summaryText: "Create one clock per subtest; remove the package-level clk variable.",
                highlightedSpan: "remove the package-level clk variable",
                isSelectedForCallout: true
            ),
            PlanProposedFileChange(
                id: "plan-change-clock",
                changeKind: "NEW",
                filePath: "testutil/clock.go",
                summaryText: "NewTestClock(t) helper, released with t.Cleanup.",
                highlightedSpan: nil,
                isSelectedForCallout: false
            )
        ]

        let planComments: [PlanInlineComment] = [
            PlanInlineComment(
                id: "plan-comment-1",
                authorInitials: "WL",
                authorName: "You",
                statusLabel: "Pending",
                targetFilePath: "settlement/batch.go",
                quotedSpan: "instead of calling time.Now() directly",
                body: "Default to the real clock when Clock is nil, so existing callers don't break."
            ),
            PlanInlineComment(
                id: "plan-comment-2",
                authorInitials: "WL",
                authorName: "You",
                statusLabel: "Pending",
                targetFilePath: "Verification",
                quotedSpan: "go test -race -count=100 ./internal/settlement/...",
                body: "Run with -count=100 and -race to confirm the 3% flake is gone."
            )
        ]

        let vegetaCmd = "vegeta attack -rate=2000/s -duration=30s \\\n  -targets=load/transfers.txt | vegeta report"
        let rateLimiterSteps: [CascadeStep] = [
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 0,
                type: .userInput,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-161),
                userInput: "Add a per-tenant token-bucket rate limiter to POST /transfers and run load tests.",
                attachedMentions: ["@transfers.go", "Skill · go-testing"]
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 1,
                type: .viewFile,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-140),
                viewFile: ViewFilePayload(
                    fileUri: "file:///Users/wl/code/ledger-svc/internal/router/transfers.go",
                    startLine: 1,
                    endLine: 96,
                    totalLines: 148
                )
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 2,
                type: .codeAction,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-95),
                codeAction: CodeActionPayload(
                    targetFileUri: "file:///Users/wl/code/ledger-svc/internal/middleware/ratelimit.go",
                    description: "Add per-tenant sync.Mutex and configurable BucketTTL to Limiter.Allow",
                    additions: 96,
                    deletions: 4,
                    startLine: 18,
                    endLine: 44,
                    diffPreviewLines: [
                        "+    mu     sync.Mutex",
                        "+ const ttl = cfg.BucketTTL",
                        "+    b.mu.Lock(); defer b.mu.Unlock()"
                    ]
                )
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 3,
                type: .plannerResponse,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-35),
                plannerResponse: PlannerResponsePayload(
                    response: "Plan approved with your 2 comments. Tests pass — next is a load test, which needs your OK.",
                    thinking: "Addressed both review comments on Implementation Plan v2 (configurable BucketTTL and per-tenant mutex lock). Ran go test ./internal/... with 42/42 passing. Preparing vegeta load test against load/transfers.txt.",
                    thinkingDurationSeconds: 14.0,
                    referencedFiles: ["/brain/rate_limiter_plan.md", "middleware/ratelimit.go"]
                )
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 4,
                type: .taskBoundary,
                status: .inProgress,
                createdAt: baseNow.addingTimeInterval(-12),
                taskBoundary: TaskBoundaryPayload(
                    taskName: "Task · 4 of 7 done",
                    taskStatus: "Waiting for your approval · Step 5 of 7",
                    taskSummary: "42 unit tests passed; awaiting Face ID confirmation for vegeta load test.",
                    completedCount: 4,
                    totalCount: 7,
                    elapsedLabel: "2m 41s",
                    checklist: [
                        TaskChecklistItem(
                            id: "chk-wire-router",
                            title: "Wire limiter into router",
                            status: .done,
                            trailingBadge: nil
                        ),
                        TaskChecklistItem(
                            id: "chk-go-test",
                            title: "go test ./internal/...",
                            status: .done,
                            trailingBadge: "42 passed"
                        ),
                        TaskChecklistItem(
                            id: "chk-vegeta-load",
                            title: "Load test with vegeta",
                            status: .waiting,
                            trailingBadge: nil
                        )
                    ]
                )
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 5,
                type: .runCommand,
                status: .waiting,
                createdAt: baseNow,
                runCommand: RunCommandPayload(
                    commandId: "cmd-vegeta-01",
                    commandLine: vegetaCmd,
                    proposedCommandLine: vegetaCmd,
                    cwd: "~/code/ledger-svc"
                ),
                requestedInteraction: RequestedInteraction(
                    kind: .runCommand,
                    runCommand: RunCommandInteractionSpec(
                        proposedCommandLine: vegetaCmd,
                        cwd: "~/code/ledger-svc",
                        isDaemon: false
                    )
                )
            )
        ]

        let auditQuestionSteps: [CascadeStep] = [
            CascadeStep(
                cascadeId: "cas-audit-log-admin",
                stepIndex: 0,
                type: .userInput,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-600),
                userInput: "Design an immutable audit log for privileged admin actions in ledger-svc."
            ),
            CascadeStep(
                cascadeId: "cas-audit-log-admin",
                stepIndex: 1,
                type: .plannerResponse,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-580),
                plannerResponse: PlannerResponsePayload(
                    response: "Before I draft the plan I need three decisions. Tap to answer — you can also reply in your own words.",
                    thinking: "Identifying storage sink, auditable admin mutations, and compliance retention window.",
                    thinkingDurationSeconds: 6.0
                )
            ),
            CascadeStep(
                cascadeId: "cas-audit-log-admin",
                stepIndex: 2,
                type: .ephemeralMessage,
                status: .waiting,
                createdAt: baseNow.addingTimeInterval(-575),
                requestedInteraction: RequestedInteraction(
                    kind: .askQuestion,
                    askQuestion: AskQuestionInteractionSpec(
                        question: "Which admin actions should be audited?",
                        options: [
                            "Account freeze / unfreeze",
                            "Limit changes",
                            "Manual ledger adjustments",
                            "Role & permission changes"
                        ],
                        isMultiSelect: true
                    )
                )
            )
        ]

        let flakySettlementSteps: [CascadeStep] = [
            CascadeStep(
                cascadeId: "cas-flaky-settlement",
                stepIndex: 0,
                type: .userInput,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-520),
                userInput: "Fix flaky TestSettlementBatch in CI without disabling t.Parallel()."
            ),
            CascadeStep(
                cascadeId: "cas-flaky-settlement",
                stepIndex: 1,
                type: .plannerResponse,
                status: .waiting,
                createdAt: baseNow.addingTimeInterval(-480),
                plannerResponse: PlannerResponsePayload(
                    response: "The flake comes from a shared fake clock across parallel subtests in settlement_test.go. I wrote a plan to isolate it per test — review it before I change anything?",
                    thinking: "Traced ~3% failure in TestSettlementBatch to concurrent Advance() calls on package-level clk.",
                    thinkingDurationSeconds: 9.0,
                    referencedFiles: ["/brain/implementation_plan.md"]
                ),
                requestedInteraction: RequestedInteraction(
                    kind: .filePermission,
                    filePermission: FilePermissionInteractionSpec(
                        absolutePathUri: "file:///brain/implementation_plan.md",
                        isDirectory: false
                    )
                )
            )
        ]

        let artifacts: [ArtifactSnapshot] = [
            ArtifactSnapshot(
                artifactPath: "/brain/implementation_plan.md",
                title: "Implementation Plan",
                summary: "Isolate the fake clock in settlement tests",
                kind: .implementationPlan,
                content: """
                # Isolate the fake clock in settlement tests

                TestSettlementBatch fails in ~3% of CI runs. Parallel subtests share one fake clock, so `Advance()` in one subtest moves time for the others.

                ## Proposed changes
                - **MODIFY** `settlement/batch.go` — Accept a `clock.Clock` through BatchOptions instead of calling time.Now() directly.
                - **MODIFY** `settlement/settlement_test.go` — Create one clock per subtest; remove the package-level clk variable.
                - **NEW** `testutil/clock.go` — NewTestClock(t) helper, released with t.Cleanup.

                ## Verification
                - `go test -race -count=100 ./internal/settlement/...`
                """,
                requestFeedback: true,
                userFacing: true,
                version: 2,
                updatedAt: baseNow.addingTimeInterval(-480)
            ),
            ArtifactSnapshot(
                artifactPath: "/brain/rate_limiter_plan.md",
                title: "Implementation Plan",
                summary: "Approved · 2 comments addressed",
                kind: .implementationPlan,
                content: "# Per-Tenant Rate Limiter Plan\n\nApproved · 2 comments addressed.",
                requestFeedback: false,
                userFacing: true,
                version: 2,
                updatedAt: baseNow.addingTimeInterval(-120)
            ),
            ArtifactSnapshot(
                artifactPath: "/brain/release_walkthrough_v2_3.md",
                title: "Walkthrough · v2.3",
                summary: "Walkthrough ready",
                kind: .walkthrough,
                content: "# Release v2.3 Walkthrough\n\nAll staging verification checks passed.",
                requestFeedback: false,
                userFacing: true,
                version: 1,
                updatedAt: baseNow.addingTimeInterval(-3500)
            )
        ]

        let diffs: [FilePatchDiff] = [
            FilePatchDiff(
                turnNumber: 3,
                filePath: "middleware/ratelimit.go",
                additions: 96,
                deletions: 4,
                hunkHeader: "@@ -18,9 +18,27 @@ Allow",
                isReviewed: false,
                lines: [
                    DiffLine(id: 1, kind: .hunkHeader, text: "@@ -18,9 +18,27 @@ Allow"),
                    DiffLine(id: 18, kind: .context, oldLineNumber: 18, newLineNumber: 18, text: "type bucket struct {"),
                    DiffLine(id: 19, kind: .context, oldLineNumber: 19, newLineNumber: 19, text: "    tokens float64"),
                    DiffLine(id: 20, kind: .context, oldLineNumber: 20, newLineNumber: 20, text: "    last   time.Time"),
                    DiffLine(id: 21, kind: .addition, oldLineNumber: nil, newLineNumber: 21, text: "    mu     sync.Mutex", wordHighlightRange: "sync.Mutex"),
                    DiffLine(id: 22, kind: .context, oldLineNumber: 21, newLineNumber: 22, text: "}"),
                    DiffLine(id: 23, kind: .context, oldLineNumber: 22, newLineNumber: 23, text: ""),
                    DiffLine(id: 240, kind: .deletion, oldLineNumber: 24, newLineNumber: nil, text: "const ttl = 5 * time.Minute", wordHighlightRange: "5 * time.Minute"),
                    DiffLine(id: 241, kind: .addition, oldLineNumber: nil, newLineNumber: 24, text: "const ttl = cfg.BucketTTL", wordHighlightRange: "cfg.BucketTTL"),
                    DiffLine(id: 25, kind: .context, oldLineNumber: 25, newLineNumber: 25, text: ""),
                    DiffLine(id: 26, kind: .context, oldLineNumber: 26, newLineNumber: 26, text: "func (l *Limiter) Allow(tenant string) bool {"),
                    DiffLine(id: 27, kind: .addition, oldLineNumber: nil, newLineNumber: 27, text: "    b := l.bucketFor(tenant)"),
                    DiffLine(id: 28, kind: .addition, oldLineNumber: nil, newLineNumber: 28, text: "    b.mu.Lock(); defer b.mu.Unlock()"),
                    DiffLine(id: 29, kind: .addition, oldLineNumber: nil, newLineNumber: 29, text: "    now := time.Now()"),
                    DiffLine(id: 30, kind: .addition, oldLineNumber: nil, newLineNumber: 30, text: "    elapsed := now.Sub(b.last).Seconds()"),
                    DiffLine(id: 31, kind: .addition, oldLineNumber: nil, newLineNumber: 31, text: "    b.tokens = min(l.burst, b.tokens+elapsed*l.rate)")
                ]
            ),
            FilePatchDiff(
                turnNumber: 3,
                filePath: "router/transfers.go",
                additions: 18,
                deletions: 6,
                hunkHeader: "@@ -42,8 +42,20 @@ RegisterTransferRoutes",
                isReviewed: true,
                lines: [
                    DiffLine(id: 101, kind: .hunkHeader, text: "@@ -42,8 +42,20 @@ RegisterTransferRoutes"),
                    DiffLine(id: 102, kind: .addition, oldLineNumber: nil, newLineNumber: 45, text: "    r.Use(middleware.RateLimit(limiter))")
                ]
            ),
            FilePatchDiff(
                turnNumber: 2,
                filePath: "middleware/ratelimit_test.go",
                additions: 10,
                deletions: 2,
                hunkHeader: "@@ -1,6 +1,14 @@ TestLimiterAllow",
                isReviewed: true,
                lines: [
                    DiffLine(id: 201, kind: .hunkHeader, text: "@@ -1,6 +1,14 @@ TestLimiterAllow"),
                    DiffLine(id: 202, kind: .addition, oldLineNumber: nil, newLineNumber: 12, text: "    require.True(t, lim.Allow(\"tenant-acme\"))")
                ]
            ),
            FilePatchDiff(
                turnNumber: 1,
                filePath: "config/limits.yaml",
                additions: 4,
                deletions: 2,
                hunkHeader: "@@ -8,4 +8,6 @@ transfers:",
                isReviewed: false,
                lines: [
                    DiffLine(id: 301, kind: .hunkHeader, text: "@@ -8,4 +8,6 @@ transfers:"),
                    DiffLine(id: 302, kind: .addition, oldLineNumber: nil, newLineNumber: 10, text: "  bucket_ttl: 10m")
                ]
            )
        ]

        let store = AntigravitySessionStore(
            hosts: [macHost, cloudHost],
            activeHost: macHost,
            projects: projects,
            workspaces: workspaces,
            selectedWorkspaceUri: workspaces[0].workspaceUri,
            summaries: summaries,
            automations: automations,
            contextCandidates: contextCandidates,
            questionSteps: questionSteps,
            activeQuestionStepIndex: 1,
            planChanges: planChanges,
            planComments: planComments,
            activeCascadeId: "cas-rate-limiter",
            stepsByCascadeId: [
                "cas-rate-limiter": rateLimiterSteps,
                "cas-audit-log-admin": auditQuestionSteps,
                "cas-flaky-settlement": flakySettlementSteps
            ],
            activeArtifacts: artifacts,
            activeTurnDiffs: diffs,
            selectedDiffTurn: 3,
            selectedDiffFileIndex: 0,
            activeLineCommentDraft: "Use l.clock.Now() — the plan says to inject the clock so tests can control time.",
            selectedModelConfig: CascadeModelConfig.catalog[0],
            secretStore: InMemorySecretStore(),
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(),
            preferencesStore: InMemoryPreferencesStore()
        )
        store.isVerificationMode = true
        store.isInitialSessionCheckComplete = true
        store.connectionStatusText = "Demo Sandbox · Offline ESDD Fixtures"
        store.composerAttachments = [
            ComposerAttachmentChip(
                id: "chip-ratelimit",
                kind: .fileMention,
                label: "@ratelimit.go",
                targetUri: "file:///Users/wl/code/ledger-svc/internal/middleware/ratelimit.go"
            )
        ]
        store.composerDraftText = "Use 1000/s instead — staging is smaller than prod."
        return store
    }
}
