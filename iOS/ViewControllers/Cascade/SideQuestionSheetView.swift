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

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.bubble.fill")
                        .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    Text("Read-only side thread · Does not mutate main conversation history")
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
                                Text("Ask a quick `/btw` follow-up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                Text("Inspect code, verify edge cases, or clarify design choices without interrupting the main agent turn.")
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
                                Text("Thinking on side thread...")
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
                        Label("Insert into main conversation", systemImage: "arrow.uturn.left.circle.fill")
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
                    TextField("Ask a side question...", text: $draftText, axis: .vertical)
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
            .navigationTitle("/btw Side Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        store.resetSideQuestionThread()
                    }
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        store.presentedSheet = nil
                        dismiss()
                    }
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("sheet_side_question")
    }
}
