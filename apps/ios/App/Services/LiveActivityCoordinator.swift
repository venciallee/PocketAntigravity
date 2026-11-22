import Foundation
import AntigravityData
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Synchronizes active `AntigravitySessionStore` agent runs into real iOS Dynamic Island
/// and Lock Screen Live Activities (`Activity<AntigravityActivityAttributes>`).
@MainActor
public final class LiveActivityCoordinator {
    public static let shared = LiveActivityCoordinator()

    private var activeCascadeId: String? = nil

    private init() {}

    public func sync(with store: AntigravitySessionStore) {
        guard !store.isVerificationMode else { return }
        #if canImport(ActivityKit) && os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let summary = store.summaries.first(where: { $0.status == .waiting || $0.status == .inProgress })
                ?? store.activeSummary else {
            endAllActivities()
            return
        }

        let isRunningOrWaiting = (summary.status == .inProgress || summary.status == .waiting || summary.status == .pending)
        let pendingWaiting = store.pendingWaitingStep
        let pendingReq = pendingWaiting?.effectiveRequestedInteraction
        let permLabel: String? = pendingReq?.permission.map { "\($0.action)(\($0.target))" }
        let pendingCmdCandidates: [String?] = [
            pendingWaiting?.runCommand?.proposedCommandLine,
            pendingWaiting?.runCommand?.commandLine,
            permLabel,
            pendingReq?.filePermission?.absolutePathUri,
            pendingReq?.mcpToolName,
            pendingReq?.askQuestion?.question,
            pendingReq?.rawSummary,
            summary.pendingInteractionTitle
        ]
        let pendingCmd: String? = pendingCmdCandidates.compactMap { $0 }.first(where: { !$0.isEmpty })

        let contentState = AntigravityActivityAttributes.ContentState(
            statusRaw: summary.status.jsonName,
            currentStepIndex: max(1, summary.currentStepIndex),
            totalSteps: max(1, summary.totalSteps),
            activeToolAction: summary.statusSubtitle.isEmpty ? "Working..." : summary.statusSubtitle,
            pendingApprovalCommand: summary.status == .waiting ? pendingCmd : nil,
            elapsedSeconds: max(1, Int(Date().timeIntervalSince(summary.updatedAt))),
            additions: summary.totalAdditions,
            deletions: summary.totalDeletions
        )

        let cascadeId = summary.cascadeId
        let existingActivityId = Activity<AntigravityActivityAttributes>.activities.first {
            $0.attributes.cascadeId == cascadeId
        }?.id

        if let existingActivityId {
            let shouldEndImmediately = !isRunningOrWaiting && summary.status == .cancelled
            Task.detached(priority: .utility) {
                await Self.updateOrEndActivity(
                    activityId: existingActivityId,
                    contentState: contentState,
                    shouldEndImmediately: shouldEndImmediately
                )
            }
            activeCascadeId = cascadeId
            return
        }

        guard isRunningOrWaiting else { return }

        let attributes = AntigravityActivityAttributes(
            cascadeId: cascadeId,
            cascadeTitle: summary.title,
            hostName: store.activeHost.hostname,
            workspaceName: summary.projectSlug,
            branchName: summary.branchName.isEmpty ? "main" : summary.branchName
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: contentState,
                    staleDate: Date().addingTimeInterval(300)
                ),
                pushType: nil
            )
            activeCascadeId = cascadeId
        } catch {
            // Live Activity request may be denied when backgrounded or unsupported on simulator without entitlement
        }
        #else
        _ = store
        #endif
    }

    public func endAllActivities() {
        #if canImport(ActivityKit) && os(iOS)
        let activityIds = Activity<AntigravityActivityAttributes>.activities.map(\.id)
        if !activityIds.isEmpty {
            Task.detached(priority: .utility) {
                await Self.endActivities(ids: activityIds)
            }
        }
        #endif
        activeCascadeId = nil
    }

    #if canImport(ActivityKit) && os(iOS)
    private nonisolated static func updateOrEndActivity(
        activityId: String,
        contentState: AntigravityActivityAttributes.ContentState,
        shouldEndImmediately: Bool
    ) async {
        guard let existing = Activity<AntigravityActivityAttributes>.activities.first(where: { $0.id == activityId }) else {
            return
        }
        if shouldEndImmediately {
            await existing.end(
                ActivityContent(state: contentState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        } else {
            await existing.update(
                ActivityContent(
                    state: contentState,
                    staleDate: Date().addingTimeInterval(300)
                )
            )
        }
    }

    private nonisolated static func endActivities(ids: [String]) async {
        for activityId in ids {
            guard let activity = Activity<AntigravityActivityAttributes>.activities.first(where: { $0.id == activityId }) else {
                continue
            }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    #endif
}
