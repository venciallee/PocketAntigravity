package dev.antigravity.android.core.ui.icons

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Brush
import androidx.compose.material.icons.rounded.Category
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.DeviceHub
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.FindInPage
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.PriorityHigh
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.QuestionAnswer
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.VerifiedUser
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.Widgets
import androidx.compose.ui.graphics.vector.ImageVector
import dev.antigravity.shared.model.SemanticIcon

/**
 * Exhaustive mapping from platform-neutral KMP [SemanticIcon] identifiers to
 * Material Symbols Rounded (`Icons.Rounded.*`) vectors — zero SF Symbols on Android.
 */
fun SemanticIcon.toMaterialIcon(): ImageVector = when (this) {
    // Markdown Alert Callouts
    SemanticIcon.ALERT_INFO -> Icons.Rounded.Info
    SemanticIcon.ALERT_TIP -> Icons.Rounded.Lightbulb
    SemanticIcon.ALERT_IMPORTANT -> Icons.Rounded.PriorityHigh
    SemanticIcon.ALERT_WARNING -> Icons.Rounded.Warning
    SemanticIcon.ALERT_CAUTION -> Icons.Rounded.LocalFireDepartment

    // Markdown Embed Kinds
    SemanticIcon.EMBED_HTML_WIDGET -> Icons.Rounded.Widgets
    SemanticIcon.EMBED_IMAGE -> Icons.Rounded.Image
    SemanticIcon.EMBED_SVG -> Icons.Rounded.Brush
    SemanticIcon.EMBED_MARKDOWN -> Icons.Rounded.Description
    SemanticIcon.EMBED_WEB_LINK -> Icons.Rounded.Public
    SemanticIcon.EMBED_SIDECAR -> Icons.Rounded.Extension
    SemanticIcon.EMBED_ARTIFACT -> Icons.AutoMirrored.Rounded.InsertDriveFile

    // Permission Presets
    SemanticIcon.PERMISSION_REVIEW -> Icons.Rounded.Visibility
    SemanticIcon.PERMISSION_SANDBOX -> Icons.Rounded.Lock
    SemanticIcon.PERMISSION_AUTO -> Icons.Rounded.VerifiedUser
    SemanticIcon.PERMISSION_TURBO -> Icons.Rounded.Security
    SemanticIcon.PERMISSION_INHERIT_GLOBAL -> Icons.Rounded.Tune

    // Slash Commands
    SemanticIcon.COMMAND_PLAN -> Icons.Rounded.FindInPage
    SemanticIcon.COMMAND_GRILL_ME -> Icons.Rounded.QuestionAnswer
    SemanticIcon.COMMAND_GOAL -> Icons.Rounded.Flag
    SemanticIcon.COMMAND_BOOST -> Icons.Rounded.Bolt
    SemanticIcon.COMMAND_SWARM -> Icons.Rounded.DeviceHub
    SemanticIcon.COMMAND_TEAMWORK -> Icons.Rounded.Groups
    SemanticIcon.COMMAND_WORKFLOW -> Icons.Rounded.AccountTree
    SemanticIcon.COMMAND_SIDE_QUESTION -> Icons.Rounded.Forum
    SemanticIcon.COMMAND_SCHEDULE -> Icons.Rounded.Schedule
    SemanticIcon.COMMAND_BROWSER -> Icons.Rounded.Explore
    SemanticIcon.COMMAND_LEARN -> Icons.Rounded.AutoAwesome
    SemanticIcon.COMMAND_CUSTOMIZATIONS -> Icons.Rounded.Tune
    SemanticIcon.COMMAND_GUIDE -> Icons.AutoMirrored.Rounded.MenuBook
    SemanticIcon.COMMAND_AUTOMATION -> Icons.Rounded.History
    SemanticIcon.COMMAND_GENERATIVE_UI -> Icons.Rounded.AutoFixHigh
    SemanticIcon.COMMAND_VOICE -> Icons.Rounded.GraphicEq
    SemanticIcon.COMMAND_CUSTOM_SKILL -> Icons.Rounded.Category
}
