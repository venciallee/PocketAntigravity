import SwiftUI
import AntigravityData

/// State `UE11_PLAN_REVIEW`: Implementation Plan Review & Inline Selection Commenting (`iOS · Implementation Plan 审阅`).
/// Features:
/// - Header `Implementation Plan` (`Fix flaky TestSettlementBatch · v2`) + `[💬 2]` badge (`plan-comments-badge`)
/// - Amber paused banner (`plan-paused-banner`: `Agent is paused until you review. Long-press any text to comment.`)
/// - H1 `Isolate the fake clock in settlement tests`
/// - `Proposed changes` with `MODIFY` (`settlement/batch.go` + amber highlight + `WL You Pending` comment card `plan-pending-comment-card`),
///   floating white `[💬 Comment | Copy]` callout (`selection-callout-comment`),
///   `MODIFY` (`settlement/settlement_test.go` + blue selection highlight),
///   `NEW` (`testutil/clock.go`), and `Verification`
/// - Sticky bottom `Proceed` (`btn-plan-proceed`) + Periwinkle `Send 2 comments` (`btn-plan-send-comments`) buttons.
public struct ImplementationPlanReviewViewController: View {
    @Bindable public var store: AntigravitySessionStore

    @State private var commentCount: Int = 2
    @State private var isAddingSelectionComment: Bool = false
    @State private var newSelectionCommentDraft: String = ""

