import SwiftUI
import AntigravityData

/// State `UE05_CREATE_PROJECT`: Create New Project Sheet (`MacBook Pro` / `Cloud` + `GitHub` / `Drive`).
/// Matches `/home/antigravity/iOS_·_Create_New_Project.png` 1:1.
public struct CreateProjectSheetView: View {
    @Bindable public var store: AntigravitySessionStore
    public var onDismiss: (() -> Void)?

    public enum RuntimeTarget: String, CaseIterable, Identifiable {
        case macBookPro = "MacBook Pro"
        case cloud = "Cloud"

        public var id: String { rawValue }

        public func localizedTitle(for lang: AppLanguage) -> String {
            switch self {
            case .macBookPro: return rawValue
            case .cloud: return lang.t("Cloud", "云端")
            }
        }
    }

    public enum SourceKind: String, CaseIterable, Identifiable {
        case github = "GitHub repository"
        case drive = "Drive folder"

        public var id: String { rawValue }

        public func localizedTitle(for lang: AppLanguage) -> String {
            switch self {
            case .github: return lang.t("GitHub repository", "GitHub 仓库")
            case .drive: return lang.t("Drive folder", "云端硬盘文件夹")
            }
        }
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var localizedBranchWorktreeLabel: String {
        if branchWorktreeLabel == "main · Existing checkout" {
            return lang.t("main · Existing checkout", "main · 已有检出目录")
        }
        return lang.t("main · New worktree", "main · 新建工作树")
    }

    private struct GitHubRepoRowModel: Identifiable {
        let id: String
        let fullName: String
        let metadata: String
        let defaultProjectNameCloud: String
        let defaultProjectNameMac: String
        let accessibilityId: String
    }

    @State private var runsOn: RuntimeTarget = .cloud
    @State private var sourceKind: SourceKind = .github
    @State private var repoSearchQuery: String = ""
    @State private var selectedRepoId: String
    @State private var branchWorktreeLabel: String = "main · New worktree"
    @State private var projectName: String

    private let verificationRepositories: [GitHubRepoRowModel] = [
        GitHubRepoRowModel(
            id: "acme/ledger-svc",
            fullName: "acme/ledger-svc",
            metadata: "Private · Go · updated 2h ago",
            defaultProjectNameCloud: "ledger-svc-cloud",
            defaultProjectNameMac: "ledger-svc",
            accessibilityId: "repo-row-ledger-svc"
        ),
        GitHubRepoRowModel(
            id: "acme/web-console",
            fullName: "acme/web-console",
            metadata: "Private · TypeScript · updated 1d ago",
            defaultProjectNameCloud: "web-console-cloud",
            defaultProjectNameMac: "web-console",
            accessibilityId: "repo-row-web-console"
        ),
        GitHubRepoRowModel(
            id: "acme/design-tokens",
            fullName: "acme/design-tokens",
            metadata: "Public · updated 5d ago",
            defaultProjectNameCloud: "design-tokens-cloud",
            defaultProjectNameMac: "design-tokens",
            accessibilityId: "repo-row-design-tokens"
        )
    ]

    private var repositories: [GitHubRepoRowModel] {
        guard !store.isVerificationMode else { return verificationRepositories }
        return store.availableGitHubRepos.map { repo in
            let slug = repo.fullName.split(separator: "/").last.map(String.init) ?? repo.fullName
            return GitHubRepoRowModel(
                id: repo.id,
                fullName: repo.fullName,
                metadata: repo.visibilityLabel,
                defaultProjectNameCloud: "\(slug)-cloud",
                defaultProjectNameMac: slug,
                accessibilityId: "repo-row-\(slug)"
            )
        }
    }

