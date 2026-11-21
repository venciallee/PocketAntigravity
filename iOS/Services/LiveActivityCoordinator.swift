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
        let pendingCmd = store.pendingWaitingStep?.runCommand?.proposedCommandLine
            ?? store.pendingWaitingStep?.runCommand?.commandLine
            ?? summary.pendingInteractionTitle

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

        let existing = Activity<AntigravityActivityAttributes>.activities.first {
            $0.attributes.cascadeId == summary.cascadeId
        }

        if let existing {
            if !isRunningOrWaiting && summary.status == .cancelled {
                Task {
                    await existing.end(
                        ActivityContent(state: contentState, staleDate: nil),
                        dismissalPolicy: .immediate
                    )
                }
            } else {
                Task {
                    await existing.update(
                        ActivityContent(
                            state: contentState,
                            staleDate: Date().addingTimeInterval(300)
                        )
                    )
                }
            }
            activeCascadeId = summary.cascadeId
            return
        }

        guard isRunningOrWaiting else { return }

        let attributes = AntigravityActivityAttributes(
            cascadeId: summary.cascadeId,
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
            activeCascadeId = summary.cascadeId
        } catch {
            // Live Activity request may be denied when backgrounded or unsupported on simulator without entitlement
        }
        #else
        _ = store
        #endif
    }

    public func endAllActivities() {
        #if canImport(ActivityKit) && os(iOS)
        let activities = Activity<AntigravityActivityAttributes>.activities
        for activity in activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
        activeCascadeId = nil
    }
}
