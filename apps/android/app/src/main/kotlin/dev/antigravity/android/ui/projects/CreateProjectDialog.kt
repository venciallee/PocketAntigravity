package dev.antigravity.android.ui.projects

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
 * UE05_CREATE_PROJECT (`and-new-project.png`): Material 3 Full-Screen Dialog matching
 * `and-new-project.png` with top-right primary Create pill, SegmentedButton runtime picker,
 * FilterChip source toggles, RadioButton repo list, Branch dropdown, New worktree switch, and Name field.
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
    var selectedBranch by remember { mutableStateOf("main") }
    var branchMenuExpanded by remember { mutableStateOf(false) }
    var newWorktreeEnabled by remember { mutableStateOf(true) }
    var projectName by remember {
        mutableStateOf(
            workspaceState.newProjectDraft.projectName
                .ifBlank { "ledger-svc" }
                .removeSuffix("-cloud"),
        )
    }

    val filteredRepos = remember(repos, repoSearchQuery) {
        val q = repoSearchQuery.trim().lowercase()
        if (q.isEmpty()) repos else repos.filter { it.fullName.lowercase().contains(q) }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        // 1. Top Full-Screen Dialog Header: X | New project | [Create]
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconButton(
                onClick = onDismiss,
                modifier = Modifier
                    .size(AntigravityDesignTokens.MinTouchTarget)
                    .testTag("btn-cancel-create-project"),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Close,
                    contentDescription = "Close",
                    tint = colors.inkReading,
                )
            }

            Text(
                text = "New project",
                style = MaterialTheme.typography.headlineSmall.copy(
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Normal,
                ),
                color = colors.inkReading,
                modifier = Modifier.weight(1f),
            )

            Button(
                onClick = {
                    val trimmedName = projectName.trim().ifBlank { "ledger-svc-cloud" }
                    val draft = NewProjectDraft(
                        runsOn = runsOn,
                        source = sourceKind,
                        repoSearchQuery = repoSearchQuery,
                        selectedRepo = selectedRepo,
                        branchWorktree = if (newWorktreeEnabled) "$selectedBranch · New worktree" else selectedBranch,
                        projectName = trimmedName,
                    )
                    coordinator.workspaceStore.updateNewProjectDraft { draft }
                    scope.launch(start = CoroutineStart.UNDISPATCHED) {
                        val rpcClient = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                        coordinator.workspaceStore.createProject(client = rpcClient, draft = draft)
                    }
                    onCreated()
                },
                modifier = Modifier
                    .defaultMinSize(minHeight = 42.dp)
                    .testTag("btn-create-project-submit"),
                shape = RoundedCornerShape(100.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.accentPeriwinkle,
                    contentColor = colors.inkOnPrimaryCta,
                ),
            ) {
                Text(
                    text = "Create",
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                )
            }
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 6.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Runs on
            Text(
                text = "Runs on",
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                color = colors.accentPeriwinkle,
            )

            SingleChoiceSegmentedButtonRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("runtime-segmented-row"),
            ) {
                SegmentedButton(
                    selected = runsOn == ProjectRuntimeTarget.MAC_BOOK_PRO,
                    onClick = { runsOn = ProjectRuntimeTarget.MAC_BOOK_PRO },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                    icon = {
                        if (runsOn == ProjectRuntimeTarget.MAC_BOOK_PRO) {
                            Icon(Icons.Rounded.Check, contentDescription = null, modifier = Modifier.size(16.dp))
                        } else {
                            Icon(Icons.Rounded.Computer, contentDescription = null, modifier = Modifier.size(16.dp))
                        }
                    },
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = colors.surfaceActiveTab,
                        activeContentColor = colors.pillActiveForeground,
                        inactiveContainerColor = colors.canvasObsidian,
                        inactiveContentColor = colors.inkReading,
                        activeBorderColor = colors.cardBorder,
                        inactiveBorderColor = colors.cardBorder,
                    ),
                    modifier = Modifier.testTag("runtime-mac"),
                ) {
                    Text("MacBook Pro", maxLines = 1)
                }

                SegmentedButton(
                    selected = runsOn == ProjectRuntimeTarget.CLOUD,
                    onClick = { runsOn = ProjectRuntimeTarget.CLOUD },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                    icon = {
                        if (runsOn == ProjectRuntimeTarget.CLOUD) {
                            Icon(Icons.Rounded.Check, contentDescription = null, modifier = Modifier.size(16.dp))
                        }
                    },
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = colors.surfaceActiveTab,
                        activeContentColor = colors.pillActiveForeground,
                        inactiveContainerColor = colors.canvasObsidian,
                        inactiveContentColor = colors.inkReading,
                        activeBorderColor = colors.cardBorder,
                        inactiveBorderColor = colors.cardBorder,
                    ),
                    modifier = Modifier.testTag("runtime-cloud"),
                ) {
                    Text("Cloud", maxLines = 1)
                }
            }

            Text(
                text = if (runsOn == ProjectRuntimeTarget.CLOUD) {
                    "Runs in its own cloud VM and keeps working while your computer sleeps."
                } else {
                    "Runs directly on your paired MacBook Pro with local filesystem access."
                },
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp, lineHeight = 19.sp),
                color = colors.inkSecondary,
            )

            Spacer(modifier = Modifier.height(4.dp))

            // Source
            Text(
                text = "Source",
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                color = colors.accentPeriwinkle,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FilterChip(
                    selected = sourceKind == ProjectSourceKind.GITHUB_REPO,
                    onClick = { sourceKind = ProjectSourceKind.GITHUB_REPO },
                    label = { Text("GitHub repository") },
                    leadingIcon = if (sourceKind == ProjectSourceKind.GITHUB_REPO) {
                        { Icon(Icons.Rounded.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
                    } else null,
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = colors.surfaceActiveTab,
                        selectedLabelColor = colors.pillActiveForeground,
                        selectedLeadingIconColor = colors.pillActiveForeground,
                        containerColor = colors.canvasObsidian,
                        labelColor = colors.inkReading,
                    ),
                    border = FilterChipDefaults.filterChipBorder(
                        enabled = true,
                        selected = sourceKind == ProjectSourceKind.GITHUB_REPO,
                        borderColor = colors.cardBorder,
                        selectedBorderColor = colors.surfaceActiveTab,
                    ),
                    modifier = Modifier.testTag("source-github"),
                )

                FilterChip(
                    selected = sourceKind == ProjectSourceKind.DRIVE_FOLDER,
                    onClick = { sourceKind = ProjectSourceKind.DRIVE_FOLDER },
                    label = { Text("Drive folder") },
                    leadingIcon = if (sourceKind == ProjectSourceKind.DRIVE_FOLDER) {
                        { Icon(Icons.Rounded.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
                    } else null,
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = colors.surfaceActiveTab,
                        selectedLabelColor = colors.pillActiveForeground,
                        selectedLeadingIconColor = colors.pillActiveForeground,
                        containerColor = colors.canvasObsidian,
                        labelColor = colors.inkReading,
                    ),
                    border = FilterChipDefaults.filterChipBorder(
                        enabled = true,
                        selected = sourceKind == ProjectSourceKind.DRIVE_FOLDER,
                        borderColor = colors.cardBorder,
                        selectedBorderColor = colors.surfaceActiveTab,
                    ),
                    modifier = Modifier.testTag("source-drive"),
                )
            }

            // Rounded Search repositories pill
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(100.dp),
                color = colors.surfaceCard,
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Search,
                        contentDescription = null,
                        tint = colors.inkSecondary,
                        modifier = Modifier.size(20.dp),
                    )
                    BasicTextField(
                        value = repoSearchQuery,
                        onValueChange = { repoSearchQuery = it },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("input-repo-search"),
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.inkReading),
                        cursorBrush = SolidColor(colors.accentPeriwinkle),
                        decorationBox = { inner ->
                            if (repoSearchQuery.isEmpty()) {
                                Text(
                                    text = "Search repositories",
                                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp),
                                    color = colors.inkMuted,
                                )
                            }
                            inner()
                        },
                    )
                }
            }

            // RadioButton Repo List
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                filteredRepos.forEach { repo ->
                    val isSelected = selectedRepo?.id == repo.id
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                selectedRepo = repo
                                projectName = repo.fullName.substringAfter("/")
                            }
                            .padding(vertical = 8.dp)
                            .testTag("repo-row-${repo.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        RadioButton(
                            selected = isSelected,
                            onClick = {
                                selectedRepo = repo
                                projectName = repo.fullName.substringAfter("/")
                            },
                            colors = RadioButtonDefaults.colors(
                                selectedColor = colors.accentPeriwinkle,
                                unselectedColor = colors.inkSecondary,
                            ),
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                text = repo.fullName,
                                style = MaterialTheme.typography.bodyLarge.copy(
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 15.5.sp,
                                ),
                                color = colors.inkReading,
                            )
                            Text(
                                text = repo.visibilityLabel,
                                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                                color = colors.inkSecondary,
                            )
                        }
                    }
                }
            }

            Text(
                text = buildAnnotatedString {
                    withStyle(SpanStyle(color = colors.inkSecondary)) {
                        append("Missing a repo? ")
                    }
                    withStyle(SpanStyle(color = colors.accentPeriwinkle, fontWeight = FontWeight.Medium)) {
                        append("Configure on GitHub")
                    }
                },
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
            )

            Spacer(modifier = Modifier.height(4.dp))

            // Branch & worktree
            Text(
                text = "Branch & worktree",
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                color = colors.accentPeriwinkle,
            )

            Box(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = selectedBranch,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Branch") },
                    trailingIcon = {
                        Icon(
                            imageVector = Icons.Rounded.ArrowDropDown,
                            contentDescription = "Select branch",
                            tint = colors.inkSecondary,
                        )
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { branchMenuExpanded = true }
                        .testTag("input-project-branch"),
                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                        fontFamily = FontFamily.Monospace,
                        color = colors.inkReading,
                    ),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = colors.accentPeriwinkle,
                        unfocusedBorderColor = colors.cardBorder,
                        focusedLabelColor = colors.accentPeriwinkle,
                        unfocusedLabelColor = colors.inkSecondary,
                        focusedContainerColor = colors.canvasObsidian,
                        unfocusedContainerColor = colors.canvasObsidian,
                    ),
                )
                Box(
                    modifier = Modifier
                        .matchParentSize()
                        .clickable { branchMenuExpanded = true },
                )
                DropdownMenu(
                    expanded = branchMenuExpanded,
                    onDismissRequest = { branchMenuExpanded = false },
                    containerColor = colors.surfacePopover,
                ) {
                    listOf("main", "develop", "feat/ratelimit").forEach { br ->
                        DropdownMenuItem(
                            text = { Text(br, color = colors.inkReading, fontFamily = FontFamily.Monospace) },
                            onClick = {
                                selectedBranch = br
                                branchMenuExpanded = false
                            },
                        )
                    }
                }
            }

            // New worktree Switch row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { newWorktreeEnabled = !newWorktreeEnabled }
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "New worktree",
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                        color = colors.inkReading,
                    )
                    Text(
                        text = "Keep this project's changes off your checkout",
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = colors.inkSecondary,
                    )
                }
                Switch(
                    checked = newWorktreeEnabled,
                    onCheckedChange = { newWorktreeEnabled = it },
                    modifier = Modifier.testTag("switch-new-worktree"),
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = colors.inkOnPrimaryCta,
                        checkedTrackColor = colors.accentPeriwinkle,
                        uncheckedThumbColor = colors.inkSecondary,
                        uncheckedTrackColor = colors.surfaceElevated,
                    ),
                )
            }

            // Project Name OutlinedTextField (highlighted periwinkle outline matching `and-new-project.png`)
            OutlinedTextField(
                value = projectName,
                onValueChange = { projectName = it },
                label = { Text("Name") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("input-project-name"),
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.inkReading),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = colors.accentPeriwinkle,
                    unfocusedBorderColor = colors.accentPeriwinkle,
                    focusedLabelColor = colors.accentPeriwinkle,
                    unfocusedLabelColor = colors.accentPeriwinkle,
                    focusedContainerColor = colors.canvasObsidian,
                    unfocusedContainerColor = colors.canvasObsidian,
                ),
            )
        }
    }
}

private val defaultFallbackRepos = listOf(
    GitHubRepoItem(
        id = "repo-ledger-svc",
        fullName = "acme/ledger-svc",
        visibilityLabel = "Private · Go · updated 2h ago",
        defaultBranch = "main",
    ),
    GitHubRepoItem(
        id = "repo-web-console",
        fullName = "acme/web-console",
        visibilityLabel = "Private · TypeScript · updated 1d ago",
        defaultBranch = "main",
    ),
    GitHubRepoItem(
        id = "repo-design-tokens",
        fullName = "acme/design-tokens",
        visibilityLabel = "Public · updated 5d ago",
        defaultBranch = "main",
    ),
)
