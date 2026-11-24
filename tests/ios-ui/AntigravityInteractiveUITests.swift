import Darwin
import Foundation
import XCTest

/// Embedded Connect-RPC HTTP server simulating a live Antigravity Desktop `language_server`
/// inside the `XCUITest` runner process so `AGPocket.app` exercises real network + real UI touch events.
private final class EmbeddedDesktopMockServer: @unchecked Sendable {
    let port: UInt16
    private let listenFD: Int32
    private let lock = NSLock()
    private let handshakeCondition = NSCondition()
    private var handshakePaused = false
    private var isStopped = false
    private var simulatedOffline = false
    private var trajectoriesByCascadeId: [String: [[String: Any]]] = [:]
    private var summariesMap: [String: [String: Any]] = [:]
    private var createdCounter = 0

    func setSimulatedOffline(_ offline: Bool) {
        lock.lock()
        simulatedOffline = offline
        lock.unlock()
    }

    func setHandshakePaused(_ paused: Bool) {
        handshakeCondition.lock()
        handshakePaused = paused
        if !paused {
            handshakeCondition.broadcast()
        }
        handshakeCondition.unlock()
    }

    private func waitWhileHandshakePaused() {
        let deadline = Date().addingTimeInterval(18.0)
        handshakeCondition.lock()
        while handshakePaused && Date() < deadline {
            handshakeCondition.wait(until: deadline)
        }
        handshakeCondition.unlock()
    }

