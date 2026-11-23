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

    private var isProceeded: Bool {
        store.proceededArtifactIds.contains(artifact.id)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    WatchNavigationHeader(title: artifact.title, onBack: onBack)

                    VStack(alignment: .leading, spacing: 5.5) {
                        Text(artifact.headline)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(WatchTheme.inkPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)

                        VStack(alignment: .leading, spacing: 5.5) {
                            ForEach(Array(artifact.points.prefix(WatchArtifactSummarySnapshot.maxKeyPoints))) { point in
                                keyPointRow(point)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 52)
                }
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            .background(WatchTheme.canvas.ignoresSafeArea())

            bottomActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .automatic)
        .onAppear {
            store.advertiseHandoff(cascadeId: cascadeId, target: .artifact)
        }
    }

    private func keyPointRow(_ point: WatchArtifactPoint) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(point.index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchTheme.inkPrimary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(WatchTheme.elevatedButton))
                .padding(.top, 1)

            renderedPointText(point.spans)
                .lineSpacing(1.0)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func renderedPointText(_ spans: [WatchStyledTextSpan]) -> Text {
        spans.reduce(Text("")) { acc, span in
            switch span.kind {
            case .plain:
                return acc + Text(span.text)
                    .font(.system(size: 12.2, weight: .regular))
                    .foregroundStyle(WatchTheme.inkPrimary)
            case .code:
                return acc + Text(span.text)
                    .font(.system(size: 11.8, weight: .regular, design: .monospaced))
                    .foregroundStyle(WatchTheme.inkPrimary)
            case .metricHighlight:
                return acc + Text(span.text)
                    .font(.system(size: 12.2, weight: .bold))
                    .foregroundStyle(WatchTheme.emerald)
            }
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 7) {
            WatchCircleChromeButton(
                systemName: "iphone",
                foreground: WatchTheme.inkPrimary,
                background: WatchTheme.elevatedButton,
                diameter: WatchTheme.bottomControlHeight,
                iconSize: 14,
                accessibilityId: "watch.artifact.openOnPhone"
            ) {
                store.openOnPhone(cascadeId: cascadeId, target: .artifact)
            }

            if artifact.primaryAction == .proceed {
                Button {
                    store.proceedPlan(cascadeId: cascadeId, artifact: artifact)
                } label: {
                    HStack(spacing: 5) {
                        if isProceeded {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12.5, weight: .bold))
                        }
                        Text(isProceeded ? "Proceeding" : "Proceed")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(WatchTheme.inkOnPeriwinkle)
                    .frame(maxWidth: .infinity)
                    .frame(height: WatchTheme.bottomControlHeight)
                    .background(
                        Capsule().fill(isProceeded ? WatchTheme.emerald : WatchTheme.accentPeriwinkle)
                    )
                }
                .buttonStyle(.plain)
                .watchPrimaryDoubleTap(enabled: !isProceeded)
                .accessibilityIdentifier("watch.artifact.proceed")
            } else {
                Button {
                    WatchHaptics.click()
                    store.navigationPath.append(.changes(cascadeId: cascadeId))
                } label: {
                    Text("See changes")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(WatchTheme.inkOnPeriwinkle)
                        .frame(maxWidth: .infinity)
                        .frame(height: WatchTheme.bottomControlHeight)
                        .background(Capsule().fill(WatchTheme.accentPeriwinkle))
                }
                .buttonStyle(.plain)
                .watchPrimaryDoubleTap()
                .accessibilityIdentifier("watch.artifact.seeChanges")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, WatchTheme.bottomBezelInset)
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
