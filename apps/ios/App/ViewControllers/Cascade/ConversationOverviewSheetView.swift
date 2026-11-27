import SwiftUI
import AntigravityData

/// Native iOS Conversation Overview drawer surfacing Review diffs, Modified Files,
/// Subagents, Background Tasks (with Cancel), Goals, Artifacts, Documents, and GitHub PRs (v2.30-v2.33).
public struct ConversationOverviewSheetView: View {
    @Bindable private var store: AntigravitySessionStore
    @Environment(\.dismiss) private var dismiss

    public init(store: AntigravitySessionStore) {
        self.store = store
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    reviewCard
                    pullRequestsCard
                    subagentsCard
                    backgroundTasksCard
                    goalsCard
                    artifactsCard
                    filesAndLinksCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle(lang.t("Conversation Overview", "对话概览"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang.t("Done", "完成")) {
                        store.presentedSheet = nil
                        dismiss()
                    }
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                }
            }
            .task {
                await store.refreshConversationOverview()
                if !store.activeCascadeId.isEmpty {
                    await store.loadLiveArtifactsAndDiffs(for: store.activeCascadeId)
                }
            }
        }
        .accessibilityIdentifier("sheet_conversation_overview")
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(lang.t("Review & Diffs", "审查与变更"), systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                Spacer()
                Text("+\(store.conversationOverview.reviewAdditions)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.statusDone)
                Text("-\(store.conversationOverview.reviewDeletions)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.statusError)
            }
            HStack(spacing: 10) {
                Button {
                    store.presentedSheet = nil
                    store.activeRoute = .turnDiffReview
                } label: {
                    Text(lang.t("Open Diff Review", "打开变更审查"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .background(AntigravityTheme.accentPeriwinkle, in: RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    store.presentedSheet = nil
                    store.activeRoute = .planReview
                } label: {
                    Text(lang.t("Plan Review", "方案审查"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(14)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }

    @ViewBuilder
    private var pullRequestsCard: some View {
        let prs = store.conversationOverview.pullRequests
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(lang.t("Pull Requests (\(prs.count))", "拉取请求 (\(prs.count))"), systemImage: "arrow.triangle.pull")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                ForEach(prs) { pr in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(pr.state == .merged ? Color.purple : (pr.state == .open ? AntigravityTheme.statusDone : AntigravityTheme.inkSecondary))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pr.ownerRepo) #\(pr.number)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkReading)
                            Text("\(pr.title) · \(pr.checksSummary)")
                                .font(.system(size: 12))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let url = URL(string: pr.url) {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            }
                        }
                    }
                    .padding(10)
                    .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(14)
            .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
        }
    }

    private var subagentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.t("Subagents (\(store.conversationOverview.subagents.count))", "子代理 (\(store.conversationOverview.subagents.count))"), systemImage: "person.3.sequence")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkReading)
            if store.conversationOverview.subagents.isEmpty {
                Text(lang.t("No active subagents spawned in this conversation.", "此对话中暂无活跃子代理。"))
                    .font(.system(size: 13))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            } else {
                ForEach(store.conversationOverview.subagents) { sub in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(sub.role)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                Text(sub.status.localizedTitle(for: lang))
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AntigravityTheme.surfaceElevated, in: Capsule())
                                    .foregroundStyle(sub.status == .inProgress ? AntigravityTheme.statusRunning : AntigravityTheme.statusDone)
                            }
                            if !sub.summary.isEmpty {
                                Text(sub.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if sub.status == .inProgress || sub.status == .waiting {
                            Button(lang.t("Stop", "停止")) {
                                store.stopSubagent(sub.subagentId)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.statusError)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AntigravityTheme.statusError.opacity(0.14), in: Capsule())
                        }
                    }
                    .padding(10)
                    .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(14)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }

    private var backgroundTasksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.t("Background Tasks (\(store.conversationOverview.backgroundTasks.count))", "后台任务 (\(store.conversationOverview.backgroundTasks.count))"), systemImage: "gearshape.2")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkReading)
            if store.conversationOverview.backgroundTasks.isEmpty {
                Text(lang.t("No background shell or daemon tasks running.", "当前无后台 Shell 或守护进程任务。"))
                    .font(.system(size: 13))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            } else {
                ForEach(store.conversationOverview.backgroundTasks) { task in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkReading)
                            Text("\(task.commandSummary) · \(task.elapsedLabel)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if task.canCancel && task.status == .inProgress {
                            Button(lang.t("Cancel", "取消")) {
                                store.cancelBackgroundTask(task.id)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.statusError)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AntigravityTheme.statusError.opacity(0.14), in: Capsule())
                            .accessibilityIdentifier("btn_cancel_bg_task_\(task.id)")
                        } else {
                            Text(task.status.localizedTitle(for: lang))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                    }
                    .padding(10)
                    .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(14)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }

    @ViewBuilder
    private var goalsCard: some View {
        if !store.conversationOverview.goals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(lang.t("Goals (\(store.conversationOverview.goals.count))", "目标 (\(store.conversationOverview.goals.count))"), systemImage: "target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                ForEach(store.conversationOverview.goals) { goal in
                    HStack {
                        Text(goal.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AntigravityTheme.inkReading)
                        Spacer()
                        Text(goal.progressText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    }
                    .padding(10)
                    .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(14)
            .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
        }
    }

    private var artifactsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.t("Artifacts (\(store.activeArtifacts.count))", "产物 (\(store.activeArtifacts.count))"), systemImage: "doc.richtext")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkReading)
            if store.activeArtifacts.isEmpty {
                Text(lang.t("No artifacts captured yet.", "暂未生成产物。"))
                    .font(.system(size: 13))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            } else {
                ForEach(store.activeArtifacts) { artifact in
                    Button {
                        store.selectedArtifactPath = artifact.artifactPath
                        if artifact.kind == .implementationPlan {
                            store.presentedSheet = nil
                            store.activeRoute = .planReview
                        } else {
                            store.presentedSheet = .richArtifactViewer(artifactPath: artifact.artifactPath)
                        }
                    } label: {
                        HStack {
                            Image(systemName: iconName(for: artifact.kind))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artifact.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                Text(artifact.artifactPath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(AntigravityTheme.inkMuted)
                        }
                        .padding(10)
                        .background(AntigravityTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(14)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }

    private var filesAndLinksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(lang.t("Modified Files (\(store.conversationOverview.modifiedFiles.count))", "修改的文件 (\(store.conversationOverview.modifiedFiles.count))"), systemImage: "folder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkReading)
            if store.conversationOverview.modifiedFiles.isEmpty {
                Text(lang.t("No modified files tracked yet.", "暂未跟踪到修改的文件。"))
                    .font(.system(size: 13))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            } else {
                ForEach(store.conversationOverview.modifiedFiles, id: \.self) { file in
                    Text(file)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                }
            }
        }
        .padding(14)
        .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
    }

    private func iconName(for kind: ArtifactKind) -> String {
        switch kind {
        case .pdfDocument: return "doc.fill"
        case .jupyterNotebook: return "curlybraces.square"
        case .imageAsset: return "photo"
        case .videoAsset: return "video"
        case .generativeUIHTML: return "safari"
        case .urlBookmark: return "link"
        case .unsupportedAsset: return "doc.questionmark"
        default: return "doc.text"
        }
    }
}