    public init(store: AntigravitySessionStore) {
        self.store = store
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var livePlanArtifact: ArtifactSnapshot? {
        guard !store.isVerificationMode else { return nil }
        return store.activeArtifacts.first(where: { $0.artifactPath == store.selectedArtifactPath })
            ?? store.activeArtifacts.first(where: { $0.kind == .implementationPlan })
            ?? store.activeArtifacts.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            topHeaderBar

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. Amber Paused Banner
                    pausedReviewBanner

                    if let livePlan = livePlanArtifact {
                        Text(livePlan.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .fixedSize(horizontal: false, vertical: true)

                        AntigravityMarkdownView(markdown: livePlan.content, variant: .assistant)

                        if !store.planComments.isEmpty {
                            Text(lang.t("Review Comments (\(store.planComments.count))", "审阅评论（\(store.planComments.count)）"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AntigravityTheme.inkReading)
                                .padding(.top, 4)
                            ForEach(store.planComments) { comment in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(comment.authorName) · \(comment.statusLabel)")
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(AntigravityTheme.statusWaiting)
                                        Spacer()
                                        Text(comment.targetFilePath)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(AntigravityTheme.inkSecondary)
                                    }
                                    Text(comment.body)
                                        .font(.system(size: 14))
                                        .foregroundStyle(AntigravityTheme.inkReading)
                                }
                                .padding(12)
                                .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
                                )
                            }
                        }

                        if isAddingSelectionComment {
                            inlineSelectionCommentEditor
                        }
                    } else {
                        // 2. H1 Plan Title & Problem Statement (`UE11` Verification Showcase)
                        Text("Isolate the fake clock in settlement tests")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .fixedSize(horizontal: false, vertical: true)

                        problemSummaryParagraph

                        // 3. Proposed Changes Section
                        Text(lang.t("Proposed changes", "建议更改"))
                            .font(.system(size: 16.5, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .padding(.top, 2)

                        // Change 1: MODIFY settlement/batch.go + Amber Highlight + WL You Pending Card
                        batchChangeWithPendingComment

                        // Floating Inverted `[💬 Comment | Copy]` Selection Callout + Change 2
                        selectionCalloutAndSettlementTestChange

                        if isAddingSelectionComment {
                            inlineSelectionCommentEditor
                        }

                        // Change 3: NEW testutil/clock.go
                        newClockHelperChange

                        // 4. Verification Section
                        Text(lang.t("Verification", "验证方案"))
                            .font(.system(size: 16.5, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            // 5. Sticky Bottom Bar (`Proceed` + `Send comments`)
            bottomDecisionBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .background(AntigravityTheme.canvasObsidian)
        .task {
            if !store.isVerificationMode {
                await store.loadLiveArtifactsAndDiffs()
                commentCount = max(0, store.planComments.count)
            }
        }
    }

    // MARK: - 1. Top Header Bar

    private var topHeaderBar: some View {
        let subtitle = livePlanArtifact.map { "\($0.title) · v\($0.version)" }
            ?? "Fix flaky TestSettlementBatch · v2"
        return HStack(spacing: 8) {
            Button {
                store.currentRoute = .chatAndComposer
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-back-from-plan")

            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t("Implementation Plan", "实施计划"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // `[💬 N]` Comments Badge
            Button {
                isAddingSelectionComment.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(livePlanArtifact != nil ? store.planComments.count : commentCount)")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(AntigravityTheme.inkReading)
                .padding(.horizontal, 12)
                .frame(minWidth: 52, minHeight: AntigravityTheme.minTouchTargetPt)
                .background(AntigravityTheme.surfacePill)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan-comments-badge")

            Button {
                store.currentRoute = .chatAndComposer
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    // MARK: - 2. Amber Paused Banner

    private var pausedReviewBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(AntigravityTheme.statusWaiting)
                .frame(width: 8, height: 8)

            Text(lang.t(
                "Agent is paused until you review. Long-press any text to comment.",
                "代理已暂停并等待你审阅。长按任意文本即可添加评论。"
            ))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(AntigravityTheme.statusWaiting)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AntigravityTheme.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AntigravityTheme.surfaceAmberTint)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AntigravityTheme.statusWaiting.opacity(0.26), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("plan-paused-banner")
    }

    // MARK: - 3. Plan Content Blocks

    private var problemSummaryParagraph: some View {
        Text("TestSettlementBatch fails in ~3% of CI runs. Parallel subtests share one fake clock, so `Advance()` in one subtest moves time for the others.")
            .font(.system(size: 14.5))
            .foregroundStyle(AntigravityTheme.inkLabel)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var batchChangeWithPendingComment: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                changeKindBadge(label: "MODIFY", tint: AntigravityTheme.statusWaiting)
                Text("settlement/batch.go")
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkReading)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Accept a `clock.Clock` through BatchOptions")
                    .font(.system(size: 14.5))
                    .foregroundStyle(AntigravityTheme.inkLabel)

                HStack(spacing: 0) {
                    Text("instead of calling time.Now() directly")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(AntigravityTheme.statusWaiting.opacity(0.22))
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(AntigravityTheme.statusWaiting)
                                .frame(height: 1.5)
                        }
                    Text(".")
                        .font(.system(size: 14.5))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                }
            }

            // `WL You Pending` Comment Card (`plan-pending-comment-card`)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AntigravityTheme.surfaceElevated)
                            .frame(width: 24, height: 24)
                        Text("WL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                    }

                    Text(lang.t("You", "你"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(AntigravityTheme.inkReading)

                    Text(lang.t("Pending", "待发送"))
                        .font(.system(size: 13))
                        .foregroundStyle(AntigravityTheme.inkSecondary)

                    Spacer()
                }

                Text("Default to the real clock when Clock is nil, so existing callers don't break.")
                    .font(.system(size: 14))
                    .foregroundStyle(AntigravityTheme.inkLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(AntigravityTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.leading, 8)
            .accessibilityIdentifier("plan-pending-comment-card")
        }
    }

    private var selectionCalloutAndSettlementTestChange: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Floating Inverted `[💬 Comment | Copy]` Callout Pill
            HStack {
                Spacer()
                HStack(spacing: 0) {
                    Button {
                        isAddingSelectionComment = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text(lang.t("Comment", "评论"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(AntigravityTheme.pillActiveForeground)
                        .padding(.horizontal, 14)
                        .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selection-callout-comment")

                    Rectangle()
                        .fill(AntigravityTheme.pillActiveForeground.opacity(0.20))
                        .frame(width: 1, height: 22)

                    Button {
                        isAddingSelectionComment = false
                    } label: {
                        Text(lang.t("Copy", "复制"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.pillActiveForeground)
                            .padding(.horizontal, 14)
                            .frame(minWidth: 60, minHeight: AntigravityTheme.minTouchTargetPt)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selection-callout-copy")
                }
                .background(AntigravityTheme.pillActiveBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: AntigravityTheme.glassShadow, radius: 10, y: 4)
                Spacer()
            }

            HStack(spacing: 8) {
                changeKindBadge(label: "MODIFY", tint: AntigravityTheme.statusWaiting)
                Text("settlement/settlement_test.go")
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkReading)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Create one clock per subtest;")
                        .font(.system(size: 14.5))
                        .foregroundStyle(AntigravityTheme.inkLabel)

                    Text("remove the package-")
                        .font(.system(size: 14.5))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .padding(.horizontal, 3)
                        .background(AntigravityTheme.accentPeriwinkle.opacity(0.28))
                }

                HStack(spacing: 0) {
                    Text("level clk variable")
                        .font(.system(size: 14.5))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .padding(.horizontal, 3)
                        .background(AntigravityTheme.accentPeriwinkle.opacity(0.28))
                    Text(".")
                        .font(.system(size: 14.5))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                }
            }
        }
    }

    private var inlineSelectionCommentEditor: some View {
        HStack(spacing: 8) {
            TextField(lang.t("Comment on selected span...", "评论所选片段…"), text: $newSelectionCommentDraft)
                .font(.system(size: 14))
                .foregroundStyle(AntigravityTheme.inkReading)
                .padding(.horizontal, 12)
                .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                .background(AntigravityTheme.surfaceInput)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                if !newSelectionCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    commentCount += 1
                    newSelectionCommentDraft = ""
                }
                isAddingSelectionComment = false
            } label: {
                Text(lang.t("Save", "保存"))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                    .padding(.horizontal, 14)
                    .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                    .background(AntigravityTheme.accentPeriwinkle)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var newClockHelperChange: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                changeKindBadge(label: "NEW", tint: AntigravityTheme.statusDone)
                Text("testutil/clock.go")
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkReading)
            }

            Text("NewTestClock(t) helper, released with t.Cleanup.")
                .font(.system(size: 14.5))
                .foregroundStyle(AntigravityTheme.inkLabel)
        }
    }

    private func changeKindBadge(label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - 4. Sticky Bottom Bar

    private var bottomDecisionBar: some View {
        HStack(spacing: 12) {
            Button {
                if let firstPath = store.activeArtifacts.first?.artifactPath {
                    store.approveArtifactPlan(artifactPath: firstPath)
                }
                store.currentRoute = .chatAndComposer
            } label: {
                Text(lang.t("Proceed", "继续执行"))
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AntigravityTheme.surfacePill)
                    .overlay(
                        Capsule()
                            .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-plan-proceed")

            Button {
                store.composerDraftText = "Plan review: submitted \(commentCount) inline comments."
                store.sendCurrentDraft()
                store.currentRoute = .chatAndComposer
            } label: {
                Text(lang.t("Send \(commentCount) comments", "发送 \(commentCount) 条评论"))
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AntigravityTheme.accentPeriwinkle)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-plan-send-comments")
        }
    }
}
