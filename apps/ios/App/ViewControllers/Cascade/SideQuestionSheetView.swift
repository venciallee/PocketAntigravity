import SwiftUI
import AntigravityData

/// Multi-turn `/btw` Read-Only Side Question sheet (Antigravity v2.32.2 - v2.33.0).
/// Keeps main conversation context clean while letting the user insert answers on demand.
public struct SideQuestionSheetView: View {
    @Bindable private var store: AntigravitySessionStore
    @State private var draftText: String = ""
    @Environment(\.dismiss) private var dismiss

    public init(store: AntigravitySessionStore) {
        self.store = store
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.bubble.fill")
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    Text(lang.t("Read-only side thread · Does not mutate main conversation history", "只读旁路对话 · 不会修改主对话历史"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AntigravityTheme.surfaceObsidian)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if store.sideQuestionThread.messages.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.system(size: 28))
                                    .foregroundStyle(AntigravityTheme.inkMuted)
                                Text(lang.t("Ask a quick `/btw` follow-up", "发起快捷 `/btw` 旁路提问"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                Text(lang.t("Inspect code, verify edge cases, or clarify design choices without interrupting the main agent turn.", "在不打断主 Agent 任务的情况下，随时查看代码、验证边界情况或澄清设计方案。"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                        } else {
                            ForEach(store.sideQuestionThread.messages) { msg in
                                HStack {
                                    if msg.isUser { Spacer(minLength: 40) }
                                    Text(msg.text)
                                        .font(.system(size: 14))
                                        .foregroundStyle(msg.isUser ? AntigravityTheme.inkOnPrimaryCTA : AntigravityTheme.inkReading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            msg.isUser ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.surfaceCard,
                                            in: RoundedRectangle(cornerRadius: 14)
                                        )
                                    if !msg.isUser { Spacer(minLength: 40) }
                                }
                            }
                        }

                        if store.sideQuestionThread.isStreaming {
                            HStack(spacing: 8) {
                                ProgressView().tint(AntigravityTheme.accentPeriwinkle)
                                Text(lang.t("Thinking on side thread...", "正在旁路线程中思考..."))
                                    .font(.system(size: 13))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                            }
                        }
                    }
                    .padding(16)
                }

                if store.sideQuestionThread.latestAssistantAnswer != nil {
                    Button {
                        store.insertSideQuestionAnswerIntoMain()
                        dismiss()
                    } label: {
                        Label(lang.t("Insert into main conversation", "插入主对话"), systemImage: "arrow.uturn.left.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(AntigravityTheme.accentPeriwinkle, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("btn_insert_btw_into_main")
                }

                HStack(spacing: 10) {
                    TextField(lang.t("Ask a side question...", "输入旁路问题..."), text: $draftText, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 15))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("input_side_question")

                    Button {
                        let q = draftText
                        draftText = ""
                        store.sendSideQuestion(q)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? AntigravityTheme.inkMuted
                                : AntigravityTheme.accentPeriwinkle)
                    }
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("btn_send_side_question")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AntigravityTheme.surfaceObsidian)
            }
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle(lang.t("/btw Side Question", "/btw 旁路提问"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang.t("Clear", "清空")) {
                        store.resetSideQuestionThread()
                    }
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang.t("Done", "完成")) {
                        store.presentedSheet = nil
                        dismiss()
                    }
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
            }
        }
        .accessibilityIdentifier("sheet_side_question")
    }
}
