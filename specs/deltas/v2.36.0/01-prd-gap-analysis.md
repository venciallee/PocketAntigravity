# Auto-Generated PRD & Gap Analysis — Antigravity v2.36.0

# Antigravity Upstream Documentation Delta (v2.33.0 → v2.36.0)

- **Checked (UTC)**: `2026-11-27T17:44:47.279116+00:00`
- **App Version**: `v2.33.0` → `v2.36.0`
- **CLI Version**: `v1.5.11` → `v1.5.18`
- **Stale CDN Guard Triggered**: `False`
- **Meaningful Delta**: `True` (max tier: `tier3`)
- **Changed Sources**: `changelog`, `cli_changelog`, `cli_releases_atom`, `sdk_releases_atom`, `docs/features`, `docs/models`, `docs/permissions`, `docs/remote-control`, `docs/remote-agents`, `docs/review-changes`, `docs/side-panel`, `docs/voice-mode`, `docs/browser`, `docs/ssh`, `docs/dynamic-workflows`, `docs/swarm`, `docs/teamwork`, `docs/plugins`, `docs/mcp`, `docs/sidecars`

## Classified Requirements Delta

| Tier | Source | Summary | Rationale |
| :--- | :--- | :--- | :--- |
| `TIER1` | `changelog` | Changelog2-0Antigravity AppDocumentationChangelog Antigravity App DocumentationAntigravity App | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Track new features, improvements, and bug fixes across Google Antigravity surfaces, including the Antigravity App, Antigravity CLI, the Antigravity SDK, and Antigravity IDE. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | New versions roll out gradually and may take a few days to reach all users. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | November 27, 2026 | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | This release adds a floating composer with live status inside maximized side panels, expands Auto mode to approve safe file edits outside your current project, and carries spoken context from ended voice calls into local conversations. It includes 13 improveme | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Improvements(13) | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Added a floating composer pill at the bottom of maximized side panels with a live status bar showing agent progress, unread replies, and saved drafts; expand it to send follow-ups or start dictation without leaving the maximized view. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Expanded Auto mode to automatically approve safe file edits in other version-controlled repositories and non-replacing file additions outside your current project without prompting for confirmation. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Carried spoken context from live voice calls that end before handoff into the local conversation so the agent remembers what you discussed. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Added discovery for custom skills stored in ~/.agents/skills, with skills in ~/.gemini taking precedence if two skills share the same name. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | Kept disabled plugin and Marketplace controls visible in Customizations as grayed-out options with an explanation tooltip when an organization administrator turns them off, while built-in plugins continue to work. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | Enabled authorizing cloud automations for remote agents directly from the desktop app using a Google sign-in prompt that opens in your system browser. | Matched protocol/RPC/orchestration keyword `remote agent` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | Updated the Installed tab in Customizations to display up to 16 plugins initially and reveal all remaining installed plugins at once when you select See more. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | Rendered LaTeX mathematical equations in subagent replies inside the main conversation thread instead of displaying raw TeX markup. | Matched protocol/RPC/orchestration keyword `subagent` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | Requested offline access during OAuth sign-in for MCP servers that support it, allowing refresh tokens to be issued automatically and reducing repeated sign-in prompts. | Matched protocol/RPC/orchestration keyword `mcp` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Added a dashed circle icon alongside strikethrough text for skipped steps in task checklists so they stand out clearly from pending steps. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Displayed a standalone info icon with a hover tooltip for models with descriptions in the model selector even when they do not have a status badge. | Matched client/catalog/UI keyword `model` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Reduced disk reads and memory usage when updating conversation summaries during active turns. | Matched client/catalog/UI keyword `usage` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Fixed an issue where typing localhost or a local port into the built-in browser address bar defaulted to HTTPS and failed to load local HTTP development servers. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where the default Open Keyboard Shortcuts binding did not work on macOS by changing it to Option+Cmd+/ and removing the unreachable ? shortcut. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where selecting the same model for both Orchestrator planner and executor fell back to a different default model instead of running as a single agent on the chosen model. | Matched client/catalog/UI keyword `model` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Fixed an issue where selecting System default as your microphone could open a previously used physical microphone instead of following your operating system's default input device. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where LaTeX equations containing \label commands failed to render and displayed an error banner. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where unformatted shell variables in chat messages were mistakenly rendered as LaTeX math. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where copying text from raw markdown and code viewers collapsed blank lines. | Matched client/catalog/UI keyword `markdown` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Fixed an issue where an empty organization prepaid wallet was misreported as a temporary model quota limit with retry prompts instead of showing a clear notice. | Matched client/catalog/UI keyword `model` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Fixed an issue where attaching a truncated or corrupt image could cause subsequent turns in the conversation to fail repeatedly. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | Fixed an issue where long-running turns could fail with an authentication error when an OAuth token expired mid-session by preserving early token refresh and retrying once on expired credentials. | Matched protocol/RPC/orchestration keyword `oauth` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | Fixed an issue where failed plugin or skill actions showed error messages across other Customizations pages without a dismiss button and rendered in plain gray text. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Fixed an issue where hovering over a running conversation in the sidebar showed a Stop button instead of the Archive action, and restored hover Archive on sidebar conversations outside Inbox Mode. | Matched client/catalog/UI keyword `sidebar` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Fixed an issue where an unsent message draft deleted in one tab or window could reappear when switching or closing another open tab. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where sending an immediate follow-up or using Send Now behind an in-flight message could fail to cancel the active generation. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where closing a maximized side panel or resizing the window could leave the conversation area blank. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where Enterprise accounts saw an empty agent selector and could not open the in-app Give Feedback screen from the command palette. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where allowing non-project file access under legacy permissions could bypass protections on sensitive configuration files. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | Fixed an issue where typing quickly in the Add MCP Server search box could display stale results from an earlier query or clear the loading spinner early. | Matched protocol/RPC/orchestration keyword `mcp` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | Fixed an issue where interrupted remote agent turns did not display an error card with a retry button. | Matched protocol/RPC/orchestration keyword `remote agent` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Fixed an issue where Markdown tables repeatedly re-measured their columns during sidebar resize animations. | Matched client/catalog/UI keyword `markdown` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Fixed an issue where the collapsed Update Available icon in narrow windows had no tooltip on hover or keyboard focus. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where the empty middle area of the New Conversation title bar could not be dragged to move the window. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where opening a deep link to a specific setting failed to scroll to and highlight that row. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where switching between conversations caused the conversation navigator rail to briefly flash. | Matched client/catalog/UI keyword `navigator` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Fixed an issue where dismissed onboarding suggestions containing commas could reappear after reloading the app. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | November 25, 2026 | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | This release lets you change the selected model while a conversation turn is running, with a tooltip clarifying when the change takes effect. It includes 1 fix. | Matched client/catalog/UI keyword `model` (Auto-implementable Ready PR) |
| `TIER2` | `changelog` | Fixed an issue where the model selector was locked while a turn was running, preventing you from switching models before sending a /btw side question or follow-up message. The selector now stays interactive with a tooltip noting when the change takes effect. | Matched protocol/RPC/orchestration keyword `/btw` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | November 24, 2026 | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | This release automatically resumes active conversations after an app restart or update, opens plugin panel links directly in the side panel, and compresses background diagnostic uploads to reduce upload bandwidth while capping upload batch sizes. It includes 2 | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Added automatic resumption on startup for active conversations interrupted by an app restart or update. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | Updated plugin panel links in live agent replies to open their view automatically in the side panel. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Fixed an issue where background diagnostic uploads were sent uncompressed and without a batch size limit, using more upload bandwidth than necessary and causing oversized batches to fail. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | November 23, 2026 | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | This release keeps your local conversation history unlimited by default, offers a conversation management API for agents to create and manage Antigravity conversations, and adds Cmd+F search inside full-page HTML artifacts. It includes 20 improvements and 19 f | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Improvements(20) | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Antigravity now keeps your local conversation history unlimited by default instead of pruning older conversations after 500. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | Agents, scripts, plugins, and automations can now use the built-in Conversation Management API and conversations skill to create, list, inspect, rename, pin, star, archive, tag, group, and delete local Antigravity conversations. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | The message box now places the Environment selector ahead of Project and Branch, putting SSH Host directly in the environment menu and scoping project lists with cloning submenus when remote agents are enabled. | Matched protocol/RPC/orchestration keyword `remote agent` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Auto permission mode now approves file reads outside your current project automatically while keeping sensitive configuration directories protected. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Permission prompts for writing files outside your project now suggest directory scopes instead of single files, and bold target paths and patterns for faster scanning. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Markdown and plain-text file tabs now include a per-tab RTL text direction toggle in the header for reading RTL prose without flipping code blocks or other open tabs. | Matched client/catalog/UI keyword `markdown` (Auto-implementable Ready PR) |

## Delivery Triage Summary
- **Tier 1 (Auto Ready PR)**: 4053 item(s)
- **Tier 2 (Draft PR + Protocol Probe)**: 1435 item(s)
- **Tier 3 (RFC Issue Only)**: 96 item(s)
