import SwiftUI
import AntigravityData

/// State `UE12_TURN_DIFF_REVIEW`: Turn Diff Line-Level Review & Comment Composer (`iOS · Turn Diff 行级审查`).
/// Features:
/// - Header `Review changes` (`Add rate limiter to /transfers`) + `Accept all` (`btn-accept-all-diffs`)
/// - Turn strip (`Turn 1`, `Turn 2`, `Turn 3 · latest` white pill `turn-pill-3-latest`, `All`)
/// - File pager `< middleware/ratelimit.go (File 1 of 4 · +96 -4) >` (`file-pager-card`)
/// - Hunk header `@@ -18,9 +18,27 @@ Allow` + `Revert hunk` (`btn-revert-hunk`)
/// - Syntax diff lines `18..31` with word-level red/green highlights, selected blue line `29 + now := time.Now()` (`diff-line-29`)
/// - Inline `Comment on line 29` composer card (`line-comment-composer`: `Add to review` `btn-add-to-review` + Periwinkle `Send to agent` `btn-send-to-agent`)
/// - Bottom `Viewed` checkbox (`checkbox-viewed`) + `Revert file` (`btn-revert-file`) + Periwinkle `Accept file` (`btn-accept-file`).
public struct TurnDiffReviewViewController: View {
    private enum DiffRowKind {
        case context
        case addition
        case deletion
        case selectedAddition
    }

    private struct DiffCodeRowSpec: Identifiable {
        let id: String
        let lineNumLabel: String
        let prefixSymbol: String
        let codePrefix: String
        let emphasizedSpan: String?
        let codeSuffix: String
        let kind: DiffRowKind
    }

    private struct DiffFilePageSpec {
        let filePath: String
        let additions: Int
        let deletions: Int
    }

    @Bindable public var store: AntigravitySessionStore

    @State private var selectedTurnPill: String = "Turn 3 · latest"
    @State private var currentFileIndex: Int = 0
    @State private var isLine29CommentOpen: Bool = true
    @State private var line29CommentText: String = "Use l.clock.Now() — the plan says to inject the clock so tests can control time."
    @State private var isFileViewed: Bool = false

    private static let periwinkle = Color(red: 0x8E / 255.0, green: 0xB4 / 255.0, blue: 0xFF / 255.0) // #8EB4FF
    private static let emeraldDone = Color(red: 0x57 / 255.0, green: 0xC8 / 255.0, blue: 0x8A / 255.0) // #57C88A
    private static let coralError = Color(red: 0xF0 / 255.0, green: 0x71 / 255.0, blue: 0x67 / 255.0) // #F07167
    private static let inkOnCTA = Color(red: 0x0A / 255.0, green: 0x0E / 255.0, blue: 0x17 / 255.0) // #0A0E17
    private static let cardSurface = Color(red: 0x14 / 255.0, green: 0x15 / 255.0, blue: 0x19 / 255.0) // #141519
    private static let pillBg = Color(red: 0x1A / 255.0, green: 0x1C / 255.0, blue: 0x23 / 255.0)
    private static let commentCardBg = Color(red: 0x17 / 255.0, green: 0x18 / 255.0, blue: 0x1E / 255.0)
    private static let greenLineBg = Color(red: 0x0E / 255.0, green: 0x24 / 255.0, blue: 0x18 / 255.0)
    private static let greenWordBg = Color(red: 0x19 / 255.0, green: 0x45 / 255.0, blue: 0x2B / 255.0)
    private static let redLineBg = Color(red: 0x2A / 255.0, green: 0x13 / 255.0, blue: 0x17 / 255.0)
    private static let redWordBg = Color(red: 0x50 / 255.0, green: 0x1D / 255.0, blue: 0x24 / 255.0)
    private static let selectedBlueBg = Color(red: 0x19 / 255.0, green: 0x26 / 255.0, blue: 0x42 / 255.0)

    private let files: [DiffFilePageSpec] = [
        DiffFilePageSpec(filePath: "middleware/ratelimit.go", additions: 96, deletions: 4),
        DiffFilePageSpec(filePath: "internal/router/transfers.go", additions: 18, deletions: 6),
        DiffFilePageSpec(filePath: "middleware/ratelimit_test.go", additions: 10, deletions: 2),
        DiffFilePageSpec(filePath: "load/transfers.txt", additions: 4, deletions: 2)
    ]

