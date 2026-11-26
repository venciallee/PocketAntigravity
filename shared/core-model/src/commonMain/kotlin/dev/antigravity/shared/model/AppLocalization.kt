package dev.antigravity.shared.model

/**
 * Shared bilingual (English / Simplified Chinese) localization helpers for KMP domain models
 * and dynamic status strings, enabling real-time in-app language switching across Android and iOS.
 */
public fun PrimaryTab.localizedTitle(language: AppLanguage): String = when (this) {
    PrimaryTab.AGENTS -> language.t("Agents", "代理")
    PrimaryTab.AUTOMATIONS -> language.t("Automations", "自动化")
    PrimaryTab.SETTINGS -> language.t("Settings", "设置")
}

public fun AgentsQuickFilter.localizedTitle(language: AppLanguage): String = when (this) {
    AgentsQuickFilter.ALL -> language.t("All", "全部")
    AgentsQuickFilter.RUNNING -> language.t("Running", "运行中")
    AgentsQuickFilter.NEEDS_YOU -> language.t("Needs you", "待处理")
    AgentsQuickFilter.UNREAD -> language.t("Unread", "未读")
}

public fun DisplayGroupBy.localizedTitle(language: AppLanguage): String = when (this) {
    DisplayGroupBy.PROJECT -> language.t("Project", "项目")
    DisplayGroupBy.HOST -> language.t("Host", "主机")
    DisplayGroupBy.NONE -> language.t("None", "不分组")
}

public fun ConversationSortField.localizedTitle(language: AppLanguage): String = when (this) {
    ConversationSortField.LAST_UPDATED -> language.t("Last Updated", "最近更新")
    ConversationSortField.DATE_CREATED -> language.t("Date Created", "创建时间")
    ConversationSortField.TITLE -> language.t("Title", "标题")
}

public fun ProjectRuntimeTarget.localizedTitle(language: AppLanguage): String = when (this) {
    ProjectRuntimeTarget.MAC_BOOK_PRO -> displayTitle
    ProjectRuntimeTarget.CLOUD -> language.t("Cloud", "云端")
}

public fun ProjectRuntimeTarget.localizedDescription(language: AppLanguage): String = when (this) {
    ProjectRuntimeTarget.MAC_BOOK_PRO -> language.t(
        "Runs locally on your paired workstation with direct filesystem access.",
        "在已配对的本地工作站运行，可直接访问本地文件系统。",
    )
    ProjectRuntimeTarget.CLOUD -> language.t(
        "Runs in its own cloud VM and keeps working while your computer sleeps.",
        "在独立云端虚拟机中运行，电脑休眠时也可继续执行。",
    )
}

public fun ProjectSourceKind.localizedTitle(language: AppLanguage): String = when (this) {
    ProjectSourceKind.GITHUB_REPO -> language.t("GitHub repository", "GitHub 仓库")
    ProjectSourceKind.DRIVE_FOLDER -> language.t("Drive folder", "云端硬盘文件夹")
}

public fun ProjectDetailTab.localizedTitle(language: AppLanguage): String = when (this) {
    ProjectDetailTab.ACTIVE -> language.t("Active", "进行中")
    ProjectDetailTab.ARCHIVED -> language.t("Archived", "已归档")
    ProjectDetailTab.AUTOMATIONS -> language.t("Automations", "自动化")
}

public fun ThinkingEffortLevel.localizedTitle(language: AppLanguage): String = when (this) {
    ThinkingEffortLevel.LOW -> language.t("Low", "低")
    ThinkingEffortLevel.MEDIUM -> language.t("Medium", "中")
    ThinkingEffortLevel.HIGH -> language.t("High", "高")
    ThinkingEffortLevel.EXTRA -> language.t("Extra", "极高")
}

public fun CascadeExecutionMode.localizedTitle(language: AppLanguage): String = when (this) {
    CascadeExecutionMode.PLANNING -> language.t("Planning", "规划")
    CascadeExecutionMode.FAST -> language.t("Fast", "快速")
}

