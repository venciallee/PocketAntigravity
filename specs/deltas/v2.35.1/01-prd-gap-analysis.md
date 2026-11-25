# Auto-Generated PRD & Gap Analysis — Antigravity v2.35.1

# Antigravity Upstream Documentation Delta (v2.33.0 → v2.35.1)

- **Checked (UTC)**: `2026-11-25T18:18:52.060824+00:00`
- **App Version**: `v2.33.0` → `v2.35.1`
- **CLI Version**: `v1.5.11` → `v1.5.17`
- **Stale CDN Guard Triggered**: `False`
- **Meaningful Delta**: `True` (max tier: `tier3`)
- **Changed Sources**: `changelog`, `cli_changelog`, `cli_releases_atom`, `sdk_releases_atom`, `docs/features`, `docs/models`, `docs/permissions`, `docs/remote-control`, `docs/remote-agents`, `docs/review-changes`, `docs/side-panel`, `docs/voice-mode`, `docs/browser`, `docs/ssh`, `docs/dynamic-workflows`, `docs/swarm`, `docs/teamwork`, `docs/plugins`, `docs/mcp`, `docs/sidecars`

## Classified Requirements Delta

| Tier | Source | Summary | Rationale |
| :--- | :--- | :--- | :--- |
| `TIER1` | `changelog` | Changelog2-0Antigravity AppDocumentationChangelog Antigravity App DocumentationAntigravity App | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Track new features, improvements, and bug fixes across Google Antigravity surfaces, including the Antigravity App, Antigravity CLI, the Antigravity SDK, and Antigravity IDE. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | New versions roll out gradually and may take a few days to reach all users. | General Antigravity 2.0 capability or UX update |
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
| `TIER1` | `changelog` | Opening large swarms in the Swarm board is now much faster with on-demand message paging, incremental board updates, and reduced background polling while hidden. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | ClickUp, Midpage Legal Research, and Descrybe Legal Engine partner plugins are now available in the Marketplace. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | Updated the official Gemini API Marketplace plugin to v2.8.0 with Gemini 4 Neon usage and migration guidance. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | The queued messages card now names any active background tasks or subagents holding delivery after a turn ends, so you can see why a message is waiting or choose Send Now. | Matched protocol/RPC/orchestration keyword `subagent` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | Consecutive parallel subagent launches now collapse into a single expandable row, and adjacent Worked for sections with no intervening output merge automatically. | Matched protocol/RPC/orchestration keyword `subagent` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | The model and permissions selectors in the message box now lock with explanatory tooltips while a turn is running so changes are not mistaken as taking effect mid-turn. | Matched client/catalog/UI keyword `model` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Default Orchestrator and Executor models in Settings > Models now start at High thinking effort when available instead of the highest available effort level. | Matched client/catalog/UI keyword `model` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Selecting a side-question match in conversation search now opens both the parent conversation and its side-question tab directly. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | The Installed tab in Customizations now starts non-plugin sections collapsed until you search, plugin detail pages show an Added badge once installed, and chat plugin cards display install errors inline. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Running conversations now include Archive right below Stop in sidebar and history menus. | Matched client/catalog/UI keyword `sidebar` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | The Other License auto-assign screen now suggests your discoverable Google Cloud projects in a searchable dropdown during onboarding and in Settings. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where comments added on code artifacts did not appear in the Review button counter, sidebar badges, or combined review submissions. | Matched client/catalog/UI keyword `sidebar` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Fixed an issue where pressing Stop right after sending a follow-up could drop the message instead of returning it to the message box. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where using Send Now on a queued message could overwrite draft text in the message box or lose keyboard focus, and kept queue collapse state scoped per conversation. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where sending a follow-up to an idle conversation could briefly flash a pending send card, and where a message waiting to send during a running turn could appear below the working indicator. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where splitting a terminal in the side panel reloaded the pane and lost its scroll position and keyboard focus. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where selecting a quote pill inside a side-question tab did not scroll the parent conversation to the quoted passage, and where closed side-question tabs were not restored when navigating back to them. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where reconnecting to a conversation wiped edits made inside an open permission prompt. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where approving a permission or question prompt could cause the conversation to jump. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where shell commands containing dollar signs inside agent question cards rendered as math formulas. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where single-line command and file pills could misalign their first letter by one pixel at fractional display zoom levels. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where Fill conversation width left extra left padding in single-turn conversations and narrow views where the navigator rail is hidden. | Matched client/catalog/UI keyword `navigator` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | Fixed an issue where focus rings around the Google Cloud project field and license cards were cut off during license selection. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where closing media previews or the voice picker could move keyboard focus to the wrong control instead of returning to the button that opened it. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | Fixed an issue where installed plugins disappeared from Customizations when disabled by an organization policy instead of showing as blocked and removable. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Fixed an issue where failed skill, rule, or agent loads in Project Customizations appeared as an empty list instead of displaying an error. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | Fixed an issue where a Marketplace plugin card could briefly revert from a spinner back to the Add button after installation before showing the installed menu. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Fixed an issue where file tools or sandboxed commands could access internal session connection files, and where Auto mode safety checks inspected commands from the wrong working directory. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where enterprise sign-in could save a token with stale project or license metadata, and where cached account status did not refresh right away after access was revoked. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Fixed an issue where the desktop app repeatedly polled unavailable remote Git status and retried permanent permission or request errors instead of stopping or backing off. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | November 20, 2026 | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | This release brings MCP App support and Gemini 4 Neon to eligible paid consumer plans. It includes 15 improvements and 24 fixes. | Matched protocol/RPC/orchestration keyword `mcp` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | Improvements(15) | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Gemini 4 Neon and Orchestrator (Neon) are now available for eligible paid consumer plans, and Gemini 4 Neon is available with Gemini API keys and Application Default Credentials. Enterprise and Application Default Credentials accounts also now support the Orch | Matched client/catalog/UI keyword `gemini 4` (Auto-implementable Ready PR) |
| `TIER1` | `changelog` | You can now choose whether Enter or Ctrl+Enter (Cmd+Enter on macOS) sends messages under Settings > General > Input Box. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Diff views now use a single-column line-number gutter with color-coded change strips, giving code more horizontal room before wrapping. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | You can now drag conversation tabs from the side panel directly into the message box to reference them in a prompt. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | URLs typed or pasted into the message box are now automatically formatted as interactive links. | General Antigravity 2.0 capability or UX update |
| `TIER1` | `changelog` | Selecting a skill pill in a conversation now opens its skill definition file in the side panel. | General Antigravity 2.0 capability or UX update |
| `TIER2` | `changelog` | Added Clerk, Docusign, and TestMu AI partner plugins to the Marketplace. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | The Installed tab in Customizations now shows the first two bundles above a See more toggle so your plugins stay near the top. | Matched protocol/RPC/orchestration keyword `plugin` (Draft PR + Protocol Probe) |
| `TIER2` | `changelog` | Sign out buttons for plugin accounts and plugin MCP servers now show a loading indicator while sign-out finishes. | Matched protocol/RPC/orchestration keyword `mcp` (Draft PR + Protocol Probe) |
| `TIER1` | `changelog` | The model selector effort submenu now includes a Thinking effort header with a tooltip explaining latency and quota tradeoffs. | Matched client/catalog/UI keyword `model` (Auto-implementable Ready PR) |

## Delivery Triage Summary
- **Tier 1 (Auto Ready PR)**: 4019 item(s)
- **Tier 2 (Draft PR + Protocol Probe)**: 1421 item(s)
- **Tier 3 (RFC Issue Only)**: 96 item(s)