    private let upperRows: [DiffCodeRowSpec] = [
        DiffCodeRowSpec(id: "18", lineNumLabel: "18", prefixSymbol: " ", codePrefix: "type bucket struct {", emphasizedSpan: nil, codeSuffix: "", kind: .context),
        DiffCodeRowSpec(id: "19", lineNumLabel: "19", prefixSymbol: " ", codePrefix: "    tokens float64", emphasizedSpan: nil, codeSuffix: "", kind: .context),
        DiffCodeRowSpec(id: "20", lineNumLabel: "20", prefixSymbol: " ", codePrefix: "    last   time.Time", emphasizedSpan: nil, codeSuffix: "", kind: .context),
        DiffCodeRowSpec(id: "21", lineNumLabel: "21", prefixSymbol: "+", codePrefix: "    mu     sync.Mutex", emphasizedSpan: nil, codeSuffix: "", kind: .addition),
        DiffCodeRowSpec(id: "22", lineNumLabel: "22", prefixSymbol: " ", codePrefix: "}", emphasizedSpan: nil, codeSuffix: "", kind: .context),
        DiffCodeRowSpec(id: "23", lineNumLabel: "23", prefixSymbol: " ", codePrefix: "", emphasizedSpan: nil, codeSuffix: "", kind: .context),
        DiffCodeRowSpec(id: "24-del", lineNumLabel: "24", prefixSymbol: "-", codePrefix: "const ttl = ", emphasizedSpan: "5 * time.Minute", codeSuffix: "", kind: .deletion),
        DiffCodeRowSpec(id: "24-add", lineNumLabel: "24", prefixSymbol: "+", codePrefix: "const ttl = ", emphasizedSpan: "cfg.BucketTTL", codeSuffix: "", kind: .addition),
        DiffCodeRowSpec(id: "25", lineNumLabel: "25", prefixSymbol: " ", codePrefix: "", emphasizedSpan: nil, codeSuffix: "", kind: .context),
        DiffCodeRowSpec(id: "26", lineNumLabel: "26", prefixSymbol: " ", codePrefix: "func (l *Limiter) Allow(tenant string) bool {", emphasizedSpan: nil, codeSuffix: "", kind: .context),
        DiffCodeRowSpec(id: "27", lineNumLabel: "27", prefixSymbol: "+", codePrefix: "    b := l.bucketFor(tenant)", emphasizedSpan: nil, codeSuffix: "", kind: .addition),
        DiffCodeRowSpec(id: "28", lineNumLabel: "28", prefixSymbol: "+", codePrefix: "    b.mu.Lock(); defer b.mu.Unlock()", emphasizedSpan: nil, codeSuffix: "", kind: .addition)
    ]

    private let lowerRows: [DiffCodeRowSpec] = [
        DiffCodeRowSpec(id: "30", lineNumLabel: "30", prefixSymbol: "+", codePrefix: "    elapsed := now.Sub(b.last).Seconds()", emphasizedSpan: nil, codeSuffix: "", kind: .addition),
        DiffCodeRowSpec(id: "31", lineNumLabel: "31", prefixSymbol: "+", codePrefix: "    b.tokens = min(l.burst, b.tokens+elapsed*l.rate)", emphasizedSpan: nil, codeSuffix: "", kind: .addition)
    ]

    public init(store: AntigravitySessionStore) {
        self.store = store
    }

    private var usesLiveDiffs: Bool {
        !store.isVerificationMode && !store.activeTurnDiffs.isEmpty
    }

    private var activeLiveDiff: FilePatchDiff? {
        guard usesLiveDiffs else { return nil }
        return store.activeTurnDiffs[min(max(0, currentFileIndex), store.activeTurnDiffs.count - 1)]
    }

    private var activeFile: DiffFilePageSpec {
        if let live = activeLiveDiff {
            return DiffFilePageSpec(filePath: live.filePath, additions: live.additions, deletions: live.deletions)
        }
        return files[currentFileIndex % files.count]
    }

