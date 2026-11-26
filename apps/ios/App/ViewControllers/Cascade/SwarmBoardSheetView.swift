import SwiftUI
import AntigravityData

/// Native Agent Swarm Board sheet (`/swarm`, Antigravity v2.31.0+) displaying
/// Specialist Roster, live status pills, and filterable shared Discussion Board posts.
public struct SwarmBoardSheetView: View {
    @Bindable private var store: AntigravitySessionStore
    private let stepIndex: Int
    @State private var selectedMemberFilter: String? = nil
    @Environment(\.dismiss) private var dismiss

    public init(store: AntigravitySessionStore, stepIndex: Int) {
        self.store = store
        self.stepIndex = stepIndex
    }

    private var lang: AppLanguage { store.appearancePreferences.language }

    private var payload: SwarmBoardPayload? {
        store.activeSteps.first(where: { $0.stepIndex == stepIndex })?.swarmBoard
            ?? store.activeSteps.compactMap(\.swarmBoard).last
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let board = payload {
                        rosterSection(board: board)
                        postsSection(board: board)
                    } else {
                        Text(lang.t("No active Agent Swarm board found for this conversation.", "此对话暂无活跃的多代理协作看板。"))
                            .font(.system(size: 14))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                            .padding(.top, 24)
                    }
                }
                .padding(16)
            }
            .background(AntigravityTheme.canvasObsidian.ignoresSafeArea())
            .navigationTitle(payload?.title ?? lang.t("Agent Swarm Board", "多代理协作看板"))
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
        }
        .accessibilityIdentifier("sheet_swarm_board")
    }

    private func rosterSection(board: SwarmBoardPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("SWARM ROSTER (\(board.members.count))", "协作团队成员 (\(board.members.count))"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AntigravityTheme.inkSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        selectedMemberFilter = nil
                    } label: {
                        Text(lang.t("All", "全部"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedMemberFilter == nil ? AntigravityTheme.inkOnPrimaryCTA : AntigravityTheme.inkReading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedMemberFilter == nil ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.surfaceCard, in: Capsule())
                    }
                    ForEach(board.members) { member in
                        let isSelected = selectedMemberFilter == member.name
                        Button {
                            selectedMemberFilter = isSelected ? nil : member.name
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(member.status == .done ? AntigravityTheme.statusDone : AntigravityTheme.statusRunning)
                                    .frame(width: 7, height: 7)
                                Text("@\(member.name)")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("· \(member.role)")
                                    .font(.system(size: 11))
                                    .opacity(0.8)
                            }
                            .foregroundStyle(isSelected ? AntigravityTheme.inkOnPrimaryCTA : AntigravityTheme.inkReading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.surfaceCard, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func postsSection(board: SwarmBoardPayload) -> some View {
        let filtered = board.posts.filter { post in
            guard let filter = selectedMemberFilter else { return true }
            return post.authorName == filter || post.mentions.contains(filter)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("DISCUSSION BOARD (\(filtered.count))", "共享讨论板 (\(filtered.count))"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AntigravityTheme.inkSecondary)

            if filtered.isEmpty {
                Text(lang.t("No board posts yet for this filter.", "当前筛选条件下暂无讨论帖。"))
                    .font(.system(size: 13))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            } else {
                ForEach(filtered) { post in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("@\(post.authorName)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                            if !post.mentions.isEmpty {
                                Text("→ " + post.mentions.map { "@\($0)" }.joined(separator: " "))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AntigravityTheme.inkSecondary)
                            }
                            Spacer()
                        }
                        Text(post.bodyMarkdown)
                            .font(.system(size: 14))
                            .foregroundStyle(AntigravityTheme.inkReading)
                    }
                    .padding(12)
                    .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AntigravityTheme.glassHairline, lineWidth: 1))
                }
            }
        }
    }
}
