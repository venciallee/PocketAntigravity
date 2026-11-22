package dev.antigravity.android.ui.projects

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.SectionHeaderLabel
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.GitHubRepoItem
import dev.antigravity.shared.model.NewProjectDraft
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectSourceKind
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/**
 * UE05_CREATE_PROJECT: Material 3 Full-Screen Dialog for creating a local (MacBook Pro)
 * or Cloud VM workspace from a GitHub repository or Drive folder.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateProjectScreen(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    onCreated: () -> Unit = onDismiss,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    val repos = remember(workspaceState.availableRepos) {
        workspaceState.availableRepos.ifEmpty { defaultFallbackRepos }
    }

    var runsOn by remember { mutableStateOf(workspaceState.newProjectDraft.runsOn) }
    var sourceKind by remember { mutableStateOf(workspaceState.newProjectDraft.source) }
    var repoSearchQuery by remember { mutableStateOf(workspaceState.newProjectDraft.repoSearchQuery) }
    var selectedRepo by remember {
        mutableStateOf(workspaceState.newProjectDraft.selectedRepo ?: repos.firstOrNull())
    }
    var branchWorktree by remember { mutableStateOf(workspaceState.newProjectDraft.branchWorktree) }
    var projectName by remember { mutableStateOf(workspaceState.newProjectDraft.projectName) }

    val filteredRepos = remember(repos, repoSearchQuery) {
        val q = repoSearchQuery.trim().lowercase()
        if (q.isEmpty()) repos else repos.filter { it.fullName.lowercase().contains(q) }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.surfaceSheet),
    ) {
        // 1. M3 Full-Screen Dialog Header Bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(
                onClick = onDismiss,
                modifier = Modifier
                    .defaultMinSize(minWidth = 72.dp, minHeight = AntigravityDesignTokens.MinTouchTarget)
                    .testTag("btn-cancel-project"),
            ) {
                Text(
                    text = "Cancel",
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontSize = 15.5.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    color = colors.inkSecondary,
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Text(
                text = "New Project",
                style = MaterialTheme.typography.titleMedium.copy(
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                ),
                color = colors.inkReading,
                maxLines = 1,
            )

            Spacer(modifier = Modifier.weight(1f))

            Spacer(modifier = Modifier.width(72.dp))
        }

        HorizontalDivider(color = colors.subtleDivider)

        // Scrollable Dialog Form Body
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // 2. RUNS ON Material 3 SingleChoiceSegmentedButtonRow
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SectionHeaderLabel(title = "RUNS ON")

                val runTargets = listOf(
                    Triple(ProjectRuntimeTarget.MAC_BOOK_PRO, Icons.Rounded.Computer, "seg-runs-on-mac"),
                    Triple(ProjectRuntimeTarget.CLOUD, Icons.Rounded.Cloud, "seg-runs-on-cloud"),
                )
                SingleChoiceSegmentedButtonRow(
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    runTargets.forEachIndexed { index, (target, icon, tag) ->
                        val isSelected = runsOn == target
                        SegmentedButton(
                            selected = isSelected,
                            onClick = {
                                runsOn = target
                                val repoSlug = selectedRepo?.fullName?.substringAfterLast('/')
                                if (!repoSlug.isNullOrBlank()) {
                                    projectName = if (target == ProjectRuntimeTarget.CLOUD) {
                                        "$repoSlug-cloud"
                                    } else {
                                        repoSlug
                                    }
                                }
                            },
                            shape = SegmentedButtonDefaults.itemShape(index = index, count = runTargets.size),
                            modifier = Modifier
                                .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                                .testTag(tag),
                            colors = SegmentedButtonDefaults.colors(
                                activeContainerColor = colors.surfaceActiveTab,
                                activeContentColor = colors.inkReading,
                                activeBorderColor = colors.cardBorder,
                                inactiveContainerColor = colors.surfaceSheetGroup,
                                inactiveContentColor = colors.inkSecondary,
                                inactiveBorderColor = colors.cardBorder,
                            ),
                            icon = {
                                Icon(
                                    imageVector = icon,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                )
                            },
                            label = {
                                Text(
                                    text = target.displayTitle,
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    softWrap = false,
                                )
                            },
                        )
                    }
                }

                Text(
                    text = runsOn.descriptionText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.inkSecondary,
                )
            }

            // 3. SOURCE Dual Selectable Cards
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SectionHeaderLabel(title = "SOURCE")

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    SourceOptionCard(
                        title = ProjectSourceKind.GITHUB_REPO.displayTitle,
                        icon = Icons.Rounded.AccountTree,
                        selected = sourceKind == ProjectSourceKind.GITHUB_REPO,
                        modifier = Modifier
                            .weight(1f)
                            .testTag("source-card-github"),
                        onClick = { sourceKind = ProjectSourceKind.GITHUB_REPO },
                    )
                    SourceOptionCard(
                        title = ProjectSourceKind.DRIVE_FOLDER.displayTitle,
                        icon = Icons.Rounded.Folder,
                        selected = sourceKind == ProjectSourceKind.DRIVE_FOLDER,
                        modifier = Modifier
                            .weight(1f)
                            .testTag("source-card-drive"),
                        onClick = { sourceKind = ProjectSourceKind.DRIVE_FOLDER },
                    )
                }
            }

            // 4. Repository Search Field
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget),
                shape = RoundedCornerShape(14.dp),
                color = colors.surfaceSheetGroup,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Search,
                        contentDescription = null,
                        tint = colors.inkMuted,
                        modifier = Modifier.size(18.dp),
                    )
                    Box(modifier = Modifier.weight(1f)) {
                        if (repoSearchQuery.isEmpty()) {
                            Text(
                                text = if (sourceKind == ProjectSourceKind.DRIVE_FOLDER) {
                                    "Search Drive folders"
                                } else {
                                    "Search repositories"
                                },
                                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                                color = colors.inkMuted,
                                maxLines = 1,
                            )
                        }
                        BasicTextField(
                            value = repoSearchQuery,
                            onValueChange = { repoSearchQuery = it },
                            singleLine = true,
                            textStyle = MaterialTheme.typography.bodyLarge.copy(
                                fontSize = 15.sp,
                                color = colors.inkReading,
                            ),
                            cursorBrush = SolidColor(colors.accentPeriwinkle),
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("repo-search-input"),
                        )
                    }
                }
            }

            // 5. Selectable Repository List Card
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                color = colors.surfaceSheetGroup,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    if (filteredRepos.isEmpty()) {
                        Text(
                            text = "No repositories match \"$repoSearchQuery\"",
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.inkSecondary,
                            modifier = Modifier.padding(16.dp),
                        )
                    } else {
                        filteredRepos.forEachIndexed { index, repo ->
                            val slug = repo.fullName.substringAfterLast('/')
                            val isSelected = selectedRepo?.id == repo.id ||
                                selectedRepo?.fullName == repo.fullName
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .defaultMinSize(minHeight = 52.dp)
                                    .clickable {
                                        selectedRepo = repo
                                        projectName = if (runsOn == ProjectRuntimeTarget.CLOUD) {
                                            "$slug-cloud"
                                        } else {
                                            slug
                                        }
                                    }
                                    .padding(horizontal = 14.dp, vertical = 10.dp)
                                    .testTag("repo-row-$slug"),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Column(
                                    modifier = Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(2.dp),
                                ) {
                                    Text(
                                        text = repo.fullName,
                                        style = MaterialTheme.typography.titleSmall.copy(
                                            fontFamily = FontFamily.Monospace,
                                            fontWeight = FontWeight.Medium,
                                        ),
                                        color = colors.inkReading,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        text = repoMetadataLine(repo),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = colors.inkSecondary,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                                if (isSelected) {
                                    Icon(
                                        imageVector = Icons.Rounded.Check,
                                        contentDescription = "Selected repository",
                                        tint = colors.accentPeriwinkle,
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                            }
                            if (index < filteredRepos.lastIndex) {
                                HorizontalDivider(color = colors.subtleDivider)
                            }
                        }
                    }
                }
            }

            Text(
                text = "Missing a repo? Configure on GitHub",
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Medium),
                color = colors.accentPeriwinkle,
                modifier = Modifier.padding(start = 2.dp),
            )

            // 6. Branch & Worktree + Editable Project Name Card
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                color = colors.surfaceSheetGroup,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .clickable {
                                branchWorktree = if (branchWorktree == "main · New worktree") {
                                    "main · Existing checkout"
                                } else {
                                    "main · New worktree"
                                }
                            }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "Branch & worktree",
                            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                            color = colors.inkReading,
                        )
                        Spacer(modifier = Modifier.weight(1f))
                        Text(
                            text = branchWorktree,
                            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                            color = colors.inkSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Icon(
                            imageVector = Icons.Rounded.UnfoldMore,
                            contentDescription = null,
                            tint = colors.inkMuted,
                            modifier = Modifier.size(16.dp),
                        )
                    }

                    HorizontalDivider(color = colors.subtleDivider)

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            text = "Name",
                            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                            color = colors.inkReading,
                        )
                        BasicTextField(
                            value = projectName,
                            onValueChange = { projectName = it },
                            singleLine = true,
                            textStyle = MaterialTheme.typography.bodyLarge.copy(
                                fontSize = 14.5.sp,
                                color = colors.inkLabel,
                                textAlign = TextAlign.End,
                            ),
                            cursorBrush = SolidColor(colors.accentPeriwinkle),
                            modifier = Modifier
                                .weight(1f)
                                .testTag("project-name-input"),
                        )
                    }
                }
            }
        }

        // 7. Bottom Docked Full-Width Periwinkle CTA Button
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
        ) {
            Button(
                onClick = {
                    val draft = NewProjectDraft(
                        runsOn = runsOn,
                        source = sourceKind,
                        repoSearchQuery = repoSearchQuery,
                        selectedRepo = selectedRepo,
                        branchWorktree = branchWorktree,
                        projectName = projectName.trim().ifEmpty { "ledger-svc-cloud" },
                    )
                    coordinator.workspaceStore.updateNewProjectDraft { draft }
                    scope.launch(start = CoroutineStart.UNDISPATCHED) {
                        val rpcClient = if (coordinator.isVerificationMode) {
                            null
                        } else {
                            coordinator.connectionStore.activeClient()
                        }
                        coordinator.workspaceStore.createProject(client = rpcClient, draft = draft)
                        onCreated()
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 52.dp)
                    .testTag("btn-submit-create-project"),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.accentPeriwinkle,
                    contentColor = colors.inkOnPrimaryCta,
                ),
                contentPadding = PaddingValues(vertical = 14.dp),
            ) {
                Text(
                    text = "Create Project",
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                )
            }
        }
    }
}

@Composable
private fun SourceOptionCard(
    title: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    Surface(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minHeight = 72.dp),
        shape = RoundedCornerShape(16.dp),
        color = if (selected) colors.surfaceSelectionTint else colors.surfaceSheetGroup,
        border = BorderStroke(
            width = if (selected) 1.5.dp else 1.dp,
            color = if (selected) colors.accentPeriwinkle else colors.cardBorder,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.Start,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (selected) colors.accentPeriwinkle else colors.inkSecondary,
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall.copy(
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                ),
                color = colors.inkReading,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

private fun repoMetadataLine(repo: GitHubRepoItem): String = when (repo.fullName) {
    "acme/ledger-svc" -> "${repo.visibilityLabel} · Go · updated 2h ago"
    "acme/web-console" -> "${repo.visibilityLabel} · TypeScript · updated 1d ago"
    "acme/design-tokens" -> "${repo.visibilityLabel} · updated 5d ago"
    else -> "${repo.visibilityLabel} · ${repo.defaultBranch}"
}

private val defaultFallbackRepos: List<GitHubRepoItem> = listOf(
    GitHubRepoItem(id = "repo-ledger-svc", fullName = "acme/ledger-svc", visibilityLabel = "Private", defaultBranch = "main"),
    GitHubRepoItem(id = "repo-web-console", fullName = "acme/web-console", visibilityLabel = "Private", defaultBranch = "main"),
    GitHubRepoItem(id = "repo-design-tokens", fullName = "acme/design-tokens", visibilityLabel = "Public", defaultBranch = "main"),
)
