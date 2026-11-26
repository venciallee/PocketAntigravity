import Foundation

// MARK: - Bilingual Model Localization Helpers (English / Simplified Chinese)

public extension PrimaryTab {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .agents: return language.t("Agents", "代理")
        case .automations: return language.t("Automations", "自动化")
        case .settings: return language.t("Settings", "设置")
        }
    }
}

public extension AgentsQuickFilter {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .all: return language.t("All", "全部")
        case .running: return language.t("Running", "运行中")
        case .needsYou: return language.t("Needs you", "待处理")
        case .unread: return language.t("Unread", "未读")
        }
    }
}

public extension DisplayGroupBy {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .project: return language.t("Project", "项目")
        case .host: return language.t("Host", "主机")
        case .none: return language.t("None", "不分组")
        }
    }
}

public extension ConversationSortField {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .lastUpdated: return language.t("Last Updated", "最近更新")
        case .dateCreated: return language.t("Date Created", "创建时间")
        case .title: return language.t("Title", "标题")
        }
    }
}

public extension ProjectRuntimeTarget {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .macBookPro: return rawValue
        case .cloud: return language.t("Cloud", "云端")
        }
    }

    func localizedDescription(for language: AppLanguage) -> String {
        switch self {
        case .macBookPro:
            return language.t(
                "Runs locally on your paired MacBook Pro with direct filesystem access.",
                "在已配对的本地 MacBook Pro 上运行，可直接访问本地文件系统。"
            )
        case .cloud:
            return language.t(
                "Runs in its own cloud VM and keeps working while your computer sleeps.",
                "在独立云端虚拟机中运行，电脑休眠时也可继续执行。"
            )
        }
    }
}

public extension ProjectSourceKind {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .githubRepo: return language.t("GitHub repository", "GitHub 仓库")
        case .driveFolder: return language.t("Drive folder", "云端硬盘文件夹")
        }
    }
}

public extension ProjectDetailTab {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .active: return language.t("Active", "进行中")
        case .archived: return language.t("Archived", "已归档")
        case .automations: return language.t("Automations", "自动化")
        }
    }
}

public extension ThinkingEffortLevel {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .low: return language.t("Low", "低")
        case .medium: return language.t("Medium", "中")
        case .high: return language.t("High", "高")
        case .extra: return language.t("Extra", "极高")
        }
    }
}

public extension CascadeExecutionMode {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .planning: return language.t("Planning", "规划")
        case .fast: return language.t("Fast", "快速")
        }
    }

    func localizedSummaryDescription(for language: AppLanguage) -> String {
        switch self {
        case .planning:
            return language.t(
                "Plans first and writes artifacts for you to review",
                "先制定计划并生成产物供你审核"
            )
        case .fast:
            return language.t(
                "Acts directly — best for small, local edits",
                "直接执行操作，适合轻量、局部的修改"
            )
        }
    }
}

public extension AgentPermissionPreset {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .requestReview: return language.t("Request Review", "请求审核")
        case .defaultPolicy: return language.t("Default", "默认")
        case .auto: return language.t("Auto", "自动")
        case .turbo: return language.t("Turbo", "极速")
        case .inheritGlobal: return language.t("Use Global Settings", "跟随全局设置")
        }
    }

    func localizedSummaryDescription(for language: AppLanguage) -> String {
        switch self {
        case .requestReview:
            return language.t("Every command requires approval.", "每条命令都需要审批。")
        case .defaultPolicy:
            return language.t("Ask before sensitive operations.", "敏感操作前征求确认。")
        case .auto:
            return language.t("Automatically decide if commands run.", "自动判断是否直接执行命令。")
        case .turbo:
            return language.t("Run all commands without restrictions.", "无限制自动执行所有命令。")
        case .inheritGlobal:
            return language.t(
                "Follow your global workstation or remote agent preset.",
                "沿用全局工作站或云端代理权限策略。"
            )
        }
    }

    func localizedShortDescription(for language: AppLanguage) -> String {
        switch self {
        case .requestReview:
            return language.t(
                "Always ask before terminal commands; workspace file access only.",
                "执行终端命令前始终询问；仅限访问工作区文件。"
            )
        case .defaultPolicy:
            return language.t(
                "Commands run in isolated Terminal sandbox; ask before leaving sandbox.",
                "命令在隔离终端沙盒中运行；离开沙盒前先询问。"
            )
        case .auto:
            return language.t(
                "Sandboxed by default; safe outside-sandbox commands auto-evaluated.",
                "默认沙盒运行；沙盒外安全命令自动评估放行。"
            )
        case .turbo:
            return language.t(
                "Unrestricted local commands and file access (sensitive browser gates remain).",
                "无限制本地命令与文件访问（仍保留敏感浏览器确认门控）。"
            )
        case .inheritGlobal:
            return language.t(
                "Follow your global workstation or remote agent preset.",
                "沿用全局工作站或云端代理权限策略。"
            )
        }
    }
}