public fun CascadeExecutionMode.localizedDescription(language: AppLanguage): String = when (this) {
    CascadeExecutionMode.PLANNING -> language.t(
        "Plans first and writes artifacts for you to review",
        "先制定计划并生成产物供你审核",
    )
    CascadeExecutionMode.FAST -> language.t(
        "Acts directly — best for small, local edits",
        "直接执行操作，适合轻量、局部的修改",
    )
}

public fun AgentPermissionPreset.localizedTitle(language: AppLanguage): String = when (this) {
    AgentPermissionPreset.REQUEST_REVIEW -> language.t("Request Review", "请求审核")
    AgentPermissionPreset.DEFAULT_POLICY -> language.t("Default", "默认")
    AgentPermissionPreset.AUTO -> language.t("Auto", "自动")
    AgentPermissionPreset.TURBO -> language.t("Turbo", "极速")
    AgentPermissionPreset.INHERIT_GLOBAL -> language.t("Inherit Global", "跟随全局")
}

public fun AgentPermissionPreset.localizedDescription(language: AppLanguage): String = when (this) {
    AgentPermissionPreset.REQUEST_REVIEW -> language.t(
        "Ask before running commands, editing outside workspace, or opening browser",
        "执行命令、修改工作区外文件或打开浏览器前先征求确认",
    )
    AgentPermissionPreset.DEFAULT_POLICY -> language.t(
        "Sandboxed terminal commands run safely; sensitive actions ask first",
        "沙盒内终端命令自动安全执行，敏感操作需先确认",
    )
    AgentPermissionPreset.AUTO -> language.t(
        "Automatically approve routine edits & sandboxed commands",
        "自动批准常规代码编辑与沙盒内命令",
    )
    AgentPermissionPreset.TURBO -> language.t(
        "Maximum autonomy — execute commands and edits without stopping",
        "最高自主权限，无需停顿直接执行命令与编辑",
    )
    AgentPermissionPreset.INHERIT_GLOBAL -> language.t(
        "Use the global permission policy configured in Settings",
        "沿用设置中配置的全局权限策略",
    )
}

public fun AppAppearanceMode.localizedTitle(language: AppLanguage): String = when (this) {
    AppAppearanceMode.SYSTEM -> language.t("System", "跟随系统")
    AppAppearanceMode.DARK -> language.t("Dark", "深色")
    AppAppearanceMode.LIGHT -> language.t("Light", "浅色")
}

public fun AppThemePreset.localizedTitle(language: AppLanguage): String = when (this) {
    AppThemePreset.OBSIDIAN -> language.t("Obsidian", "曜石")
    AppThemePreset.NORD -> language.t("Nord", "北欧")
    AppThemePreset.EVERFOREST_DARK -> language.t("Everforest", "森雾")
    AppThemePreset.EVERFOREST_LIGHT -> language.t("Everforest Light", "森雾浅")
}

public fun InterfaceLayoutMode.localizedTitle(language: AppLanguage): String = when (this) {
    InterfaceLayoutMode.COMPACT -> language.t("Compact", "紧凑")
    InterfaceLayoutMode.COMFORTABLE -> language.t("Comfortable", "舒适")
}

public fun AutomationSectionKind.localizedTitle(language: AppLanguage): String = when (this) {
    AutomationSectionKind.SCHEDULED -> language.t("SCHEDULED", "定时任务")
    AutomationSectionKind.ALWAYS_ON -> language.t("ALWAYS ON", "常驻运行")
    AutomationSectionKind.PAUSED -> language.t("PAUSED", "已暂停")
}

public fun AutomationRunStatus.localizedTitle(language: AppLanguage): String = when (this) {
    AutomationRunStatus.SUCCEEDED -> language.t("Succeeded", "成功")
    AutomationRunStatus.NEEDS_REVIEW -> language.t("Needs review", "待审核")
    AutomationRunStatus.FAILED -> language.t("Failed", "失败")
    AutomationRunStatus.RUNNING -> language.t("Running", "运行中")
}

