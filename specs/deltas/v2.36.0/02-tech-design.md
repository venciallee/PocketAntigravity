# Auto-Generated Technical Design — Antigravity v2.36.0

## Module Mapping
- `shared/`: Kotlin Multiplatform shared core (`core-model`, `core-protocol`, `core-markdown`, `core-domain`, `umbrella`).
- `apps/ios/Packages/AntigravityData/`: Pure Swift 6 domain models (`ResilientStringEnum`), RPC payloads (`HostCapabilityRegistry`), Protobuf decoding (zero UIKit/WebKit/AVFoundation).
- `apps/ios/App/`: SwiftUI views, KMP bridge & sheets bound to `AntigravitySessionStore` (dual-track live vs `--ui-verify`, using `performLiveCapabilityWrite`).
- `verification/`: `mock_language_server.py`, `verify-v233-capabilities.py`, `verify-compat-matrix.py`, and `esdd-verify.py`.

## Bidirectional Compatibility Checklist
- [ ] Register any newly added Connect-RPC methods in `HostCapabilityRegistry.swift`.
- [ ] Conform all newly added `String, Codable` model enums to `ResilientStringEnum`.
- [ ] Mirror any new enum downgrade mappings between `HostCapabilityRegistry.swift` and `scripts/mac-companion-bridge.py`.
- [ ] Use `performLiveCapabilityWrite(...)` for mutating Store RPCs (zero silent `try?`).

