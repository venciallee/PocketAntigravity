import SwiftUI
import AntigravityData

/// Screen `W04_ARTIFACT_SUMMARY`: Watch · 产物摘要 (`Walkthrough` numbered key points, iPhone Handoff & `See changes` CTA).
public struct WatchArtifactSummaryView: View {
    @Bindable public var store: WatchAppStore
    public let cascadeId: String
    public var onBack: () -> Void

    public init(store: WatchAppStore, cascadeId: String, onBack: @escaping () -> Void) {
        self.store = store
        self.cascadeId = cascadeId
        self.onBack = onBack
    }

    private var session: WatchSessionSnapshot? {
        store.session(for: cascadeId) ?? store.snapshot.sessions.first
    }

    private var artifact: WatchArtifactSummarySnapshot {
        session?.artifactSummary ?? WatchVerificationFixtures.makeWalkthroughSummary()
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    WatchNavigationHeader(title: artifact.title, onBack: onBack)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(artifact.headline)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(WatchTheme.inkPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)

                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(artifact.points) { point in
                                keyPointRow(point)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 54)
                }
            }
            .background(WatchTheme.canvas.ignoresSafeArea())

            bottomActionBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            store.advertiseHandoff(cascadeId: cascadeId, target: .artifact)
        }
    }

    private func keyPointRow(_ point: WatchArtifactPoint) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(point.index)")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(WatchTheme.inkPrimary)
                .frame(width: 17, height: 17)
                .background(Circle().fill(WatchTheme.elevatedButton))
                .padding(.top, 1.5)

            renderedPointText(point.spans)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func renderedPointText(_ spans: [WatchStyledTextSpan]) -> Text {
        spans.reduce(Text("")) { acc, span in
            switch span.kind {
            case .plain:
                return acc + Text(span.text)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(WatchTheme.inkPrimary)
            case .code:
                return acc + Text(span.text)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(WatchTheme.inkPrimary)
            case .metricHighlight:
                return acc + Text(span.text)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(WatchTheme.emerald)
            }
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 8) {
            WatchCircleChromeButton(
                systemName: "iphone",
                foreground: WatchTheme.inkPrimary,
                background: WatchTheme.elevatedButton,
                diameter: WatchTheme.bottomControlHeight,
                iconSize: 15,
                accessibilityId: "watch.artifact.openOnPhone"
            ) {
                store.openOnPhone(cascadeId: cascadeId, target: .artifact)
            }

            Button {
                WatchHaptics.click()
                store.navigationPath.append(.changes(cascadeId: cascadeId))
            } label: {
                Text("See changes")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WatchTheme.inkOnPeriwinkle)
                    .frame(maxWidth: .infinity)
                    .frame(height: WatchTheme.bottomControlHeight)
                    .background(Capsule().fill(WatchTheme.accentPeriwinkle))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("watch.artifact.seeChanges")
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [WatchTheme.canvas.opacity(0.0), WatchTheme.canvas.opacity(0.92), WatchTheme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}