    init() throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "EmbeddedDesktopMockServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "socket() failed"])
        }

        var yes: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 32) == 0 else {
            Darwin.close(fd)
            throw NSError(domain: "EmbeddedDesktopMockServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "bind/listen failed"])
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.getsockname(fd, sockPtr, &boundLen)
            }
        }

        self.listenFD = fd
        self.port = UInt16(bigEndian: boundAddr.sin_port)
        seedRealisticDesktopFixtures()

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        setHandshakePaused(false)
        lock.lock()
        let alreadyStopped = isStopped
        isStopped = true
        lock.unlock()
        if !alreadyStopped {
            Darwin.shutdown(listenFD, SHUT_RDWR)
            Darwin.close(listenFD)
        }
    }

    private func seedRealisticDesktopFixtures() {
        summariesMap = [
            // Blank 0-step Desktop tab placeholder that MUST be filtered out on iOS
            "cid-blank-placeholder": [
                "stepCount": 0,
                "status": "CASCADE_RUN_STATUS_IDLE",
                "workspaces": [
                    ["workspaceFolderAbsoluteUri": "file:///Users/dev/slardar_app_ai"]
                ]
            ],
            // Synthetic probe session that MUST be filtered out on iOS
            "cid-synthetic-probe": [
                "summary": "iOS Connect-RPC Handshake Confirmation",
                "stepCount": 1,
                "status": "CASCADE_RUN_STATUS_DONE",
                "lastModifiedTime": "2026-11-11T08:59:00.000000000Z",
                "workspaces": [
                    ["workspaceFolderAbsoluteUri": "file:///Users/dev/iOSAntigravity"]
                ]
            ],
            // Running Cloud VM session (`iOSAntigravity` -> `Cloud · venciallee/iOSAntigravity · main` with 2x2 four-dot loading indicator)
            "cid-arch-research": [
                "summary": "Antigravity iOS App Architecture Research",
                "stepCount": 3,
                "status": "CASCADE_RUN_STATUS_RUNNING",
                "lastModifiedTime": "2026-11-11T08:58:00.000000000Z",
                "workspaces": [
                    ["workspaceFolderAbsoluteUri": "file:///home/antigravity"],
                    [
                        "workspaceFolderAbsoluteUri": "file:///home/antigravity/venciallee/iOSAntigravity",
                        "gitBranch": "main"
                    ]
                ]
            ],
            // Unread completed Desktop session
            "cid-slardar-review": [
                "summary": "Slardar Tag Code Review",
                "stepCount": 5,
                "status": "CASCADE_RUN_STATUS_DONE",
                "lastModifiedTime": "2026-11-11T08:50:12.481920114Z",
                "annotations": [
                    "lastUserViewTime": "2026-11-11T08:30:00.000000Z"
                ],
                "workspaces": [
                    [
                        "workspaceFolderAbsoluteUri": "file:///Users/dev/slardar_app_ai",
                        "gitBranch": "main"
                    ]
                ]
            ],
            // Previously viewed idle Desktop session
            "cid-slardar-tracking": [
                "summary": "Slardar App AI 埋点梳理",
                "stepCount": 2,
                "status": "CASCADE_RUN_STATUS_IDLE",
                "lastModifiedTime": "2026-11-11T07:10:00.000000000Z",
                "annotations": [
                    "lastUserViewTime": "2026-11-11T07:25:00.000000Z"
                ],
                "workspaces": [
                    [
                        "workspaceFolderAbsoluteUri": "file:///Users/dev/slardar_app_ai",
                        "gitBranch": "main"
                    ]
                ]
            ]
        ]

        trajectoriesByCascadeId["cid-arch-research"] = [
            [
                "stepIndex": 0,
                "type": "CORTEX_STEP_TYPE_USER_INPUT",
                "status": "CORTEX_STEP_STATUS_DONE",
                "userInput": [
                    "items": [
                        ["text": "调研 Antigravity iOS App 与 PC language_server 的实时同步架构"]
                    ]
                ]
            ],
            [
                "stepIndex": 1,
                "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
                "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                "plannerResponse": [
                    "response": "正在通过 JetboxSubscribeToSummaries 与 ProjectUpdatesStream 同步全部项目会话..."
                ]
            ]
        ]

        trajectoriesByCascadeId["cid-slardar-review"] = [
            [
                "stepIndex": 0,
                "type": "CORTEX_STEP_TYPE_USER_INPUT",
                "status": "CORTEX_STEP_STATUS_DONE",
                "userInput": [
                    "userResponse": "",
                    "items": [
                        ["text": "请帮我 Review Slardar Tag 核心代码逻辑"],
                        [
                            "item": [
                                "file": [
                                    "absoluteUri": "file:///Users/dev/slardar_app_ai/internal/tag/manager.go"
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            [
                "stepIndex": 1,
                "type": "CORTEX_STEP_TYPE_CHECKPOINT",
                "status": "CORTEX_STEP_STATUS_DONE"
            ],
            [
                "stepIndex": 2,
                "type": "CORTEX_STEP_TYPE_VIEW_FILE",
                "status": "CORTEX_STEP_STATUS_DONE",
                "viewFile": [
                    "absolutePathUri": "file:///Users/dev/slardar_app_ai/internal/tag/manager.go",
                    "startLine": 1,
                    "endLine": 88
                ]
            ],
            [
                "stepIndex": 3,
                "type": "CORTEX_STEP_TYPE_GREP_SEARCH",
                "status": "CORTEX_STEP_STATUS_DONE",
                "grepSearch": [
                    "query": "RegisterTagValidator",
                    "searchPath": "internal/tag"
                ]
            ],
            [
                "stepIndex": 4,
                "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
                "status": "CORTEX_STEP_STATUS_DONE",
                "plannerResponse": [
                    "modifiedResponse": "",
                    "response": "已完成 Slardar Tag 模块审查：建议在 RegisterTagValidator 增加空值保护。",
                    "thinking": "Checked manager.go and validator chain.",
                    "thinkingDuration": "5.2s"
                ]
            ]
        ]

        trajectoriesByCascadeId["cid-slardar-tracking"] = [
            [
                "stepIndex": 0,
                "type": "CORTEX_STEP_TYPE_USER_INPUT",
                "status": "CORTEX_STEP_STATUS_DONE",
                "userInput": [
                    "items": [
                        ["text": "梳理 Slardar App AI 全链路埋点上报时机"]
                    ]
                ]
            ],
            [
                "stepIndex": 1,
                "type": "CORTEX_STEP_TYPE_NOTIFY_USER",
                "status": "CORTEX_STEP_STATUS_DONE",
                "notifyUser": [
                    "notificationContent": "已整理完冷启动、会话切换与异常捕获三处核心埋点。"
                ]
            ]
        ]
    }

    /// Simulates a new message sent from Antigravity Desktop (PC) while iOS is viewing the conversation.
    func injectPCMessage(cascadeId: String, userText: String, assistantReply: String) {
        lock.lock()
        defer { lock.unlock() }
        var steps = trajectoriesByCascadeId[cascadeId] ?? []
        let baseIdx = steps.count
        steps.append([
            "stepIndex": baseIdx,
            "type": "CORTEX_STEP_TYPE_USER_INPUT",
            "status": "CORTEX_STEP_STATUS_DONE",
            "userInput": [
                "items": [["text": userText]]
            ]
        ])
        steps.append([
            "stepIndex": baseIdx + 1,
            "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
            "status": "CORTEX_STEP_STATUS_DONE",
            "plannerResponse": [
                "modifiedResponse": "",
                "response": assistantReply
            ]
        ])
        trajectoriesByCascadeId[cascadeId] = steps
        if var summary = summariesMap[cascadeId] {
            summary["stepCount"] = steps.count
            summary["status"] = "CASCADE_RUN_STATUS_DONE"
            summary["lastModifiedTime"] = "2026-11-11T09:05:00.000000000Z"
            summariesMap[cascadeId] = summary
        }
    }

    /// Simulates an outside-workspace permission waiting gate (e.g. listDirectory + requestedInteraction.permission).
    func injectWaitingPermissionStep(cascadeId: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        var steps = trajectoriesByCascadeId[cascadeId] ?? []
        let waitingIdx = steps.count
        steps.append([
            "stepIndex": waitingIdx,
            "type": "CORTEX_STEP_TYPE_LIST_DIRECTORY",
            "status": "CORTEX_STEP_STATUS_WAITING",
            "listDirectory": [
                "directoryPathUri": "file:///Users/dev/external-workspace"
            ],
            "requestedInteraction": [
                "permission": [
                    "action": "list_dir",
                    "target": "/Users/dev/external-workspace",
                    "suggestedPersistPattern": "/Users/dev/external-workspace/*",
                    "reason": "Outside current workspace"
                ]
            ]
        ])
        trajectoriesByCascadeId[cascadeId] = steps
        if var summary = summariesMap[cascadeId] {
            summary["stepCount"] = steps.count
            summary["status"] = "CASCADE_RUN_STATUS_WAITING_FOR_USER"
            summary["lastModifiedTime"] = "2026-11-11T09:06:00.000000000Z"
            summariesMap[cascadeId] = summary
        }
        return waitingIdx
    }

    private func acceptLoop() {
        while true {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.accept(listenFD, sockPtr, &clientLen)
                }
            }
            if clientFD < 0 {
                lock.lock()
                let stopped = isStopped
                lock.unlock()
                if stopped { break }
                continue
            }
            var yes: Int32 = 1
            _ = Darwin.setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { Darwin.close(fd) }

        var rawData = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let headerSeparator = Data("\r\n\r\n".utf8)
        var headerEndIndex: Int?
        var expectedBodyBytes = 0

        while true {
            let n = Darwin.recv(fd, &buffer, buffer.count, 0)
            if n <= 0 { break }
            rawData.append(contentsOf: buffer.prefix(n))

            if headerEndIndex == nil, let range = rawData.range(of: headerSeparator) {
                headerEndIndex = range.upperBound
                let headerString = String(decoding: rawData[..<range.lowerBound], as: UTF8.self)
                for line in headerString.split(separator: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        expectedBodyBytes = Int(val) ?? 0
                    }
                }
            }

            if let endIdx = headerEndIndex, rawData.count >= endIdx + expectedBodyBytes {
                break
            }
        }

        guard let bodyStart = headerEndIndex else { return }
        let headerText = String(decoding: rawData[..<(bodyStart - 4)], as: UTF8.self)
        let firstLine = headerText.split(separator: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        let path = parts.count >= 2 ? String(parts[1]) : "/"
        let bodyData = rawData.subdata(in: bodyStart..<min(rawData.count, bodyStart + expectedBodyBytes))

        let (statusCode, contentType, responseBody) = routeRequest(path: path, bodyData: bodyData)
        var headerLines = "HTTP/1.1 \(statusCode) OK\r\n"
        headerLines += "Content-Type: \(contentType)\r\n"
        headerLines += "Content-Length: \(responseBody.count)\r\n"
        headerLines += "Connection: close\r\n\r\n"

        var out = Data(headerLines.utf8)
        out.append(responseBody)
        out.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var sent = 0
            while sent < out.count {
                let written = Darwin.send(fd, base.advanced(by: sent), out.count - sent, 0)
                if written <= 0 { break }
                sent += written
            }
        }
    }

    private func routeRequest(path: String, bodyData: Data) -> (Int, String, Data) {
        if path.hasSuffix("/GetWorkspaceInfos") || path.hasSuffix("/GetAllCascadeTrajectories") {
            waitWhileHandshakePaused()
        }
        lock.lock()
        let isOffline = simulatedOffline
        lock.unlock()
        if isOffline {
            return (503, "application/json", Data("{\"error\":\"Antigravity Desktop is offline\"}".utf8))
        }

        let jsonBody = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]

        if path.hasSuffix("/JetboxSubscribeToSummaries") {
            lock.lock()
            let payloadDict: [String: Any] = ["updates": summariesMap, "deletes": []]
            lock.unlock()
            let jsonBytes = (try? JSONSerialization.data(withJSONObject: payloadDict)) ?? Data("{}".utf8)
            var frame = Data([0x00])
            var lenBE = UInt32(jsonBytes.count).bigEndian
            withUnsafeBytes(of: &lenBE) { frame.append(contentsOf: $0) }
            frame.append(jsonBytes)
            frame.append(contentsOf: [0x02, 0x00, 0x00, 0x00, 0x02])
            frame.append(contentsOf: "{}".utf8)
            return (200, "application/connect+json", frame)
        }

        lock.lock()
        defer { lock.unlock() }

        let responseDict: [String: Any]
        if path.hasSuffix("/GetWorkspaceInfos") {
            responseDict = [
                "workspaceInfos": [
                    [
                        "workspaceUri": "file:///Users/dev/iOSAntigravity",
                        "gitBranch": "main"
                    ],
                    [
                        "workspaceUri": "file:///Users/dev/slardar_app_ai",
                        "gitBranch": "main"
                    ]
                ]
            ]
        } else if path.hasSuffix("/GetUserStatus") {
            responseDict = [
                "serverInfo": ["version": "v2.33.0"],
                "userStatus": [
                    "name": "Vencial Lee",
                    "email": "venciallee@gmail.com",
                    "userTier": ["name": "Google AI Ultra"]
                ]
            ]
        } else if path.hasSuffix("/GetAllCascadeTrajectories") {
            responseDict = ["trajectorySummaries": summariesMap]
        } else if path.hasSuffix("/GetCascadeTrajectorySteps") {
            let cid = (jsonBody["cascadeId"] as? String) ?? ""
            let allSteps = trajectoriesByCascadeId[cid] ?? []
            let startIdx = max(0, (jsonBody["startIndex"] as? Int) ?? 0)
            let endIdx = min(allSteps.count, max(startIdx, (jsonBody["endIndex"] as? Int) ?? allSteps.count))
            let slice = startIdx < endIdx ? Array(allSteps[startIdx..<endIdx]) : []
            responseDict = ["steps": slice]
        } else if path.hasSuffix("/ListAutomations") {
            responseDict = ["automations": []]
        } else if path.hasSuffix("/GetSidecars") {
            responseDict = ["sidecars": []]
        } else if path.hasSuffix("/GetSidecarEvents") {
            responseDict = ["events": []]
        } else if path.hasSuffix("/ManageSidecar") {
            let sid = (jsonBody["sidecarId"] as? String) ?? "auto-mock"
            responseDict = ["sidecarId": sid, "ok": true]
        } else if path.hasSuffix("/StartCascade") {
            createdCounter += 1
            let newId = "cid-live-created-\(createdCounter)"
            let wsUris = (jsonBody["workspaceUris"] as? [String]) ?? ["file:///Users/dev/slardar_app_ai"]
            let wsUri = wsUris.first ?? "file:///Users/dev/slardar_app_ai"
            summariesMap[newId] = [
                "summary": "New Conversation",
                "stepCount": 0,
                "status": "CASCADE_RUN_STATUS_IDLE",
                "lastModifiedTime": "2026-11-11T09:00:00.000000000Z",
                "workspaces": [
                    ["workspaceFolderAbsoluteUri": wsUri, "gitBranch": "main"]
                ]
            ]
            trajectoriesByCascadeId[newId] = []
            responseDict = ["cascadeId": newId]
        } else if path.hasSuffix("/SendUserCascadeMessage") {
            let cid = (jsonBody["cascadeId"] as? String) ?? ""
            var promptText = (jsonBody["userResponse"] as? String) ?? ""
            if promptText.isEmpty,
               let items = jsonBody["items"] as? [[String: Any]],
               let firstText = items.first?["text"] as? String {
                promptText = firstText
            }
            var steps = trajectoriesByCascadeId[cid] ?? []
            let baseIdx = steps.count
            steps.append([
                "stepIndex": baseIdx,
                "type": "CORTEX_STEP_TYPE_USER_INPUT",
                "status": "CORTEX_STEP_STATUS_DONE",
                "userInput": [
                    "items": [["text": promptText]]
                ]
            ])
            steps.append([
                "stepIndex": baseIdx + 1,
                "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
                "status": "CORTEX_STEP_STATUS_DONE",
                "plannerResponse": [
                    "modifiedResponse": "",
                    "response": "收到来自 iOS 真模拟器的实时指令，已同步至 Desktop。"
                ]
            ])
            trajectoriesByCascadeId[cid] = steps
            if var summary = summariesMap[cid] {
                summary["summary"] = String(promptText.prefix(40))
                summary["stepCount"] = steps.count
                summary["status"] = "CASCADE_RUN_STATUS_DONE"
                summariesMap[cid] = summary
            }
            responseDict = ["ok": true]
        } else if path.hasSuffix("/HandleCascadeUserInteraction") {
            let interaction = (jsonBody["interaction"] as? [String: Any]) ?? [:]
            let cid = (interaction["trajectoryId"] as? String) ?? ""
            let targetIdx = (interaction["stepIndex"] as? Int) ?? -1
            var steps = trajectoriesByCascadeId[cid] ?? []
            if targetIdx >= 0 && targetIdx < steps.count {
                steps[targetIdx]["status"] = "CORTEX_STEP_STATUS_DONE"
            }
            steps.append([
                "stepIndex": steps.count,
                "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
                "status": "CORTEX_STEP_STATUS_DONE",
                "plannerResponse": [
                    "response": "权限已批准，继续执行目录扫描。"
                ]
            ])
            trajectoriesByCascadeId[cid] = steps
            if var summary = summariesMap[cid] {
                summary["stepCount"] = steps.count
                summary["status"] = "CASCADE_RUN_STATUS_DONE"
                summary["lastModifiedTime"] = "2026-11-11T09:07:00.000000000Z"
                summariesMap[cid] = summary
            }
            responseDict = ["accepted": true]
        } else {
            responseDict = ["ok": true]
        }

        let data = (try? JSONSerialization.data(withJSONObject: responseDict)) ?? Data("{}".utf8)
        return (200, "application/json", data)
    }
}

@MainActor
final class AntigravityInteractiveUITests: XCTestCase {

    private func launchLiveApp(serverPort: UInt16) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ANTIGRAVITY_BACKEND_URL"] = "http://127.0.0.1:\(serverPort)"
        app.launchEnvironment["ANTIGRAVITY_CSRF_TOKEN"] = "uitest-csrf-token"
        app.launchEnvironment["ANTIGRAVITY_HOST_NAME"] = "MacBook-Pro-Live"
        app.launchEnvironment["NO_PROXY"] = "127.0.0.1,localhost,::1"
        app.launchEnvironment["no_proxy"] = "127.0.0.1,localhost,::1"
        app.launch()
        return app
    }

    /// Domain: Agents Home (`UE01`) + Cascade Chat (`UE07`) + Real-Time PC Sync + Inline/Status Permission Gate.
    func testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate() throws {
        let server = try EmbeddedDesktopMockServer()
        defer { server.stop() }

        // 0. Verify cold launch enters the Conversations screen immediately with inline loading instead of stalling on Welcome screen
        server.setHandshakePaused(true)
        defer { server.setHandshakePaused(false) }
        let app = launchLiveApp(serverPort: server.port)
        let inlineLoadingCard = app.descendants(matching: .any)["agents-loading-conversations"].firstMatch
        XCTAssertTrue(
            inlineLoadingCard.waitForExistence(timeout: 6),
            "Conversations screen must display inline loading state while backend handshake is in progress"
        )
        let hostPill = app.buttons["host-switcher-pill"]
        XCTAssertTrue(
            hostPill.waitForExistence(timeout: 4),
            "Cold launch must enter the Conversations screen immediately without blocking on the Welcome screen"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["welcome-screen"].firstMatch.exists,
            "Launch/Welcome screen must not block the user while connecting"
        )
        server.setHandshakePaused(false)

        // 1. Open Sidebar Drawer (`UE01B`) and verify live Desktop + Cloud sessions load, running indicator is present, and synthetic probe / 0-step placeholder are filtered out
        let sidebarButton = app.buttons["btn-sidebar"]
        XCTAssertTrue(
            sidebarButton.waitForExistence(timeout: 8),
            "New Conversation Home must render left sidebar trigger btn-sidebar"
        )
        let heroGreeting = app.descendants(matching: .any)["home-hero-greeting"].firstMatch
        XCTAssertTrue(
            heroGreeting.waitForExistence(timeout: 5),
            "New Conversation Home must render hero greeting"
        )
        let resolvedNamePredicate = NSPredicate(format: "label CONTAINS[c] %@", "Vencial")
        let resolvedNameExpectation = XCTNSPredicateExpectation(predicate: resolvedNamePredicate, object: heroGreeting)
        XCTAssertEqual(
            XCTWaiter.wait(for: [resolvedNameExpectation], timeout: 10),
            .completed,
            "Live hero greeting must display the signed-in user name from GetUserStatus (saw: \(heroGreeting.label))"
        )
        XCTAssertFalse(
            heroGreeting.label.contains("Alex"),
            "Live hero greeting must never show hardcoded mock name 'Alex' (saw: \(heroGreeting.label))"
        )
        attachScreenshot(named: "01_Live_Agents_Home")

        sidebarButton.tap()
        let reviewRow = app.buttons["drawer-conv-cid-slardar-review"]
        XCTAssertTrue(
            reviewRow.waitForExistence(timeout: 12),
            "Live Desktop conversation row 'Slardar Tag Code Review' must render inside Sidebar Drawer"
        )
        let archResearchRow = app.buttons["drawer-conv-cid-arch-research"]
        XCTAssertTrue(
            archResearchRow.waitForExistence(timeout: 6),
            "Cloud project conversation 'Antigravity iOS App Architecture Research' must render inside Sidebar Drawer"
        )
        let iosCloudHeader = app.buttons["project-header-iOSAntigravity"]
        XCTAssertTrue(
            iosCloudHeader.waitForExistence(timeout: 5),
            "Cloud VM project header 'iOSAntigravity' must render inside Sidebar Drawer"
        )
        let fourDotIndicator = app.descendants(matching: .any)["loading-four-dots-cid-arch-research"].firstMatch
        XCTAssertTrue(
            fourDotIndicator.waitForExistence(timeout: 5),
            "Running conversation row MUST render the active running indicator"
        )
        XCTAssertFalse(
            app.buttons["drawer-conv-cid-blank-placeholder"].exists,
            "Unused 0-step Desktop tab placeholders must not appear in Sidebar Drawer"
        )
        XCTAssertFalse(
            app.buttons["drawer-conv-cid-synthetic-probe"].exists,
            "Synthetic 'iOS Connect-RPC Handshake' probe sessions must be filtered out"
        )
        attachScreenshot(named: "01b_Live_Sidebar_Drawer")

        // 2. REAL TAP on conversation row -> MUST open CascadeChatViewController and load steps
        reviewRow.tap()

        let navTitle = app.descendants(matching: .any)["chat-nav-title"].firstMatch
        XCTAssertTrue(
            navTitle.waitForExistence(timeout: 6),
            "Tapping a conversation row in Sidebar Drawer MUST navigate to CascadeChatViewController"
        )
        XCTAssertTrue(navTitle.label.contains("Slardar Tag Code Review"))

        XCTAssertTrue(
            waitForTextContaining("请帮我 Review Slardar Tag 核心代码逻辑", in: app, timeout: 6),
            "Real Desktop userInput items[].text must render inside CascadeChatViewController"
        )
        XCTAssertTrue(
            waitForTextContaining("已完成 Slardar Tag 模块审查", in: app, timeout: 6),
            "Real Desktop plannerResponse must render even when modifiedResponse is empty"
        )

        // 2b. Simulate PC sending a new message while iOS is viewing this conversation -> verify iOS auto-updates in real time!
        server.injectPCMessage(
            cascadeId: "cid-slardar-review",
            userText: "PC 端新增的实时追问消息：请补充单元测试",
            assistantReply: "已为您补充 RegisterTagValidator 的边界单元测试。"
        )
        XCTAssertTrue(
            waitForTextContaining("PC 端新增的实时追问消息：请补充单元测试", in: app, timeout: 12),
            "New message added on PC must automatically appear on iOS within seconds without touching the screen"
        )
        XCTAssertTrue(
            waitForTextContaining("已为您补充 RegisterTagValidator 的边界单元测试", in: app, timeout: 6),
            "New assistant reply from PC must automatically appear on iOS"
        )

        // 2c. Inject outside-workspace `list_dir` permission gate -> verify BOTH inline approval card AND status strip Approve button appear, then tap Allow Once!
        let waitingStepIdx = server.injectWaitingPermissionStep(cascadeId: "cid-slardar-review")
        let statusApproveButton = app.buttons["btn-status-review-approval"]
        XCTAssertTrue(
            statusApproveButton.waitForExistence(timeout: 12),
            "Waiting permission step must surface an immediately tappable Approve pill in the status strip"
        )
        let inlineApproveButton = app.buttons["btn-step-approve-\(waitingStepIdx)"]
        XCTAssertTrue(
            inlineApproveButton.waitForExistence(timeout: 6),
            "Waiting permission step must render its inline Allow Once button inside the chat stream"
        )
        inlineApproveButton.tap()
        XCTAssertTrue(
            waitForTextContaining("权限已批准，继续执行目录扫描", in: app, timeout: 10),
            "Tapping Allow Once must dispatch HandleCascadeUserInteraction and stream resumed steps"
        )

        // Verify zero offline ESDD mock artifacts leak into live conversation view
        XCTAssertFalse(app.buttons["composer-chip-ratelimit"].exists, "Offline @ratelimit.go mock chip must not appear in live mode")
        XCTAssertFalse(app.buttons["chat-diff-pill"].exists, "Offline +128/-14 mock diff pill must not appear when live diffs are zero")
        attachScreenshot(named: "02_Opened_Live_Conversation_Detail")
    }

    /// Domain: Sidebar Drawer Swipe Open/Close (`UE01B`) + Project Detail (`UE04`) + Navigation Stack + Native iOS Left-Edge Swipe-Back (`interactivePopGestureRecognizer`).
    func testProjectDetailNavigationAndEdgeSwipeBack() throws {
        let server = try EmbeddedDesktopMockServer()
        defer { server.stop() }

        let app = launchLiveApp(serverPort: server.port)

        let sidebarButton = app.buttons["btn-sidebar"]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 10))
        let heroGreeting = app.descendants(matching: .any)["home-hero-greeting"].firstMatch
        XCTAssertTrue(heroGreeting.waitForExistence(timeout: 6))

        // 0. Swipe left-to-right from the left edge on Home -> must slide open Sidebar Drawer; swipe right-to-left -> must close it
        performEdgeSwipeBack(in: app)
        let drawerPanel = app.descendants(matching: .any)["sidebar-drawer-panel"].firstMatch
        XCTAssertTrue(
            drawerPanel.waitForExistence(timeout: 5),
            "Swiping left-to-right from the left edge on Home must slide open the Sidebar Drawer"
        )
        let reviewRow = app.buttons["drawer-conv-cid-slardar-review"]
        XCTAssertTrue(reviewRow.waitForExistence(timeout: 12))

        performSwipeCloseDrawer(in: app)
        XCTAssertTrue(
            waitForNonExistence(drawerPanel, timeout: 5),
            "Swiping right-to-left on the open Sidebar Drawer must dismiss it back to Home"
        )

        // 1. Re-open Sidebar via edge swipe -> open Conversation -> swipe left-to-right -> must open Sidebar Drawer (not pop to blank Home)
        performEdgeSwipeBack(in: app)
        XCTAssertTrue(reviewRow.waitForExistence(timeout: 5))
        reviewRow.tap()
        let chatNavTitle = app.descendants(matching: .any)["chat-nav-title"].firstMatch
        XCTAssertTrue(chatNavTitle.waitForExistence(timeout: 6))

        performEdgeSwipeBack(in: app)
        XCTAssertTrue(
            drawerPanel.waitForExistence(timeout: 5),
            "Swiping left-to-right from the left edge on a sidebar-launched Conversation must open the Sidebar Drawer"
        )

        // 2. Collapse & expand project conversation list, then open Project Detail from swiped-open Sidebar
        let projectToggle = app.buttons["btn-toggle-project-slardar_app_ai"]
        XCTAssertTrue(
            projectToggle.waitForExistence(timeout: 5),
            "Non-empty project group in sidebar must expose collapse/expand toggle button"
        )
        projectToggle.tap()
        XCTAssertTrue(
            waitForNonExistence(reviewRow, timeout: 4),
            "Tapping project collapse toggle must hide project conversation rows"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["project-collapsed-count-slardar_app_ai"].firstMatch.waitForExistence(timeout: 4),
            "Collapsed project header must display muted conversation count badge"
        )
        projectToggle.tap()
        XCTAssertTrue(
            reviewRow.waitForExistence(timeout: 4),
            "Tapping project collapse toggle a second time must expand project conversation rows back"
        )

        let projectHeader = app.buttons["project-header-slardar_app_ai"]
        XCTAssertTrue(projectHeader.waitForExistence(timeout: 5))
        projectHeader.tap()

        let backToAgentsButton = app.buttons["btn-back-agents"]
        XCTAssertTrue(
            backToAgentsButton.waitForExistence(timeout: 5),
            "Tapping project header must open ProjectDetailViewController"
        )
        attachScreenshot(named: "03_Opened_Live_Project_Detail")

        let projectConvRow = app.buttons["project-conv-row-cid-slardar-tracking"]
        XCTAssertTrue(projectConvRow.waitForExistence(timeout: 5))
        projectConvRow.tap()

        let backToSessionsButton = app.buttons["btn-back-sessions"]
        XCTAssertTrue(
            backToSessionsButton.waitForExistence(timeout: 5),
            "Tapping a conversation row inside ProjectDetailViewController must open CascadeChatViewController with back button"
        )
        XCTAssertTrue(app.descendants(matching: .any)["chat-nav-title"].firstMatch.label.contains("Slardar App AI 埋点梳理"))
        XCTAssertTrue(
            waitForTextContaining("已整理完冷启动", in: app, timeout: 5),
            "CORTEX_STEP_TYPE_NOTIFY_USER content must render in CascadeChatViewController"
        )

        // Back button from project-launched chat returns to ProjectDetail, then back to Home
        backToSessionsButton.tap()
        XCTAssertTrue(backToAgentsButton.waitForExistence(timeout: 5))
        backToAgentsButton.tap()
        XCTAssertTrue(heroGreeting.waitForExistence(timeout: 5))

        // 3. Re-enter Project Detail via Sidebar -> Conversation -> edge-swipe back to Project Detail -> edge-swipe back to Home
        sidebarButton.tap()
        XCTAssertTrue(projectHeader.waitForExistence(timeout: 5))
        projectHeader.tap()
        XCTAssertTrue(backToAgentsButton.waitForExistence(timeout: 5))
        projectConvRow.tap()
        XCTAssertTrue(backToSessionsButton.waitForExistence(timeout: 5))

        performEdgeSwipeBack(in: app)
        XCTAssertTrue(
            backToAgentsButton.waitForExistence(timeout: 5),
            "Edge-swipe back from a project-launched Conversation must pop back to Project Detail"
        )

        performEdgeSwipeBack(in: app)
        XCTAssertTrue(
            heroGreeting.waitForExistence(timeout: 5),
            "Edge-swipe back from Project Detail must pop back to Home"
        )
    }

    /// Domain: Host Reachability / Offline Recovery + Settings (`UE15`) Copyright & Language.
    func testOfflineHostRecoveryAndSettingsAttribution() throws {
        let server = try EmbeddedDesktopMockServer()
        defer { server.stop() }

        let app = launchLiveApp(serverPort: server.port)

        let hostPill = app.buttons["host-switcher-pill"]
        XCTAssertTrue(hostPill.waitForExistence(timeout: 12))
        XCTAssertTrue(
            waitForTextContaining("MacBook-Pro-Live", in: app, timeout: 6),
            "Initial online host pill must display MacBook-Pro-Live"
        )

        // 1. Simulate Desktop / Bridge going offline -> verify top pill shows Offline, then auto-recover!
        server.setSimulatedOffline(true)
        XCTAssertTrue(
            waitForTextContaining("MacBook-Pro-Live · Offline", in: app, timeout: 18),
            "Top host switcher pill must transition to '<hostname> · Offline' when Desktop goes offline"
        )
        attachScreenshot(named: "03b_Offline_Host_And_Cloud_Project")

        server.setSimulatedOffline(false)
        XCTAssertTrue(
            waitForTextContaining("MacBook-Pro-Live", in: app, timeout: 18),
            "App must automatically reconnect and restore online status when Desktop returns"
        )

        // 2. Open Sidebar -> Settings (`UE15`) -> verify Copyright / Trademark attribution & Language switcher
        let sidebarButton = app.buttons["btn-sidebar"]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 5))
        sidebarButton.tap()
        let settingsNav = app.buttons["drawer-nav-settings"]
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 5))
        settingsNav.tap()

        let langZhButton = app.buttons["btn-lang-zh-Hans"]
        scrollUntilHittable(langZhButton, in: app, maxSwipes: 4)
        XCTAssertTrue(langZhButton.waitForExistence(timeout: 5), "Settings must render Language switcher")

        let copyrightCard = app.descendants(matching: .any)["card-about-copyright"].firstMatch
        scrollUntilHittable(copyrightCard, in: app, maxSwipes: 8)
        XCTAssertTrue(
            copyrightCard.waitForExistence(timeout: 5),
            "Settings screen must render card-about-copyright"
        )
        XCTAssertTrue(
            waitForTextContaining("Google LLC", in: app, timeout: 5),
            "Settings screen must display Google LLC App Icon & Trademark copyright attribution"
        )
    }

    /// Domain: Automations (`UE06`) — 'Create with Prompt' unsent draft flow & '+ New' entry points via Sidebar Drawer.
    func testAutomationsCreateWithPromptDraftFlow() throws {
        let server = try EmbeddedDesktopMockServer()
        defer { server.stop() }

        let app = launchLiveApp(serverPort: server.port)

        let sidebarButton = app.buttons["btn-sidebar"]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 12))
        sidebarButton.tap()

        let automationsNav = app.buttons["drawer-nav-automations"]
        XCTAssertTrue(automationsNav.waitForExistence(timeout: 5))
        automationsNav.tap()

        let createWithPromptButton = app.buttons["btn-empty-agent-automation"]
        XCTAssertTrue(
            createWithPromptButton.waitForExistence(timeout: 6),
            "Automations empty state must render 'Create with Prompt' button"
        )
        XCTAssertTrue(
            createWithPromptButton.label.contains("Create with Prompt"),
            "Create with Prompt button copy must match PC reference"
        )
        let newAutomationButton = app.buttons["btn-empty-new-automation"]
        XCTAssertTrue(
            newAutomationButton.waitForExistence(timeout: 5),
            "Automations empty state must render '+ New' button"
        )
        XCTAssertTrue(
            newAutomationButton.label.contains("New"),
            "New automation button copy must match PC reference"
        )

        createWithPromptButton.tap()
        let workflowChip = app.buttons["composer-workflow-chip"]
        XCTAssertTrue(
            workflowChip.waitForExistence(timeout: 5),
            "Draft composer must display the removable 'automation' workflow chip"
        )
        let draftCard = app.descendants(matching: .any)["chat-pending-draft-card"].firstMatch
        XCTAssertTrue(
            draftCard.waitForExistence(timeout: 5),
            "Create with Prompt must show the unsent draft card rather than immediately sending /automation"
        )
        XCTAssertFalse(
            app.buttons["btn-stop-turn"].exists,
            "Create with Prompt must NOT immediately start streaming before user taps Send"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["chat-inline-four-dot-loading"].firstMatch.exists,
            "Create with Prompt must NOT immediately start agent execution"
        )
        attachScreenshot(named: "03d_Automations_CreateWithPrompt_Draft")

        performEdgeSwipeBack(in: app)
        XCTAssertTrue(
            createWithPromptButton.waitForExistence(timeout: 5),
            "Navigating back from an unsent Create with Prompt draft must return cleanly to Automations"
        )
    }

    /// Domain: New Conversation Home (`UE01`) + Unified ChatComposerView (`UE07`) -> Live `StartCascade` + `SendUserCascadeMessage` round-trip.
    func testComposeFABStartCascadeAndStreamedReply() throws {
        let server = try EmbeddedDesktopMockServer()
        defer { server.stop() }

        let app = launchLiveApp(serverPort: server.port)

        let heroGreeting = app.descendants(matching: .any)["home-hero-greeting"].firstMatch
        XCTAssertTrue(heroGreeting.waitForExistence(timeout: 12))

        // 1. Verify legacy Planning/Fast pill & /btw clutter are completely absent from the unified composer
        XCTAssertFalse(app.descendants(matching: .any)["composer-pill-mode"].firstMatch.exists, "Legacy Planning/Fast pill must not appear")
        XCTAssertFalse(app.descendants(matching: .any)["composer-btn-btw"].firstMatch.exists, "Legacy /btw pill must not appear above input")
        XCTAssertFalse(app.descendants(matching: .any)["composer-btn-attach-file"].firstMatch.exists, "Legacy Attach pill must not appear above input")

        // 2. Verify unified UE v2.1 composer controls: `+`, Model+Effort, `🛡 Default`, `mic`, `→`
        XCTAssertTrue(app.descendants(matching: .any)["composer-btn-add-context"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composer-pill-model"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composer-pill-permissions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composer-btn-mic"].waitForExistence(timeout: 5))
        let sendButton = app.buttons["composer-btn-send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        XCTAssertFalse(sendButton.isEnabled, "Send button must stay disabled when draft text is empty")
        let runtimeToggle = app.buttons["home-runtime-toggle"]
        XCTAssertTrue(runtimeToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForRuntimeToggleState(runtimeToggle, label: "Cloud runtime selected", value: "cloud"),
            "Initial cloud project must show cloud runtime state (got label=\(runtimeToggle.label), value=\(String(describing: runtimeToggle.value)))"
        )

        // Switching to local project `slardar_app_ai` must switch the right-hand cloud icon to the local computer icon
        let projectSelector = app.descendants(matching: .any)["home-project-selector"].firstMatch
        XCTAssertTrue(projectSelector.waitForExistence(timeout: 5))
        projectSelector.tap()
        let localProjectOption = app.buttons["slardar_app_ai"].firstMatch
        XCTAssertTrue(localProjectOption.waitForExistence(timeout: 5), "Local project slardar_app_ai must appear in project selector menu")
        localProjectOption.tap()

        XCTAssertTrue(
            waitForRuntimeToggleState(runtimeToggle, label: "Local runtime selected", value: "computer"),
            "Selecting local project must switch runtime toggle to computer icon (got label=\(runtimeToggle.label), value=\(String(describing: runtimeToggle.value)))"
        )

        // Direct toggle switches between cloud and local computer states
        runtimeToggle.tap()
        XCTAssertTrue(
            waitForRuntimeToggleState(runtimeToggle, label: "Cloud runtime selected", value: "cloud"),
            "Tapping runtime toggle must switch to cloud state (got label=\(runtimeToggle.label), value=\(String(describing: runtimeToggle.value)))"
        )

        runtimeToggle.tap()
        XCTAssertTrue(
            waitForRuntimeToggleState(runtimeToggle, label: "Local runtime selected", value: "computer"),
            "Tapping runtime toggle again must restore local computer state (got label=\(runtimeToggle.label), value=\(String(describing: runtimeToggle.value)))"
        )
        attachScreenshot(named: "04a_Live_Composer_Idle_Claude_Style")

        // 3. Typing enables Send button and dispatches StartCascade + SendUserCascadeMessage
        let composerInput = app.descendants(matching: .any)["composer-text-input"].firstMatch
        XCTAssertTrue(composerInput.waitForExistence(timeout: 5))
        composerInput.tap()
        composerInput.typeText("Verify live Simulator tap and send")

        XCTAssertTrue(
            sendButton.waitForExistence(timeout: 5) && sendButton.isEnabled,
            "Typing into the composer must enable the Send button"
        )
        attachScreenshot(named: "04b_Live_Composer_Typing_Send_Morph")
        sendButton.tap()

        XCTAssertTrue(
            waitForTextContaining("收到来自 iOS 真模拟器的实时指令", in: app, timeout: 20),
            "Sending a message in Composer must dispatch StartCascade + SendUserCascadeMessage and render streamed reply"
        )
        attachScreenshot(named: "04_Live_Composed_And_Streamed_Reply")
    }

    /// Domain: Flattened Settings (`UE15`: Appearance `System`/`Dark`/`Light`, Default Permissions 4 presets,
    /// Notifications toggles), lightweight Chat Permissions sync, and Customizations (`UE14`).
    func testAppearanceModeSwitchingLightAndDarkInSettingsAndChat() throws {
        let server = try EmbeddedDesktopMockServer()
        defer { server.stop() }

        let app = launchLiveApp(serverPort: server.port)

        let sidebarButton = app.buttons["btn-sidebar"]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 12))

        // 1. Open Sidebar -> Settings (`UE15`) and verify Appearance Mode controls exist
        sidebarButton.tap()
        let settingsNav = app.buttons["drawer-nav-settings"]
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 5))
        settingsNav.tap()

        let appearanceCard = app.descendants(matching: .any)["card-appearance-mode"].firstMatch
        scrollUntilHittable(appearanceCard, in: app, avoidBottomInset: 40)
        XCTAssertTrue(
            appearanceCard.waitForExistence(timeout: 6),
            "Settings must render card-appearance-mode"
        )

        let systemButton = app.buttons["appearance-mode-system"]
        let darkButton = app.buttons["appearance-mode-dark"]
        let lightButton = app.buttons["appearance-mode-light"]
        XCTAssertTrue(systemButton.waitForExistence(timeout: 5), "appearance-mode-system must exist in Settings")
        XCTAssertTrue(darkButton.waitForExistence(timeout: 5), "appearance-mode-dark must exist in Settings")
        XCTAssertTrue(lightButton.waitForExistence(timeout: 5), "appearance-mode-light must exist in Settings")

        // 2. Switch to Light Mode in Settings
        scrollUntilHittable(lightButton, in: app, avoidBottomInset: 40)
        lightButton.tap()
        XCTAssertTrue(
            waitForAppearanceOptionSelected(lightButton, timeout: 4),
            "Tapping appearance-mode-light must select Light Mode in Settings"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        attachScreenshot(named: "06a_Settings_Light_Mode")

        // 3. Verify Default Permissions (4 presets) and select Auto
        let permissionsAutoButton = app.buttons["settings-permission-auto"]
        scrollUntilHittable(permissionsAutoButton, in: app, maxSwipes: 6, avoidBottomInset: 40)
        XCTAssertTrue(
            permissionsAutoButton.waitForExistence(timeout: 5),
            "Settings must render settings-permission-auto row"
        )
        permissionsAutoButton.tap()
        XCTAssertTrue(
            waitForAppearanceOptionSelected(permissionsAutoButton, timeout: 4),
            "Tapping settings-permission-auto must select Auto in Settings"
        )

        // 4. Verify Notifications card renders both real switches
        let notificationsToggle = app.descendants(matching: .any)["toggle-notifications-enabled"].firstMatch
        scrollUntilHittable(notificationsToggle, in: app, maxSwipes: 6, avoidBottomInset: 40)
        XCTAssertTrue(
            notificationsToggle.waitForExistence(timeout: 5),
            "Settings must render toggle-notifications-enabled"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["toggle-notifications-suppress-manual-stop"].firstMatch.waitForExistence(timeout: 4),
            "Settings must render toggle-notifications-suppress-manual-stop"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        attachScreenshot(named: "06b_Settings_Permissions_And_Notifications")

        // 5. Switch to Dark Mode and back to Light Mode
        scrollUntilHittable(darkButton, in: app, maxSwipes: 6, avoidBottomInset: 40)
        darkButton.tap()
        XCTAssertTrue(
            waitForAppearanceOptionSelected(darkButton, timeout: 4),
            "Tapping appearance-mode-dark must select Dark Mode in Settings"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        attachScreenshot(named: "06c_Settings_Dark_Mode")

        scrollUntilHittable(lightButton, in: app, avoidBottomInset: 40)
        lightButton.tap()
        XCTAssertTrue(
            waitForAppearanceOptionSelected(lightButton, timeout: 4),
            "Tapping appearance-mode-light must switch back to Light Mode"
        )

        // 6. Close Settings -> Open Sidebar -> Open Cascade Chat in Light Mode and verify Permissions sync
        let closeSettingsBtn = app.buttons["btn-settings-close"]
        scrollUntilHittable(closeSettingsBtn, in: app, maxSwipes: 6)
        XCTAssertTrue(closeSettingsBtn.waitForExistence(timeout: 5))
        closeSettingsBtn.tap()

        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        attachScreenshot(named: "06d_AgentsHome_Light_Mode")

        sidebarButton.tap()
        let reviewRow = app.buttons["drawer-conv-cid-slardar-review"]
        XCTAssertTrue(reviewRow.waitForExistence(timeout: 6))
        reviewRow.tap()

        XCTAssertTrue(
            waitForTextContaining("已完成 Slardar Tag 模块审查", in: app, timeout: 6),
            "Cascade Chat messages must render cleanly in Light Mode"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        attachScreenshot(named: "06e_CascadeChat_Light_Mode")

        // 7. Open Permissions sheet from composer shield pill and verify Auto synced from Settings
        let composerPermPill = app.buttons["composer-pill-permissions"]
        XCTAssertTrue(composerPermPill.waitForExistence(timeout: 5), "Cascade Chat must render composer-pill-permissions")
        composerPermPill.tap()

        let chatAutoRow = app.buttons["permission-row-auto"]
        XCTAssertTrue(
            chatAutoRow.waitForExistence(timeout: 5),
            "PermissionsSheetView must render permission-row-auto"
        )
        XCTAssertTrue(
            waitForAppearanceOptionSelected(chatAutoRow, timeout: 4),
            "Selecting Auto in Settings must sync directly to Chat PermissionsSheetView"
        )
        let permissionsDoneButton = app.buttons["btn-permissions-done"]
        XCTAssertTrue(permissionsDoneButton.waitForExistence(timeout: 5))
        permissionsDoneButton.tap()

        // 8. Navigate via Sidebar -> Settings and restore Default permission & System appearance mode
        sidebarButton.tap()
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 5))
        settingsNav.tap()

        let permissionsDefaultButton = app.buttons["settings-permission-default"]
        scrollUntilHittable(permissionsDefaultButton, in: app, maxSwipes: 6, avoidBottomInset: 40)
        XCTAssertTrue(permissionsDefaultButton.waitForExistence(timeout: 5))
        permissionsDefaultButton.tap()
        XCTAssertTrue(
            waitForAppearanceOptionSelected(permissionsDefaultButton, timeout: 4),
            "Restoring Default permission must mark settings-permission-default as selected"
        )

        scrollUntilHittable(systemButton, in: app, maxSwipes: 6, avoidBottomInset: 40)
        XCTAssertTrue(systemButton.waitForExistence(timeout: 5))
        systemButton.tap()
        XCTAssertTrue(
            waitForAppearanceOptionSelected(systemButton, timeout: 4),
            "Restoring System appearance mode must mark appearance-mode-system as selected"
        )
    }

    /// Domain: Display Options (`UE02`) launched from Sidebar Drawer (`UE01B`) — Sort popover closed by default, dismissed on outside tap & option selection, and bound to live store state.
    func testDisplayOptionsPopoverDismissAndStoreSync() throws {
        let server = try EmbeddedDesktopMockServer()
        defer { server.stop() }

        let app = launchLiveApp(serverPort: server.port)
        let sidebarButton = app.buttons["btn-sidebar"]
        XCTAssertTrue(
            sidebarButton.waitForExistence(timeout: 12),
            "Live Agents Home must finish loading before opening Sidebar Drawer"
        )
        sidebarButton.tap()

        // 1. Open Display Options sheet from Sidebar Projects header -> Sort popover MUST start closed
        let displayOptionsButton = app.buttons["btn-display-options"]
        XCTAssertTrue(displayOptionsButton.waitForExistence(timeout: 5))
        displayOptionsButton.tap()

        let sortRow = app.buttons["row-sort-conversations"]
        XCTAssertTrue(
            sortRow.waitForExistence(timeout: 6),
            "Display Options sheet must present row-sort-conversations"
        )
        let sortMenu = app.descendants(matching: .any)["sort-popover-menu"].firstMatch
        XCTAssertFalse(
            sortMenu.exists,
            "Sort Conversations popover MUST NOT open by default when user opens Display Options"
        )

        // 2. Tap Sort Conversations row -> popover opens
        sortRow.tap()
        XCTAssertTrue(
            sortMenu.waitForExistence(timeout: 4),
            "Tapping Sort Conversations row must open sort-popover-menu"
        )

        // 3. Tap outside the popover on the sheet -> popover MUST dismiss while sheet stays open
        let dismissScrim = app.descendants(matching: .any)["sort-popover-dismiss-scrim"].firstMatch
        XCTAssertTrue(
            dismissScrim.waitForExistence(timeout: 3),
            "Open sort popover must present transparent outside-tap dismiss scrim"
        )
        dismissScrim.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.88)).tap()
        let dismissedAfterOutsideTap = waitUntilElementDisappears(sortMenu, timeout: 4)
        XCTAssertTrue(
            dismissedAfterOutsideTap,
            "Tapping outside sort-popover-menu must dismiss the popover"
        )
        XCTAssertTrue(
            sortRow.exists,
            "Dismissing sort-popover-menu via outside tap must keep Display Options sheet open"
        )

        // 4. Re-open Sort Conversations -> select 'Title' -> popover dismisses & row updates to Title
        sortRow.tap()
        XCTAssertTrue(sortMenu.waitForExistence(timeout: 4))
        let titleOption = app.buttons["sort-opt-title"]
        XCTAssertTrue(titleOption.waitForExistence(timeout: 4))
        titleOption.tap()
        XCTAssertTrue(
            waitUntilElementDisappears(sortMenu, timeout: 4),
            "Selecting a sort option must automatically dismiss sort-popover-menu"
        )
        XCTAssertTrue(
            waitForTextContaining("Title", in: app, timeout: 4),
            "Selecting Title must update Sort Conversations value from store.displayOptions"
        )

        // 5. Verify Mark All as Read uses live unread count (not hardcoded 3 unread) and drops to 0 unread
        let markAllReadButton = app.buttons["btn-mark-all-read"]
        XCTAssertTrue(markAllReadButton.waitForExistence(timeout: 4))
        XCTAssertFalse(
            markAllReadButton.label.contains("3 unread"),
            "Live Display Options must bind to real store.unreadCount instead of hardcoded 3 unread"
        )
        markAllReadButton.tap()
        XCTAssertTrue(
            waitForTextContaining("0 unread", in: app, timeout: 4),
            "Tapping Mark All as Read must drop live unread count to 0 unread"
        )

        // 6. Reset restores default 'Last Updated', and Done dismisses the sheet
        let resetButton = app.buttons["sheet-reset-btn"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 4))
        resetButton.tap()
        XCTAssertTrue(
            waitForTextContaining("Last Updated", in: app, timeout: 4),
            "Tapping Reset must restore default sort field 'Last Updated'"
        )

        let doneButton = app.buttons["sheet-done-btn"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 4))
        doneButton.tap()
        XCTAssertTrue(
            waitUntilElementDisappears(sortRow, timeout: 5),
            "Tapping Done must dismiss Display Options sheet back to Sidebar"
        )
    }

    private func waitUntilElementDisappears(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !element.exists
    }

    private func isAppearanceOptionSelected(_ element: XCUIElement) -> Bool {
        if element.isSelected {
            return true
        }
        if let rawValue = element.value as? String, rawValue.lowercased() == "selected" {
            return true
        }
        return false
    }

    private func waitForAppearanceOptionSelected(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && isAppearanceOptionSelected(element) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.exists && isAppearanceOptionSelected(element)
    }

    private func waitForRuntimeToggleState(
        _ element: XCUIElement,
        label: String,
        value: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.label == label && (element.value as? String) == value {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.exists && element.label == label && (element.value as? String) == value
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6,
        avoidBottomInset: CGFloat = 0,
        allowReverseSwipe: Bool = true
    ) {
        let appFrame = app.frame
        func isComfortablyVisible() -> Bool {
            guard element.exists && element.isHittable else { return false }
            let frame = element.frame
            guard !frame.isEmpty else { return false }
            return frame.minY >= appFrame.minY + 72 && frame.maxY <= appFrame.maxY - avoidBottomInset
        }
        if isComfortablyVisible() { return }

        let dragUpStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let dragUpEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let dragDownStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        let dragDownEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))

        for _ in 0..<maxSwipes {
            if isComfortablyVisible() { return }
            let frame = element.exists ? element.frame : .zero
            if allowReverseSwipe && !frame.isEmpty && frame.minY < appFrame.minY + 72 {
                dragDownStart.press(forDuration: 0.02, thenDragTo: dragDownEnd)
            } else {
                dragUpStart.press(forDuration: 0.02, thenDragTo: dragUpEnd)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        if allowReverseSwipe && !isComfortablyVisible() {
            for _ in 0..<maxSwipes {
                if isComfortablyVisible() { return }
                dragDownStart.press(forDuration: 0.02, thenDragTo: dragDownEnd)
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
    }

    private func performEdgeSwipeBack(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.02, thenDragTo: end)
    }

    private func performSwipeCloseDrawer(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        start.press(forDuration: 0.02, thenDragTo: end)
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !element.exists
    }

    private func waitForTextContaining(_ substring: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        return app.descendants(matching: .any).containing(predicate).firstMatch.waitForExistence(timeout: timeout)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