    public var body: some View {
        VStack(spacing: 0) {
            topNavigationBar

            if !store.isVerificationMode {
                liveCompareModeAndGitBar
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }

            // Turn Selector Strip (`Turn 1`, `Turn 2`, `Turn 3 · latest`, `All`)
            turnSelectorStrip
                .padding(.horizontal, 14)
                .padding(.top, 4)

            // File Pager Card (`< middleware/ratelimit.go (File 1 of 4 · +96 -4) >`)
            filePagerCard
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 8)

            // Hunk Header Bar
            hunkHeaderBar

            // Diff Lines + Inline Comment Composer
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let liveDiff = activeLiveDiff {
                        ForEach(liveDiff.lines) { line in
                            liveDiffLineRow(line, filePath: liveDiff.filePath)
                        }
                        liveGitCommitCard
                            .padding(14)
                    } else {
                        ForEach(upperRows) { row in
                            diffStaticRowView(row)
                        }

                        // Interactive Selected Line 29 (`diff-line-29`)
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isLine29CommentOpen.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("29")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Self.periwinkle)
                                    .frame(width: 24, alignment: .trailing)

                                Text("+")
                                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Self.emeraldDone)
                                    .frame(width: 12)

                                Text("    now := time.Now()")
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(AntigravityTheme.inkReading)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                            .background(Self.selectedBlueBg)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("diff-line-29")

                        // Inline `Comment on line 29` Composer Card (`line-comment-composer`)
                        if isLine29CommentOpen {
                            inlineLine29ComposerCard
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }

                        ForEach(lowerRows) { row in
                            diffStaticRowView(row)
                        }
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Bottom Review Footer (`Viewed` + `Revert file` + `Accept file`)
            bottomReviewActionBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(AntigravityTheme.canvasObsidian)
        .task {
            if !store.isVerificationMode {
                await store.loadLiveArtifactsAndDiffs()
            }
        }
    }

    private var liveCompareModeAndGitBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DiffCompareMode.allCases) { mode in
                    let isSelected = store.diffCompareMode == mode
                    Button {
                        store.setDiffCompareMode(mode)
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? Self.inkOnCTA : AntigravityTheme.inkSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Self.periwinkle : Self.pillBg, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("diff-compare-\(mode.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }

                if let live = activeLiveDiff {
                    let gitSupported = store.isCapabilitySupportedOnActiveHost(.gitVcs)
                    Button {
                        store.toggleStageDiffFile(at: currentFileIndex)
                    } label: {
                        Label(live.isStaged ? "Unstage" : "Stage", systemImage: live.isStaged ? "minus.circle" : "plus.circle")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(gitSupported ? (live.isStaged ? Self.emeraldDone : AntigravityTheme.inkReading) : AntigravityTheme.inkMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Self.pillBg, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!gitSupported)
                    .accessibilityIdentifier("btn-git-stage-toggle")

                    Button {
                        store.discardDiffFile(at: currentFileIndex)
                    } label: {
                        Label("Discard", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(gitSupported ? Self.coralError : AntigravityTheme.inkMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((gitSupported ? Self.coralError : AntigravityTheme.inkMuted).opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!gitSupported)
                    .accessibilityIdentifier("btn-git-discard-file")
                }
            }
        }
    }

    private func liveDiffLineRow(_ line: DiffLine, filePath: String) -> some View {
        let isAdd = line.kind == .addition
        let isDel = line.kind == .deletion
        let lineNum = line.displayLineNumber.map(String.init) ?? ""
        return HStack(spacing: 8) {
            Text(lineNum)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(isDel ? Self.coralError : (isAdd ? Self.emeraldDone : AntigravityTheme.inkSecondary))
                .frame(width: 28, alignment: .trailing)
            Text(isAdd ? "+" : (isDel ? "-" : " "))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(isAdd ? Self.emeraldDone : (isDel ? Self.coralError : .clear))
                .frame(width: 12)
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AntigravityTheme.inkReading)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let num = line.displayLineNumber {
                Button {
                    store.quoteDiffLinesToComposer(filePath: filePath, startLine: num, endLine: num, snippet: line.text)
                } label: {
                    Image(systemName: "text.quote")
                        .font(.system(size: 11))
                        .foregroundStyle(Self.periwinkle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 24)
        .background(isAdd ? Self.greenLineBg : (isDel ? Self.redLineBg : Color.clear))
    }

    private var liveGitCommitCard: some View {
        let gitSupported = store.isCapabilitySupportedOnActiveHost(.gitVcs)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Git Commit & Push", systemImage: "checkmark.seal")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                Spacer()
                if let last = store.lastCommitResult {
                    Text("\(last.commitSha) · \(last.pushed ? "Pushed" : "Local")")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Self.emeraldDone)
                }
            }
            if !gitSupported {
                Text(store.activeHostCapabilities.userFacingUnsupportedMessage(for: .gitVcs))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AntigravityTheme.statusWaiting)
            }
            TextField("Commit message...", text: $store.gitCommitDraft.message)
                .font(.system(size: 14))
                .foregroundStyle(AntigravityTheme.inkReading)
                .padding(10)
                .background(Self.pillBg, in: RoundedRectangle(cornerRadius: 10))
                .disabled(!gitSupported)
                .accessibilityIdentifier("input-git-commit-message")

            HStack(spacing: 12) {
                Toggle("Include Unstaged", isOn: $store.gitCommitDraft.includeUnstaged)
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .tint(Self.periwinkle)
                    .disabled(!gitSupported)
                Toggle("Amend", isOn: $store.gitCommitDraft.amend)
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .tint(Self.periwinkle)
                    .disabled(!gitSupported)
            }

            HStack(spacing: 10) {
                Button("Commit") {
                    Task { _ = await store.commitDiffChanges() }
                }
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(Self.inkOnCTA)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(gitSupported ? Self.periwinkle : Self.pillBg, in: RoundedRectangle(cornerRadius: 12))
                .disabled(!gitSupported || store.gitCommitDraft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("btn-git-commit")

                Button("Push") {
                    Task { _ = await store.pushCurrentDiffBranch() }
                }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(gitSupported ? AntigravityTheme.inkReading : AntigravityTheme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Self.pillBg, in: RoundedRectangle(cornerRadius: 12))
                .disabled(!gitSupported)
                .accessibilityIdentifier("btn-git-push")
            }
        }
        .padding(12)
        .background(Self.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - 1. Top Navigation Bar

    private var topNavigationBar: some View {
        HStack(spacing: 8) {
            Button {
                store.currentRoute = .chatAndComposer
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Self.periwinkle)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-back-from-diff")

            VStack(alignment: .leading, spacing: 2) {
                Text("Review changes")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineLimit(1)
                Text("Add rate limiter to /transfers")
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                for f in files {
                    store.acceptPatchFile(f.filePath)
                }
                store.currentRoute = .chatAndComposer
            } label: {
                Text("Accept all")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .padding(.horizontal, 14)
                    .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                    .background(Self.pillBg)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-accept-all-diffs")

            Button {
                isLine29CommentOpen.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkLabel)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    // MARK: - 2. Turn Selector Strip

    private var turnSelectorStrip: some View {
        let pills: [(label: String, testId: String)] = [
            ("Turn 1", "turn-pill-1"),
            ("Turn 2", "turn-pill-2"),
            ("Turn 3 · latest", "turn-pill-3-latest"),
            ("All", "turn-pill-all")
        ]

        return HStack(spacing: 8) {
            ForEach(pills, id: \.label) { item in
                let isSelected = selectedTurnPill == item.label
                Button {
                    selectedTurnPill = item.label
                } label: {
                    Text(item.label)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(
                            isSelected
                                ? Color(red: 0.04, green: 0.04, blue: 0.05)
                                : AntigravityTheme.inkSecondary
                        )
                        .padding(.horizontal, 12)
                        .frame(minWidth: AntigravityTheme.minTouchTargetPt, minHeight: AntigravityTheme.minTouchTargetPt)
                        .background(isSelected ? Color.white : Self.pillBg)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.testId)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 3. File Pager Card

    private var filePagerCard: some View {
        let totalCount = max(1, usesLiveDiffs ? store.activeTurnDiffs.count : files.count)
        return HStack {
            Button {
                currentFileIndex = (currentFileIndex - 1 + totalCount) % totalCount
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if let live = activeLiveDiff {
                        Text(live.statusLetter.rawValue)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(live.statusLetter == .deleted ? Self.coralError : Self.periwinkle)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Self.pillBg, in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(activeFile.filePath)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text("File \(min(currentFileIndex + 1, totalCount)) of \(totalCount) ·")
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                    Text("+\(activeFile.additions)")
                        .foregroundStyle(Self.emeraldDone)
                    Text("-\(activeFile.deletions)")
                        .foregroundStyle(Self.coralError)
                }
                .font(.system(size: 12))
            }

            Spacer()

            Button {
                currentFileIndex = (currentFileIndex + 1) % totalCount
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .frame(width: AntigravityTheme.minTouchTargetPt, height: AntigravityTheme.minTouchTargetPt)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Self.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("file-pager-card")
    }

    // MARK: - 4. Hunk Header Bar

    private var hunkHeaderBar: some View {
        let headerText = activeLiveDiff?.hunkHeader ?? "@@ -18,9 +18,27 @@ Allow"
        return HStack {
            Text(headerText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AntigravityTheme.inkSecondary)

            Spacer()

            Button {
                if usesLiveDiffs {
                    store.selectedDiffFileIndex = currentFileIndex
                    store.revertCurrentDiffHunk()
                } else {
                    store.composerDraftText = "Revert hunk \(headerText) in \(activeFile.filePath)"
                }
            } label: {
                Text("Revert hunk")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .padding(.horizontal, 10)
                    .frame(minHeight: AntigravityTheme.minTouchTargetPt)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-revert-hunk")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .background(Color(red: 0x10 / 255.0, green: 0x12 / 255.0, blue: 0x17 / 255.0))
        .overlay(alignment: .top) {
            Divider().overlay(Color.white.opacity(0.06))
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.06))
        }
    }

    // MARK: - 5. Diff Lines & Word-Level Emphasis

    private func diffStaticRowView(_ row: DiffCodeRowSpec) -> some View {
        HStack(spacing: 8) {
            Text(row.lineNumLabel)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(
                    row.kind == .deletion
                        ? Self.coralError.opacity(0.85)
                        : (row.kind == .addition ? Self.emeraldDone.opacity(0.85) : AntigravityTheme.inkSecondary)
                )
                .frame(width: 24, alignment: .trailing)

            Text(row.prefixSymbol)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    row.kind == .deletion
                        ? Self.coralError
                        : (row.kind == .addition ? Self.emeraldDone : .clear)
                )
                .frame(width: 12)

            HStack(spacing: 0) {
                Text(row.codePrefix)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineLimit(1)

                if let span = row.emphasizedSpan {
                    Text(span)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .padding(.horizontal, 3)
                        .background(row.kind == .deletion ? Self.redWordBg : Self.greenWordBg)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }

                if !row.codeSuffix.isEmpty {
                    Text(row.codeSuffix)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkReading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 19)
        .background(
            row.kind == .addition
                ? Self.greenLineBg
                : (row.kind == .deletion ? Self.redLineBg : Color.clear)
        )
    }

    // MARK: - 6. Inline `Comment on line 29` Composer Card

    private var inlineLine29ComposerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comment on line 29")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AntigravityTheme.inkSecondary)

            TextField(
                "Write line review comment...",
                text: $line29CommentText,
                axis: .vertical
            )
            .lineLimit(1...3)
            .font(.system(size: 14.5))
            .foregroundStyle(AntigravityTheme.inkReading)

            HStack(spacing: 10) {
                Spacer()

                Button {
                    store.addDiffComment(
                        filePath: activeFile.filePath,
                        lineNumber: 29,
                        text: line29CommentText
                    )
                    isLine29CommentOpen = false
                } label: {
                    Text("Add to review")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.inkReading)
                        .padding(.horizontal, 16)
                        .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-add-to-review")

                Button {
                    store.addDiffComment(
                        filePath: activeFile.filePath,
                        lineNumber: 29,
                        text: line29CommentText
                    )
                    store.composerDraftText = "\(activeFile.filePath):29 — \(line29CommentText)"
                    store.sendCurrentDraft()
                    store.currentRoute = .chatAndComposer
                } label: {
                    Text("Send to agent")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Self.inkOnCTA)
                        .padding(.horizontal, 16)
                        .frame(minHeight: AntigravityTheme.minTouchTargetPt)
                        .background(Self.periwinkle)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-send-to-agent")
            }
        }
        .padding(12)
        .background(Self.commentCardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("line-comment-composer")
    }

    // MARK: - 7. Bottom Review Action Bar

    private var bottomReviewActionBar: some View {
        HStack(spacing: 10) {
            Button {
                isFileViewed.toggle()
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isFileViewed ? Self.periwinkle : Color.white)
                            .frame(width: 20, height: 20)
                        if isFileViewed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Self.inkOnCTA)
                        }
                    }

                    Text("Viewed")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                }
                .frame(minWidth: AntigravityTheme.minTouchTargetPt, minHeight: AntigravityTheme.minTouchTargetPt)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("checkbox-viewed")

            Spacer()

            Button {
                store.composerDraftText = "Please revert \(activeFile.filePath)."
                store.sendCurrentDraft()
                store.currentRoute = .chatAndComposer
            } label: {
                Text("Revert file")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
                    .background(Self.pillBg)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-revert-file")

            Button {
                store.acceptPatchFile(activeFile.filePath)
                isFileViewed = true
            } label: {
                Text("Accept file")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Self.inkOnCTA)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
                    .background(Self.periwinkle)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-accept-file")
        }
    }
}
