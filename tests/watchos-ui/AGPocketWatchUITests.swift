import XCTest

/// Real watchOS Interactive XCUITest E2E Suite covering all 8 Apple Watch companion screens (`W01`..`W08`),
/// interactive journeys (`WTC-01`..`WTC-09`), wrist-unlock approval gating (`WTC-13`),
/// and top-right Voice New Task dispatch (`WTC-14`) on Apple Watch Simulator (`AGPocketWatch.app`).
@MainActor
final class AGPocketWatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchWatchApp(verifyScene: String, wristLocked: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["--watch-verify", verifyScene]
        if wristLocked {
            args.append("--watch-wrist-locked")
            app.launchEnvironment["AGPOCKET_WATCH_WRIST_LOCKED"] = "1"
        }
        app.launchArguments = args
        app.launchEnvironment["AGPOCKET_WATCH_VERIFY"] = verifyScene
        app.launch()
        return app
    }

    private func waitForTextAnywhere(
        _ substring: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", substring)
        return app.descendants(matching: .any).matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }

    private func ensureVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4,
        timeout: TimeInterval = 4
    ) -> Bool {
        if element.waitForExistence(timeout: timeout) && element.isHittable {
            return true
        }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.exists && element.isHittable {
                return true
            }
        }
        return element.waitForExistence(timeout: 2)
    }

    private func tapScrollingIfNeeded(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            ensureVisible(element, in: app, maxSwipes: maxSwipes),
            "Expected element \(element) to become visible",
            file: file,
            line: line
        )
        element.tap()
    }

    // MARK: - WTC-01 & WTC-02: Sessions Home & Online Devices Switching

    func testWTC01_WTC02_HomeSessionsAndDeviceSwitching() {
        let app = launchWatchApp(verifyScene: "W01_SESSIONS")

        XCTAssertTrue(app.staticTexts["Agents"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["watch.home.devicesButton"].exists)
        XCTAssertTrue(app.buttons["watch.home.voiceButton"].exists)
        let activeDeviceBtn = app.buttons["watch.home.activeDeviceLabel"]
        XCTAssertTrue(activeDeviceBtn.exists)

        let rateLimiterBtn = app.buttons["watch.home.session.cas-rate-limiter"]
        XCTAssertTrue(rateLimiterBtn.waitForExistence(timeout: 5))
        XCTAssertTrue(rateLimiterBtn.label.localizedCaseInsensitiveContains("Rate limiter"))
        XCTAssertTrue(rateLimiterBtn.label.localizedCaseInsensitiveContains("Approve command"))
        XCTAssertTrue(waitForTextAnywhere("Dark mode settings", in: app, timeout: 4))

        // Tap top-left Devices button -> W02_DEVICES
        app.buttons["watch.home.devicesButton"].tap()
        XCTAssertTrue(app.staticTexts["Devices"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["watch.devices.back"].exists)
        XCTAssertTrue(app.buttons["watch.devices.row.macbook-pro"].exists)
        XCTAssertTrue(app.buttons["watch.devices.row.cloud"].exists)
        XCTAssertTrue(app.buttons["watch.devices.row.office-imac"].exists)

        // Select Cloud -> returns to W01_SESSIONS and updates active device label
        tapScrollingIfNeeded(app.buttons["watch.devices.row.cloud"], in: app)
        XCTAssertTrue(app.staticTexts["Agents"].waitForExistence(timeout: 6))
        XCTAssertTrue(waitForTextAnywhere("Cloud", in: app, timeout: 5))
    }

    // MARK: - WTC-03 & WTC-04: Chat Stream -> Artifact Walkthrough -> See Changes

    func testWTC03_WTC04_ChatStreamAndArtifactWalkthrough() {
        let app = launchWatchApp(verifyScene: "W03_CHAT_STREAM")

        XCTAssertTrue(app.staticTexts["Rate limiter"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["watch.nav.back"].exists)
        XCTAssertTrue(app.buttons["watch.chat.voiceFab"].exists)

        let artifactCard = app.buttons["watch.chat.artifactCard"]
        XCTAssertTrue(ensureVisible(artifactCard, in: app, maxSwipes: 4))
        XCTAssertTrue(ensureVisible(app.buttons["watch.chat.diffPill"], in: app, maxSwipes: 2))

        // Tap Walkthrough card -> W04_ARTIFACT_SUMMARY (<= 3 key points + single primary CTA)
        tapScrollingIfNeeded(artifactCard, in: app)
        XCTAssertTrue(app.staticTexts["Per-tenant token bucket"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["watch.artifact.openOnPhone"].exists)
        XCTAssertTrue(app.buttons["watch.artifact.seeChanges"].exists)

        // Trigger iPhone Handoff button -> shows toast confirmation
        app.buttons["watch.artifact.openOnPhone"].tap()
        XCTAssertTrue(
            app.staticTexts["watch.toast.banner"].waitForExistence(timeout: 5)
                || waitForTextAnywhere("Opened on iPhone", in: app, timeout: 5)
        )

        // Tap See changes -> navigates to W05_CHANGED_FILES_COMPACT
        app.buttons["watch.artifact.seeChanges"].tap()
        XCTAssertTrue(app.staticTexts["Changes"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["watch.changes.acceptAll"].waitForExistence(timeout: 5))
    }

    // MARK: - WTC-05: Compact Changed Files (<= 5 files, zero risk items) & Accept All

    func testWTC05_CompactChangedFilesAndAcceptAll() {
        let app = launchWatchApp(verifyScene: "W05_CHANGED_FILES_COMPACT")

        XCTAssertTrue(app.staticTexts["Changes"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.otherElements["watch.changes.file.ratelimit.go"].exists
                || waitForTextAnywhere("ratelimit.go", in: app, timeout: 5)
        )
        XCTAssertTrue(app.buttons["watch.changes.openOnPhone"].exists)
        let acceptAll = app.buttons["watch.changes.acceptAll"]
        XCTAssertTrue(acceptAll.waitForExistence(timeout: 5))

        acceptAll.tap()
        XCTAssertTrue(waitForTextAnywhere("Accepted", in: app, timeout: 5))
    }

    // MARK: - WTC-06: Large / Risky Intent-Grouped Changed Files & iPhone Handoff

    func testWTC06_GroupedChangedFilesTriageAndPhoneHandoff() {
        let app = launchWatchApp(verifyScene: "W06_CHANGED_FILES_GROUPED")

        XCTAssertTrue(app.staticTexts["Changes"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["WORTH A LOOK · 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.otherElements["watch.changes.worthALook.audit/writer.go"].exists
                || waitForTextAnywhere("audit/writer.go", in: app, timeout: 4)
        )
        XCTAssertTrue(
            app.otherElements["watch.changes.worthALook.go.mod"].exists
                || waitForTextAnywhere("go.mod", in: app, timeout: 4)
        )
        XCTAssertFalse(app.buttons["watch.changes.acceptAll"].exists)

        let groupCard = app.buttons["watch.changes.group.grp-callsites"]
        if ensureVisible(groupCard, in: app, maxSwipes: 3, timeout: 3) {
            XCTAssertTrue(app.staticTexts["GROUPED · 21"].exists || waitForTextAnywhere("GROUPED", in: app, timeout: 3))
            groupCard.tap()
        }

        let phoneButton = app.buttons["watch.changes.handoffIPhone"]
        XCTAssertTrue(phoneButton.waitForExistence(timeout: 5))
        phoneButton.tap()
        XCTAssertTrue(
            app.staticTexts["watch.toast.banner"].waitForExistence(timeout: 5)
                || waitForTextAnywhere("Opened on iPhone", in: app, timeout: 5)
        )
    }

    // MARK: - WTC-07: Voice Input Target Cycling, Stop & Send

    func testWTC07_VoiceInputTargetSwitchAndSend() {
        let app = launchWatchApp(verifyScene: "W07_VOICE_INPUT")

        XCTAssertTrue(app.buttons["watch.voice.close"].waitForExistence(timeout: 8))
        let targetSelector = app.buttons["watch.voice.targetSelector"]
        XCTAssertTrue(targetSelector.exists)
        XCTAssertTrue(
            app.staticTexts["watch.voice.transcript"].exists
                || app.staticTexts["Double tap to send"].exists
        )
        XCTAssertTrue(app.buttons["watch.voice.stopButton"].exists)
        let sendButton = app.buttons["watch.voice.sendButton"]
        XCTAssertTrue(sendButton.exists)

        // Cycle target session & send
        targetSelector.tap()
        app.buttons["watch.voice.stopButton"].tap()
        sendButton.tap()

        XCTAssertTrue(app.staticTexts["Agents"].waitForExistence(timeout: 6))
    }

    // MARK: - WTC-08 & WTC-09: Approval Notification Allow / Deny / Reply by Voice

    func testWTC08_WTC09_ApprovalNotificationAllowDenyAndReplyByVoice() {
        // Branch 1: Allow (Watch unlocked on wrist)
        let appAllow = launchWatchApp(verifyScene: "W08_APPROVAL_NOTIFICATION")
        XCTAssertTrue(appAllow.staticTexts["watch.approval.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(appAllow.staticTexts["watch.approval.command"].exists)
        XCTAssertTrue(appAllow.buttons["watch.approval.deny"].exists)
        tapScrollingIfNeeded(appAllow.buttons["watch.approval.allow"], in: appAllow)
        XCTAssertTrue(appAllow.staticTexts["Agents"].waitForExistence(timeout: 6))

        // Branch 2: Reply by voice transitions straight into W07_VOICE_INPUT
        let appReply = launchWatchApp(verifyScene: "W08_APPROVAL_NOTIFICATION")
        XCTAssertTrue(appReply.staticTexts["watch.approval.title"].waitForExistence(timeout: 8))
        tapScrollingIfNeeded(appReply.buttons["watch.approval.replyByVoice"], in: appReply)
        XCTAssertTrue(appReply.buttons["watch.voice.sendButton"].waitForExistence(timeout: 6))
    }

    // MARK: - WTC-13: Locked / Off-Wrist Apple Watch Blocks Approval Actions

    func testWTC13_WristLockedBlocksApprovals() {
        // 1. Approval notification Allow is blocked when Watch is locked or off-wrist
        let appLockedApproval = launchWatchApp(verifyScene: "W08_APPROVAL_NOTIFICATION", wristLocked: true)
        XCTAssertTrue(appLockedApproval.staticTexts["watch.approval.title"].waitForExistence(timeout: 8))
        tapScrollingIfNeeded(appLockedApproval.buttons["watch.approval.allow"], in: appLockedApproval)
        XCTAssertTrue(waitForTextAnywhere("Unlock Watch on wrist to approve", in: appLockedApproval, timeout: 5))
        // Pending approval sheet stays open (not dismissed!)
        XCTAssertTrue(appLockedApproval.buttons["watch.approval.allow"].exists)

        // 2. Compact changes Accept all is also blocked when Watch is locked or off-wrist
        let appLockedChanges = launchWatchApp(verifyScene: "W05_CHANGED_FILES_COMPACT", wristLocked: true)
        let acceptAll = appLockedChanges.buttons["watch.changes.acceptAll"]
        XCTAssertTrue(acceptAll.waitForExistence(timeout: 8))
        acceptAll.tap()
        XCTAssertTrue(waitForTextAnywhere("Unlock Watch on wrist to approve", in: appLockedChanges, timeout: 5))
        XCTAssertFalse(acceptAll.label.localizedCaseInsensitiveContains("Accepted"))
    }

    // MARK: - WTC-14: Top-Right Mic Button Creates New Voice Task

    func testWTC14_HomeTopRightVoiceCreatesNewTask() {
        let app = launchWatchApp(verifyScene: "W01_SESSIONS")
        XCTAssertTrue(app.buttons["watch.home.voiceButton"].waitForExistence(timeout: 8))

        // Top-right mic opens Voice Input targeting "To: New task"
        app.buttons["watch.home.voiceButton"].tap()
        let targetSelector = app.buttons["watch.voice.targetSelector"]
        XCTAssertTrue(targetSelector.waitForExistence(timeout: 6))
        XCTAssertTrue(
            targetSelector.label.localizedCaseInsensitiveContains("New task")
                || waitForTextAnywhere("New task", in: app, timeout: 5)
        )

        app.buttons["watch.voice.sendButton"].tap()
        XCTAssertTrue(app.staticTexts["Agents"].waitForExistence(timeout: 6))
        XCTAssertTrue(waitForTextAnywhere("Fix flaky webhook retries", in: app, timeout: 5))
    }
}