public fun ContextCandidateCategory.localizedTitle(language: AppLanguage): String = when (this) {
    ContextCandidateCategory.FILES -> language.t("Files", "文件")
    ContextCandidateCategory.FOLDER -> language.t("Folder", "文件夹")
    ContextCandidateCategory.MENTIONS -> language.t("Mentions", "引用")
    ContextCandidateCategory.ACTIONS -> language.t("Actions", "操作")
    ContextCandidateCategory.DRIVE -> language.t("Drive", "云端硬盘")
    ContextCandidateCategory.SKILLS -> language.t("Skills", "技能")
}

public fun DiffCompareMode.localizedTitle(language: AppLanguage): String = when (this) {
    DiffCompareMode.TURN -> language.t("This Turn", "本轮变更")
    DiffCompareMode.WORKING_TREE -> language.t("Working Tree", "工作区")
    DiffCompareMode.STAGED -> language.t("Staged", "已暂存")
    DiffCompareMode.BRANCH_BASE -> language.t("vs Base Branch", "对比基准分支")
}

public fun RemoteConnectionChannel.localizedTitle(language: AppLanguage): String = when (this) {
    RemoteConnectionChannel.CLOUD_RELAY -> language.t("Google Cloud Relay", "Google 云中继")
    RemoteConnectionChannel.DIRECT_HOST -> language.t("Direct LAN / Tailscale", "局域网 / Tailscale 直连")
}

public fun CortexStepStatus.localizedTitle(language: AppLanguage): String = when (this) {
    CortexStepStatus.UNSPECIFIED -> language.t("IDLE", "空闲")
    CortexStepStatus.PENDING -> language.t("QUEUED", "排队中")
    CortexStepStatus.IN_PROGRESS -> language.t("RUNNING", "运行中")
    CortexStepStatus.DONE -> language.t("DONE", "已完成")
    CortexStepStatus.ERROR -> language.t("ERROR", "错误")
    CortexStepStatus.CANCELLED -> language.t("STOPPED", "已停止")
    CortexStepStatus.BLOCKED -> language.t("BLOCKED", "已阻塞")
    CortexStepStatus.WAITING -> language.t("WAITING", "等待中")
}

public object AppLocalizationFormatter {
    public fun localizeConnectionStatus(raw: String, language: AppLanguage): String {
        if (!language.isChinese) return raw
        val trimmed = raw.trim()
        return when {
            trimmed.equals("Not Connected", ignoreCase = true) -> "未连接"
            trimmed.equals("Connected", ignoreCase = true) -> "已连接"
            trimmed.equals("Connecting...", ignoreCase = true) || trimmed.equals("Connecting…", ignoreCase = true) -> "连接中…"
            trimmed.equals("Reconnecting...", ignoreCase = true) || trimmed.equals("Reconnecting…", ignoreCase = true) -> "重连中…"
            trimmed.equals("Offline", ignoreCase = true) -> "离线"
            trimmed.startsWith("Offline · ") -> "离线 · ${trimmed.removePrefix("Offline · ")}"
            trimmed.startsWith("Connected · ") -> "已连接 · ${trimmed.removePrefix("Connected · ")}"
            trimmed.startsWith("Connecting · ") -> "连接中 · ${trimmed.removePrefix("Connecting · ")}"
            trimmed.endsWith(" · Offline") -> "${trimmed.removeSuffix(" · Offline")} · 离线"
            else -> raw
        }
    }

    public fun localizeRelativeTime(raw: String, language: AppLanguage): String {
        if (!language.isChinese) return raw
        val trimmed = raw.trim()
        if (trimmed.equals("just now", ignoreCase = true) || trimmed.equals("now", ignoreCase = true)) {
            return "刚刚"
        }
        val compact = Regex("^(\\d+)([smhdw])(\\s+ago)?$", RegexOption.IGNORE_CASE).matchEntire(trimmed)
        if (compact != null) {
            val n = compact.groupValues[1]
            return when (compact.groupValues[2].lowercase()) {
                "s" -> "${n}秒前"
                "m" -> "${n}分钟前"
                "h" -> "${n}小时前"
                "d" -> "${n}天前"
                "w" -> "${n}周前"
                else -> raw
            }
        }
        return raw
    }

    public fun localizeAgentPersona(raw: String, language: AppLanguage): String {
        if (!language.isChinese) return raw
        return if (raw.equals("Default", ignoreCase = true)) "默认" else raw
    }
}
