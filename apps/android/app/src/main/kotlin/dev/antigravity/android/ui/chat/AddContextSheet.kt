package dev.antigravity.android.ui.chat

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AlternateEmail
import androidx.compose.material.icons.rounded.AttachFile
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CloudQueue
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.android.ui.home.AgentsHomeScreen
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.ContextCandidateCategory
import dev.antigravity.shared.model.localizedTitle
import kotlinx.coroutines.launch

/**
 * UE08_ADD_CONTEXT (`and-add-context.png`): Anchored Material 3 Add Context menu above the `+` button
 * (`Photos`, `Device Files`, `Files >`, `Folder >`, `Mentions >`, `Actions >`, `Drive [Set up]`),
 * with permissionless Android Photo Picker (`PickMultipleVisualMedia`) and interactive drill-down
 * into the multi-select file/folder/mention/skill picker.
 */
@Composable
fun AddContextSheetScreen(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    showHomeBackdrop: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val lang = LocalAppLanguage.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val workspaceState by coordinator.workspaceStore.state.collectAsState()
    val connectionState by coordinator.connectionState.collectAsState()
    val hostName = connectionState.activeHost?.hostname?.takeIf { it.isNotBlank() } ?: "MacBook Pro"

    var drilldownCategory by remember { mutableStateOf<ContextCandidateCategory?>(null) }
    var searchQuery by remember { mutableStateOf("") }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia(maxItems = 5),
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scope.launch {
            val existingLabels = coordinator.workspaceStore.state.value.attachedComposerChips
                .mapTo(mutableSetOf()) { it.label }
            for (uri in uris) {
                val chip = runCatching {
                    loadMediaAttachmentFromUri(
                        context = context,
                        uri = uri,
                        existingLabels = existingLabels,
                        preferImageKind = true,
                    )
                }.getOrNull()
                if (chip != null) {
                    existingLabels.add(chip.label)
                    coordinator.workspaceStore.addComposerChip(chip)
                }
            }
            onDismiss()
        }
    }

    val deviceFilePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scope.launch {
            val existingLabels = coordinator.workspaceStore.state.value.attachedComposerChips
                .mapTo(mutableSetOf()) { it.label }
            for (uri in uris) {
                val chip = runCatching {
                    loadMediaAttachmentFromUri(
                        context = context,
                        uri = uri,
                        existingLabels = existingLabels,
                        preferImageKind = false,
                    )
                }.getOrNull()
                if (chip != null) {
                    existingLabels.add(chip.label)
                    coordinator.workspaceStore.addComposerChip(chip)
                }
            }
            onDismiss()
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(if (showHomeBackdrop) colors.canvasObsidian else Color.Transparent),
    ) {
        if (showHomeBackdrop) {
            AgentsHomeScreen(
                coordinator = coordinator,
                onOpenSidebar = {},
                onOpenConversation = {},
                highlightAddContextButton = true,
                showNeedsApprovalBanner = false,
                showSearchAction = false,
                showHostChevron = false,
                modifier = Modifier.fillMaxSize(),
            )
        }

        // Scrim to dismiss
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = if (drilldownCategory != null) 0.56f else 0.14f))
                .clickable(onClick = onDismiss),
        )

        if (drilldownCategory == null) {
            // Anchored Popover Menu matching `and-add-context.png`
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .navigationBarsPadding()
                    .padding(start = 18.dp, bottom = 140.dp)
                    .width(256.dp)
                    .testTag("add-context-popover"),
                shape = RoundedCornerShape(18.dp),
                color = colors.surfacePopover,
                border = BorderStroke(1.dp, colors.cardBorder),
                shadowElevation = 12.dp,
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 10.dp),
                ) {
                    Text(
                        text = tr("Add Context", "添加上下文"),
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                        color = colors.inkSecondary,
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 6.dp),
                    )

                    if (!coordinator.isVerificationMode) {
                        AddContextMenuRow(
                            icon = Icons.Rounded.PhotoLibrary,
                            label = tr("Photos", "相册照片"),
                            onClick = {
                                photoPickerLauncher.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                                )
                            },
                            modifier = Modifier.testTag("ctx-menu-photos"),
                        )
                        AddContextMenuRow(
                            icon = Icons.Rounded.AttachFile,
                            label = tr("Device Files", "本地文件"),
                            onClick = {
                                deviceFilePickerLauncher.launch(arrayOf("image/*", "application/pdf", "*/*"))
                            },
                            modifier = Modifier.testTag("ctx-menu-device-file"),
                        )
                        HorizontalDivider(
                            modifier = Modifier.padding(vertical = 4.dp),
                            color = colors.subtleDivider,
                        )
                    }

                    AddContextMenuRow(
                        icon = Icons.Rounded.Description,
                        label = tr("Files", "文件"),
                        onClick = { drilldownCategory = ContextCandidateCategory.FILES },
                        modifier = Modifier.testTag("ctx-menu-files"),
                    )
                    AddContextMenuRow(
                        icon = Icons.Rounded.Folder,
                        label = tr("Folder", "文件夹"),
                        onClick = { drilldownCategory = ContextCandidateCategory.FOLDER },
                        modifier = Modifier.testTag("ctx-menu-folder"),
                    )
                    AddContextMenuRow(
                        icon = Icons.Rounded.AlternateEmail,
                        label = tr("Mentions", "引用"),
                        onClick = { drilldownCategory = ContextCandidateCategory.MENTIONS },
                        modifier = Modifier.testTag("ctx-menu-mentions"),
                    )
                    AddContextMenuRow(
                        icon = Icons.Rounded.Terminal,
                        label = tr("Actions", "操作"),
                        onClick = { drilldownCategory = ContextCandidateCategory.ACTIONS },
                        modifier = Modifier.testTag("ctx-menu-actions"),
                    )

                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 6.dp),
                        color = colors.subtleDivider,
                    )

                    // Drive row with `Set up` trailing CTA
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { drilldownCategory = ContextCandidateCategory.DRIVE }
                            .padding(horizontal = 18.dp, vertical = 12.dp)
                            .testTag("ctx-menu-drive"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.CloudQueue,
                            contentDescription = null,
                            tint = colors.inkLabel,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = tr("Drive", "云端硬盘"),
                            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                            color = colors.inkReading,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            text = tr("Set up", "去配置"),
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 13.5.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.accentPeriwinkle,
                        )
                    }

                    Text(
                        text = tr(
                            "Files and folders come from $hostName",
                            "文件和文件夹来自 $hostName",
                        ),
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, lineHeight = 16.sp),
                        color = colors.inkMuted,
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 8.dp),
                    )
                }
            }
        } else {
            // Interactive multi-select drilldown sheet when a category is chosen
            val filtered = remember(workspaceState.contextCandidates, drilldownCategory, searchQuery) {
                val q = searchQuery.trim().lowercase()
                workspaceState.contextCandidates
                    .distinctBy { it.id }
                    .filter { item ->
                        val catMatch = drilldownCategory == null || item.category == drilldownCategory
                        val qMatch = q.isEmpty() || item.title.lowercase().contains(q) || item.subtitle.lowercase().contains(q)
                        catMatch && qMatch
                    }
            }
            val selectedCount = workspaceState.contextCandidates.count { it.isSelected }

            Surface(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .testTag("add-context-picker-sheet"),
                shape = RoundedCornerShape(
                    topStart = AntigravityDesignTokens.SheetCornerRadius,
                    topEnd = AntigravityDesignTokens.SheetCornerRadius,
                ),
                color = colors.surfaceSheet,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = drilldownCategory?.localizedTitle(lang) ?: tr("Add Context", "添加上下文"),
                            style = MaterialTheme.typography.titleLarge,
                            color = colors.inkReading,
                            modifier = Modifier.weight(1f),
                        )
                        IconButton(onClick = { drilldownCategory = null }) {
                            Icon(
                                Icons.Rounded.Close,
                                contentDescription = tr("Back to categories", "返回分类"),
                                tint = colors.inkSecondary,
                            )
                        }
                    }

                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(100.dp),
                        color = colors.surfaceElevated,
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.inkSecondary, modifier = Modifier.size(18.dp))
                            val searchHint = tr("Search...", "搜索…")
                            BasicTextField(
                                value = searchQuery,
                                onValueChange = { searchQuery = it },
                                modifier = Modifier.weight(1f).testTag("input-context-search"),
                                singleLine = true,
                                textStyle = MaterialTheme.typography.bodyMedium.copy(color = colors.inkReading),
                                cursorBrush = SolidColor(colors.accentPeriwinkle),
                                decorationBox = { inner ->
                                    if (searchQuery.isEmpty()) Text(searchHint, color = colors.inkMuted)
                                    inner()
                                },
                            )
                        }
                    }

                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(240.dp)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        filtered.forEach { item ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { coordinator.workspaceStore.toggleContextCandidate(item.id) }
                                    .padding(vertical = 6.dp)
                                    .testTag("context-candidate-${item.id}"),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Checkbox(
                                    checked = item.isSelected,
                                    onCheckedChange = { coordinator.workspaceStore.toggleContextCandidate(item.id) },
                                    colors = CheckboxDefaults.colors(
                                        checkedColor = colors.accentPeriwinkle,
                                        checkmarkColor = colors.inkOnPrimaryCta,
                                    ),
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = item.title,
                                        style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                                        color = colors.inkReading,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        text = item.subtitle,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = colors.inkSecondary,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
                    }

                    Button(
                        onClick = {
                            coordinator.workspaceStore.applySelectedContextToComposer()
                            onDismiss()
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = 48.dp)
                            .testTag("btn-add-context-apply"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.accentPeriwinkle,
                            contentColor = colors.inkOnPrimaryCta,
                        ),
                    ) {
                        Text(
                            text = if (selectedCount > 0) {
                                tr("Add to message ($selectedCount)", "添加到消息（$selectedCount）")
                            } else {
                                tr("Done", "完成")
                            },
                            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AddContextMenuRow(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = colors.inkLabel,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
            color = colors.inkReading,
            modifier = Modifier.weight(1f),
        )
        Icon(
            imageVector = Icons.Rounded.ChevronRight,
            contentDescription = null,
            tint = colors.inkMuted,
            modifier = Modifier.size(18.dp),
        )
    }
}