## Tier 2 Protocol Probe Checklist
- [ ] Capture live `LanguageServerService` schema for: Kept disabled plugin and Marketplace controls visible in Customizations as grayed-out options with an explanation tooltip when an organization administrator turns them off, while built-in plugins continue to work.
- [ ] Capture live `LanguageServerService` schema for: Enabled authorizing cloud automations for remote agents directly from the desktop app using a Google sign-in prompt that opens in your system browser.
- [ ] Capture live `LanguageServerService` schema for: Updated the Installed tab in Customizations to display up to 16 plugins initially and reveal all remaining installed plugins at once when you select See more.
- [ ] Capture live `LanguageServerService` schema for: Rendered LaTeX mathematical equations in subagent replies inside the main conversation thread instead of displaying raw TeX markup.
- [ ] Capture live `LanguageServerService` schema for: Requested offline access during OAuth sign-in for MCP servers that support it, allowing refresh tokens to be issued automatically and reducing repeated sign-in prompts.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where long-running turns could fail with an authentication error when an OAuth token expired mid-session by preserving early token refresh and retrying once on expired credentials.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where failed plugin or skill actions showed error messages across other Customizations pages without a dismiss button and rendered in plain gray text.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where typing quickly in the Add MCP Server search box could display stale results from an earlier query or clear the loading spinner early.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where interrupted remote agent turns did not display an error card with a retry button.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where the model selector was locked while a turn was running, preventing you from switching models before sending a /btw side question or follow-up message. The selector now stays interactive with a tooltip noting when the change takes effect.
- [ ] Capture live `LanguageServerService` schema for: This release automatically resumes active conversations after an app restart or update, opens plugin panel links directly in the side panel, and compresses background diagnostic uploads to reduce upload bandwidth while capping upload batch sizes. It includes 2
- [ ] Capture live `LanguageServerService` schema for: Updated plugin panel links in live agent replies to open their view automatically in the side panel.
- [ ] Capture live `LanguageServerService` schema for: Agents, scripts, plugins, and automations can now use the built-in Conversation Management API and conversations skill to create, list, inspect, rename, pin, star, archive, tag, group, and delete local Antigravity conversations.
- [ ] Capture live `LanguageServerService` schema for: The message box now places the Environment selector ahead of Project and Branch, putting SSH Host directly in the environment menu and scoping project lists with cloning submenus when remote agents are enabled.
- [ ] Capture live `LanguageServerService` schema for: ClickUp, Midpage Legal Research, and Descrybe Legal Engine partner plugins are now available in the Marketplace.
- [ ] Capture live `LanguageServerService` schema for: Updated the official Gemini API Marketplace plugin to v2.8.0 with Gemini 4 Neon usage and migration guidance.
- [ ] Capture live `LanguageServerService` schema for: The queued messages card now names any active background tasks or subagents holding delivery after a turn ends, so you can see why a message is waiting or choose Send Now.
- [ ] Capture live `LanguageServerService` schema for: Consecutive parallel subagent launches now collapse into a single expandable row, and adjacent Worked for sections with no intervening output merge automatically.
- [ ] Capture live `LanguageServerService` schema for: The Installed tab in Customizations now starts non-plugin sections collapsed until you search, plugin detail pages show an Added badge once installed, and chat plugin cards display install errors inline.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where installed plugins disappeared from Customizations when disabled by an organization policy instead of showing as blocked and removable.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where a Marketplace plugin card could briefly revert from a spinner back to the Add button after installation before showing the installed menu.
- [ ] Capture live `LanguageServerService` schema for: This release brings MCP App support and Gemini 4 Neon to eligible paid consumer plans. It includes 15 improvements and 24 fixes.
- [ ] Capture live `LanguageServerService` schema for: Added Clerk, Docusign, and TestMu AI partner plugins to the Marketplace.
- [ ] Capture live `LanguageServerService` schema for: The Installed tab in Customizations now shows the first two bundles above a See more toggle so your plugins stay near the top.
- [ ] Capture live `LanguageServerService` schema for: Sign out buttons for plugin accounts and plugin MCP servers now show a loading indicator while sign-out finishes.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where a failed step update or subagent wakeup could cause the turn step checklist to flash or disappear.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where plugins whose manifest file started with a UTF-8 byte order mark installed without error but failed to load.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where Trello and Zoho Books plugin icons appeared tiny or low-contrast in dark themes.
- [ ] Capture live `LanguageServerService` schema for: This release adds SSH host connections for running projects and agents on remote Linux machines, along with live GitHub pull request status pills, hover cards, and an Overview Pull Requests section. It also brings in-page Cmd/Ctrl+F search to the built-in brow
- [ ] Capture live `LanguageServerService` schema for: GitHub pull request links in chat and URL artifact cards now render as live status pills with hover cards, alongside a new Pull Requests section in the Overview panel and an optional conversation sidebar indicator.
- [ ] Capture live `LanguageServerService` schema for: Finished /btw side-question answers now include an Insert into main conversation action, and you can start a side question from selected subagent text or promote a subagent tab to Full View when running /btw.
- [ ] Capture live `LanguageServerService` schema for: Business and enterprise accounts can now use /swarm and open UI plugin panels from the side panel, Overview, New Tab, and title bar when allowed by organization admin settings.
- [ ] Capture live `LanguageServerService` schema for: Added Cloudflare, Grafana Cloud, SonarQube, incident.io, Better Stack, Tavily, and Levels.fyi to the partner plugin marketplace, and updated the Gemini API plugin and 15 partner plugins.
- [ ] Capture live `LanguageServerService` schema for: Messages sent immediately while the agent is working now appear as sent without pulsing and keep the turn above them steady on delivery. Agent response actions are now left-aligned below the status line, and a single running subagent opens from the status line
- [ ] Capture live `LanguageServerService` schema for: Device management policies in admin_settings.json can now lock sign-in and project settings, enforce permission ceilings, disable remote control, and restrict plugins or marketplace access.
- [ ] Capture live `LanguageServerService` schema for: If you use remote agents, editing env-setup.sh now shows Saved setup routine with an Open in settings link, project setup scripts are labeled Environment, and multiple open windows share a single cloud polling loop.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where custom file viewers from plugins and MCP apps still showed non-working Preview, Raw, Word Wrap, and Export as PDF controls in the side panel.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where remote MCP servers using OAuth signed you out after an hour when tokens refreshed, where configured MCP headers were sent across cross-origin redirects, and where OAuth sign-in callbacks failed on IPv6-only machines.
- [ ] Capture live `LanguageServerService` schema for: Fixed an issue where empty internal plugin projects appeared in project pickers, where Create with Prompt on the Automations page could target a remote project instead of This Computer, and where /learn appended past rule file size limits.
- [ ] Capture live `LanguageServerService` schema for: This release brings multi-turn /btw side-question tabs with read-only tool access to the Antigravity App and fixes an issue that could truncate diagnostic logs. It includes 1 improvement and 1 fix.
- _...and 1395 additional Tier 2 item(s) recorded in `delta-report.json`._