public extension AppAppearanceMode {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .system: return language.t("System", "跟随系统")
        case .dark: return language.t("Dark", "深色")
        case .light: return language.t("Light", "浅色")
        }
    }
}

public extension AppThemePreset {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .obsidian: return language.t("Obsidian", "曜石")
        case .nord: return language.t("Nord", "北欧")
        case .everforestDark: return language.t("Everforest", "森雾")
        case .everforestLight: return language.t("Everforest Light", "森雾浅")
        }
    }
}

public extension InterfaceLayoutMode {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .softwareEngineering: return language.t("Software Engineering", "软件工程")
        case .knowledgeWork: return language.t("Knowledge Work", "知识工作")
        }
    }
}

public extension AutomationSectionKind {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .scheduled: return language.t("SCHEDULED", "定时任务")
        case .alwaysOn: return language.t("ALWAYS ON", "常驻运行")
        case .paused: return language.t("PAUSED", "已暂停")
        }
    }
}

public extension AutomationRunStatus {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .succeeded: return language.t("Succeeded", "成功")
        case .needsReview: return language.t("Needs review", "待审核")
        case .failed: return language.t("Failed", "失败")
        case .running: return language.t("Running", "运行中")
        }
    }
}

public extension ContextCategory {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .files: return language.t("Files", "文件")
        case .folder: return language.t("Folder", "文件夹")
        case .mentions: return language.t("Mentions", "引用")
        case .actions: return language.t("Actions", "操作")
        case .skills: return language.t("Skills", "技能")
        case .drive: return language.t("Drive", "云端硬盘")
        }
    }
}

public extension DiffCompareMode {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .turn: return language.t("Per Turn", "按轮次")
        case .uncommitted: return language.t("Uncommitted", "未提交")
        case .branch: return language.t("Branch", "分支对比")
        case .agentEdits: return language.t("Agent Edits", "代理修改")
        }
    }
}

public extension CortexStepStatus {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .unspecified: return language.t("IDLE", "空闲")
        case .pending: return language.t("QUEUED", "排队中")
        case .inProgress: return language.t("RUNNING", "运行中")
        case .done: return language.t("DONE", "已完成")
        case .error: return language.t("ERROR", "错误")
        case .cancelled: return language.t("STOPPED", "已停止")
        case .blocked: return language.t("BLOCKED", "已阻塞")
        case .waiting: return language.t("WAITING", "等待中")
        }
    }
}

public enum AppLocalizationFormatter: Sendable {
    public static func localizeConnectionStatus(_ raw: String, language: AppLanguage) -> String {
        guard language.isChinese else { return raw }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "not connected":
            return "未连接"
        case "connected":
            return "已连接"
        case "connecting...", "connecting…":
            return "连接中…"
        case "reconnecting...", "reconnecting…":
            return "重连中…"
        case "offline":
            return "离线"
        default:
            if trimmed.hasPrefix("Offline · ") {
                return "离线 · " + trimmed.dropFirst("Offline · ".count)
            }
            if trimmed.hasPrefix("Connected · ") {
                return "已连接 · " + trimmed.dropFirst("Connected · ".count)
            }
            if trimmed.hasPrefix("Connecting · ") {
                return "连接中 · " + trimmed.dropFirst("Connecting · ".count)
            }
            if trimmed.hasSuffix(" · Offline") {
                return trimmed.dropLast(" · Offline".count) + " · 离线"
            }
            return raw
        }
    }

    public static func localizeRelativeTime(_ raw: String, language: AppLanguage) -> String {
        guard language.isChinese else { return raw }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "just now" || lower == "now" {
            return "刚刚"
        }
        let cleaned = lower.hasSuffix(" ago") ? String(lower.dropLast(4)) : lower
        guard cleaned.count >= 2, let unit = cleaned.last else { return raw }
        let numPart = String(cleaned.dropLast())
        guard Int(numPart) != nil else { return raw }
        switch unit {
        case "s": return "\(numPart)秒前"
        case "m": return "\(numPart)分钟前"
        case "h": return "\(numPart)小时前"
        case "d": return "\(numPart)天前"
        case "w": return "\(numPart)周前"
        default: return raw
        }
    }

    public static func localizeAgentPersona(_ raw: String, language: AppLanguage) -> String {
        guard language.isChinese else { return raw }
        return raw.caseInsensitiveCompare("Default") == .orderedSame ? "默认" : raw
    }
}
