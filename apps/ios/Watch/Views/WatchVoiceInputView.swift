import SwiftUI
import AntigravityData

/// Screen `W07_VOICE_INPUT`: Watch · 语音输入 (target selector pill, live transcript with muted partial token,
/// animated periwinkle waveform, Double Tap primary action shortcut & Stop/Send bottom controls).
public struct WatchVoiceInputView: View {
    @Bindable public var store: WatchAppStore
    public var onDismiss: () -> Void

    private static let baseBarHeights: [CGFloat] = [5, 9, 17, 7, 20, 14, 17, 9, 9, 9, 6]

    public init(store: WatchAppStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    private var targetTitle: String {
        store.voiceTargetSession?.title ?? "Rate limiter"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WatchCircleChromeButton(
                    systemName: "xmark",
                    accessibilityId: "watch.voice.close",
                    action: {
                        store.isVoiceListening = false
                        onDismiss()
                    }
                )
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Button {
                WatchHaptics.click()
                store.cycleVoiceTargetSession()
            } label: {
                HStack(spacing: 4) {
                    Text("To: \(targetTitle)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(WatchTheme.inkSubtlePill)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WatchTheme.inkSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(WatchTheme.card))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .accessibilityIdentifier("watch.voice.targetSelector")

            transcriptArea
                .padding(.horizontal, 10)
                .padding(.top, 9)

            Spacer(minLength: 4)

            waveformView
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            Text("Double tap to send")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(WatchTheme.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 3)
                .padding(.bottom, 8)

            bottomControlsBar
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var transcriptArea: some View {
        if store.isVerificationMode || !store.combinedVoiceDraftText.isEmpty {
            (
                Text(store.voiceCommittedText)
                    .foregroundStyle(WatchTheme.inkPrimary)
                + Text(store.voicePartialWord)
                    .foregroundStyle(WatchTheme.inkMuted)
            )
            .font(.system(size: 16, weight: .bold))
            .lineSpacing(1.5)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("watch.voice.transcript")
        } else {
            // Live watchOS dictation / Scribble input when user opens Voice Input on a real Apple Watch.
            TextField(
                "Tap to dictate…",
                text: Binding(
                    get: { store.voiceCommittedText },
                    set: { newValue in
                        store.voiceCommittedText = newValue
                        store.voicePartialWord = ""
                    }
                )
            )
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(WatchTheme.inkPrimary)
            .accessibilityIdentifier("watch.voice.dictationField")
        }
    }

    @ViewBuilder
    private var waveformView: some View {
        if store.isVoiceListening && !store.isVerificationMode {
            TimelineView(.periodic(from: .now, by: 0.12)) { context in
                let t = context.date.timeIntervalSinceReferenceDate * 4.5
                waveformBars(phase: t)
            }
        } else {
            waveformBars(phase: nil)
        }
    }

    private func waveformBars(phase: Double?) -> some View {
        HStack(spacing: 3.5) {
            ForEach(Array(Self.baseBarHeights.enumerated()), id: \.offset) { idx, baseH in
                let height: CGFloat = {
                    guard let phase else { return baseH }
                    let wave = 0.65 + 0.45 * abs(sin(phase + Double(idx) * 0.65))
                    return max(4, min(22, baseH * wave))
                }()
                Capsule()
                    .fill(WatchTheme.accentPeriwinkle)
                    .frame(width: 3, height: height)
            }
        }
        .frame(height: 22)
    }

    private var bottomControlsBar: some View {
        HStack(spacing: 8) {
            Button {
                WatchHaptics.click()
                store.isVoiceListening.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(WatchTheme.inkPrimary)
                    .frame(width: 11, height: 11)
                    .frame(width: WatchTheme.bottomControlHeight, height: WatchTheme.bottomControlHeight)
                    .background(Circle().fill(WatchTheme.elevatedButton))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("watch.voice.stopButton")

            Button {
                store.submitVoiceReply()
                onDismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13.5, weight: .bold))
                    Text("Send")
                        .font(.system(size: 14.5, weight: .bold))
                }
                .foregroundStyle(WatchTheme.inkOnPeriwinkle)
                .frame(maxWidth: .infinity)
                .frame(height: WatchTheme.bottomControlHeight)
                .background(Capsule().fill(WatchTheme.accentPeriwinkle))
            }
            .buttonStyle(.plain)
            .watchPrimaryDoubleTap()
            .accessibilityIdentifier("watch.voice.sendButton")
        }
    }
}