    public init(
        store: AntigravitySessionStore,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.onDismiss = onDismiss
        if store.isVerificationMode {
            self._selectedRepoId = State(initialValue: "acme/ledger-svc")
            self._projectName = State(initialValue: "ledger-svc-cloud")
        } else {
            let firstRepo = store.availableGitHubRepos.first?.id ?? ""
            self._selectedRepoId = State(initialValue: firstRepo)
            self._projectName = State(initialValue: "")
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            AntigravityTheme.canvasObsidian.ignoresSafeArea()
            AntigravityTheme.scrimOverlay.ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(AntigravityTheme.sheetHandle)
                    .frame(width: 38, height: 5)
                    .padding(.top, 9)

                headerBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        runsOnSection
                        sourceSection
                        repositorySearchBar
                        repositoryListCard
                        githubConfigureButton
                        worktreeAndNameCard
                        submitButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 18)
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
                .fill(AntigravityTheme.surfaceSheet)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
                .strokeBorder(AntigravityTheme.cardBorder, lineWidth: 1)
            )
            .padding(.top, 14)
        }
        .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
    }

    // MARK: - 1. Header Bar (Cancel / New Project)

    private var headerBar: some View {
        HStack {
            Button {
                onDismiss?()
            } label: {
                Text(lang.t("Cancel", "取消"))
                    .font(.system(size: 16.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .frame(minWidth: 64, minHeight: AntigravityTheme.minTouchTargetPt, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-cancel-project")

            Spacer()

            Text(lang.t("New Project", "新建项目"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AntigravityTheme.textPrimary)

            Spacer()

            Color.clear
                .frame(width: 64, height: AntigravityTheme.minTouchTargetPt)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - 2. RUNS ON Segmented Picker

    private var runsOnSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(lang.t("RUNS ON", "运行环境"))
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AntigravityTheme.textMuted)

            HStack(spacing: 4) {
                runsOnSegmentButton(
                    target: .macBookPro,
                    symbol: "laptopcomputer",
                    accessibilityId: "seg-runs-on-mac"
                )
                runsOnSegmentButton(
                    target: .cloud,
                    symbol: "cloud",
                    accessibilityId: "seg-runs-on-cloud"
                )
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AntigravityTheme.surfaceSheetGroup)
            )

            Text(
                runsOn == .cloud
                    ? lang.t("Runs in its own cloud VM and keeps working while your computer sleeps.", "在独立的云端虚拟机中运行，电脑休眠时仍可持续工作。")
                    : lang.t("Runs directly in a local workspace or git worktree on MacBook Pro.", "直接在 MacBook Pro 的本地工作区或 git worktree 中运行。")
            )
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(AntigravityTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runsOnSegmentButton(
        target: RuntimeTarget,
        symbol: String,
        accessibilityId: String
    ) -> some View {
        let isSelected = (runsOn == target)
        return Button {
            runsOn = target
            if let repo = repositories.first(where: { $0.id == selectedRepoId }) {
                projectName = (target == .cloud) ? repo.defaultProjectNameCloud : repo.defaultProjectNameMac
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13.5, weight: .medium))
                Text(target.localizedTitle(for: lang))
                    .font(.system(size: 14.5, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? AntigravityTheme.textPrimary : AntigravityTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: AntigravityTheme.minTouchTargetPt)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(AntigravityTheme.surfaceActiveTabSlot)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }

    // MARK: - 3. SOURCE 2-Card Grid

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(lang.t("SOURCE", "来源"))
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AntigravityTheme.textMuted)

            HStack(spacing: 10) {
                sourceCardButton(
                    kind: .github,
                    symbol: "arrow.triangle.branch",
                    accessibilityId: "source-card-github"
                )
                sourceCardButton(
                    kind: .drive,
                    symbol: "folder",
                    accessibilityId: "source-card-drive"
                )
            }
        }
    }

    private func sourceCardButton(
        kind: SourceKind,
        symbol: String,
        accessibilityId: String
    ) -> some View {
        let isSelected = (sourceKind == kind)
        return Button {
            sourceKind = kind
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(isSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.textSecondary)
                Text(kind.localizedTitle(for: lang))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? AntigravityTheme.surfaceSelectionTint
                            : AntigravityTheme.surfaceSheetGroup
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.glassHairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }

    // MARK: - 4. Repository Search Input

    private var repositorySearchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(AntigravityTheme.textMuted)
            TextField(lang.t("Search repositories", "搜索仓库"), text: $repoSearchQuery)
                .font(.system(size: 15.5, weight: .regular))
                .foregroundStyle(AntigravityTheme.textPrimary)
                .tint(AntigravityTheme.accentPeriwinkle)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: AntigravityTheme.minTouchTargetPt)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(AntigravityTheme.surfaceSheetGroup)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(AntigravityTheme.glassHairline, lineWidth: 1)
        )
        .accessibilityIdentifier("repo-search-input")
    }

    // MARK: - 5. Repository List Card

    private var repositoryListCard: some View {
        let visibleRepos = repositories.filter { repo in
            let q = repoSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return q.isEmpty || repo.fullName.lowercased().contains(q)
        }

        return VStack(spacing: 0) {
            if visibleRepos.isEmpty {
                Text(lang.t("No repositories synced yet — enter a project name below.", "尚未同步仓库 — 请在下方输入项目名称。"))
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            } else {
                ForEach(Array(visibleRepos.enumerated()), id: \.element.id) { index, repo in
                    let isSelected = (selectedRepoId == repo.id)
                    Button {
                        selectedRepoId = repo.id
                        projectName = (runsOn == .cloud) ? repo.defaultProjectNameCloud : repo.defaultProjectNameMac
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.fullName)
                                    .font(.system(size: 14.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.textPrimary)
                                Text(repo.metadata)
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundStyle(AntigravityTheme.textSecondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(repo.accessibilityId)

                    if index < visibleRepos.count - 1 {
                        Divider()
                            .overlay(AntigravityTheme.subtleDivider)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AntigravityTheme.surfaceSheetGroup)
        )
    }

    private var githubConfigureButton: some View {
        Group {
            if let url = URL(string: "https://github.com/settings/installations") {
                Link(lang.t("Missing a repo? Configure on GitHub", "找不到仓库？前往 GitHub 配置"), destination: url)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .padding(.leading, 2)
            } else {
                Text(lang.t("Missing a repo? Configure on GitHub", "找不到仓库？前往 GitHub 配置"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .padding(.leading, 2)
            }
        }
    }

    // MARK: - 6. Branch & Worktree + Name Card

    private var worktreeAndNameCard: some View {
        VStack(spacing: 0) {
            Button {
                branchWorktreeLabel = (branchWorktreeLabel == "main · New worktree")
                    ? "main · Existing checkout"
                    : "main · New worktree"
            } label: {
                HStack {
                    Text(lang.t("Branch & worktree", "分支与工作树"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 5) {
                        Text(localizedBranchWorktreeLabel)
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AntigravityTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(AntigravityTheme.subtleDivider)

            HStack {
                Text(lang.t("Name", "名称"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textPrimary)
                Spacer()
                TextField(lang.t("Project name", "项目名称"), text: $projectName)
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(AntigravityTheme.textBody)
                    .multilineTextAlignment(.trailing)
                    .tint(AntigravityTheme.accentPeriwinkle)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)

            if !store.isVerificationMode {
                Divider()
                    .overlay(AntigravityTheme.subtleDivider)

                HStack {
                    Text(lang.t("Drive URL", "云端硬盘链接"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AntigravityTheme.textPrimary)
                    Spacer()
                    TextField(lang.t("Optional Google Drive folder link", "可选 Google Drive 文件夹链接"), text: Binding(
                        get: { store.newProjectDraft.driveResourceLinks.first ?? "" },
                        set: { val in
                            let clean = val.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.newProjectDraft.driveResourceLinks = clean.isEmpty ? [] : [clean]
                        }
                    ))
                    .font(.system(size: 13.5))
                    .foregroundStyle(AntigravityTheme.textBody)
                    .multilineTextAlignment(.trailing)
                    .tint(AntigravityTheme.accentPeriwinkle)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)

                Divider()
                    .overlay(AntigravityTheme.subtleDivider)

                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.t("Environment Setup (`env-setup.sh`)", "环境初始化脚本 (`env-setup.sh`)"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.textSecondary)
                    TextField(lang.t("e.g. npm ci && go mod download", "例如 npm ci && go mod download"), text: $store.newProjectDraft.envSetupScript)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.textBody)
                        .tint(AntigravityTheme.accentPeriwinkle)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AntigravityTheme.surfaceSheetGroup)
        )
    }

    // MARK: - 7. Submit CTA

    private var submitButton: some View {
        Button {
            if !store.isVerificationMode {
                let targetRuntime: ProjectRuntimeTarget = (runsOn == .cloud) ? .cloud : .macBookPro
                let targetSource: ProjectSourceKind = (sourceKind == .drive) ? .driveFolder : .githubRepo
                let chosenRepo = store.availableGitHubRepos.first(where: { $0.id == selectedRepoId })
                _ = store.createNewProject(
                    name: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                    runtime: targetRuntime,
                    source: targetSource,
                    selectedRepo: chosenRepo,
                    branchWorktree: branchWorktreeLabel
                )
            }
            onDismiss?()
        } label: {
            Text(lang.t("Create Project", "创建项目"))
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(AntigravityTheme.inkOnPrimaryCTA)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    Capsule()
                        .fill(AntigravityTheme.accentPeriwinkle)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityIdentifier("btn-submit-create-project")
    }
}
