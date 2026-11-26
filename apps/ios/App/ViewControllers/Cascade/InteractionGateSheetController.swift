import SwiftUI
import AntigravityData

/// Permission Gate & Question Modal (`InteractionGateSheetController`) bridging sheet presentations
/// to `InlineCommandApprovalCardView` (Face ID biometric gate) and `StructuredQuestionCardView`.
public struct InteractionGateSheetController: View {
    public enum PresentationMode: Sendable {
        case permissionGate
        case askQuestion
    }

    @Bindable public var store: AntigravitySessionStore
    public var mode: PresentationMode
    public var stepIndex: Int?

    public init(
        store: AntigravitySessionStore,
        mode: PresentationMode,
        stepIndex: Int? = nil
    ) {
        self.store = store
        self.mode = mode
        self.stepIndex = stepIndex
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    public var body: some View {
        switch mode {
        case .permissionGate:
            let targetStep = store.waitingStep(at: stepIndex)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("Approval Required", "需要审批"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkReading)
                        if let targetStep {
                            Text(lang.t("Step \(targetStep.stepIndex + 1) · \(store.activeSummary?.title ?? "Agent")", "第 \(targetStep.stepIndex + 1) 步 · \(store.activeSummary?.title ?? "Agent")"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        store.presentedSheet = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .frame(width: 32, height: 32)
                            .background(AntigravityTheme.surfaceElevated, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-close-approval-sheet")
                }

                if let targetStep, let effectiveReq = targetStep.effectiveRequestedInteraction {
                    ScrollView {
                        StepInlineApprovalCardView(
                            store: store,
                            step: targetStep,
                            requested: effectiveReq
                        )
                    }
                } else {
                    InlineCommandApprovalCardView(store: store)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)

        case .askQuestion:
            StructuredQuestionCardView(store: store)
        }
    }
}
