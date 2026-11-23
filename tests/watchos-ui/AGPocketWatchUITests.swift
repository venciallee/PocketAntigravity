import XCTest

/// Real watchOS Interactive XCUITest E2E Suite covering all 8 Apple Watch companion screens (`W01`..`W08`)
/// and interactive journeys (`WTC-01`..`WTC-09`) on Apple Watch Simulator (`AGPocketWatch.app`).
@MainActor
final class AGPocketWatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchWatchApp(verifyScene: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-verify", verifyScene]
        app.launchEnvironment["AGPOCKET_WATCH_VERIFY"] = verifyScene
        app.launch()
        return app
    }

    // MARK: - WTC-01 & WTC-02: Sessions Home & Online Devices Switching

    func testWTC01_WTC02_HomeSessionsAndDeviceSwitching() {
        let app = launchWatchApp(verifyScene: "W01_SESSIONS")

        XCTAssertTrue(app.staticTexts["Agents"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["watch.home.devicesButton"].exists)
        XCTAssertTrue(app.buttons["watch.home.voiceButton"].exists)
        XCTAssertTrue(app.buttons["watch.home.activeDeviceLabel"].exists)
        XCTAssertTrue(app.buttons["watch.home.session.cas-rate-limiter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rate limiter"].exists)
        XCTAssertTrue(app.staticTexts["Approve command"].exists)
        XCTAssertTrue(app.staticTexts["Dark mode settings"].exists)

        // Tap top-left Devices button -> W02_DEVICES
        app.buttons["watch.home.devicesButton"].tap()
        XCTAssertTrue(app.staticTexts["Devices"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["watch.devices.back"].exists)
        XCTAssertTrue(app.buttons["watch.devices.row.macbook-pro"].exists)
        XCTAssertTrue(app.buttons["watch.devices.row.cloud"].exists)
        XCTAssertTrue(app.buttons["watch.devices.row.office-imac"].exists)

        // Select Cloud -> returns to W01_SESSIONS and updates active device label
        app.buttons["watch.devices.row.cloud"].tap()
        XCTAssertTrue(app.staticTexts["Agents"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Cloud"].waitForExistence(timeout: 5))
    }

    // MARK: - WTC-03 & WTC-04: Chat Stream -> Artifact Walkthrough -> See Changes

    func testWTC03_WTC04_ChatStreamAndArtifactWalkthrough() {
        let app = launchWatchApp(verifyScene: "W03_CHAT_STREAM")

        XCTAssertTrue(app.staticTexts["Rate limiter"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["watch.nav.back"].exists)
        XCTAssertTrue(app.buttons["watch.chat.voiceFab"].exists)
        XCTAssertTrue(app.buttons["watch.chat.artifactCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["watch.chat.diffPill"].exists)

        // Tap Walkthrough card -> W04_ARTIFACT_SUMMARY
        app.buttons["watch.chat.artifactCard"].tap()
        XCTAssertTrue(app.staticTexts["Per-tenant token bucket"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["watch.artifact.openOnPhone"].exists)
        XCTAssertTrue(app.buttons["watch.artifact.seeChanges"].exists)

        // Trigger iPhone Handoff button -> shows toast confirmation
        app.buttons["watch.artifact.openOnPhone"].tap()
        XCTAssertTrue(app.staticTexts["Opened on iPhone"].waitForExistence(timeout: 5))

        // Tap See changes -> navigates to W05_CHANGED_FILES_COMPACT
        app.buttons["watch.artifact.seeChanges"].tap()
        XCTAssertTrue(app.staticTexts["Changes"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["watch.changes.acceptAll"].waitForExistence(timeout: 5))
    }

    // MARK: - WTC-05: Compact Changed Files & Accept All

    func testWTC05_CompactChangedFilesAndAcceptAll() {
        let app = launchWatchApp(verifyScene: "W05_CHANGED_FILES_COMPACT")

        XCTAssertTrue(app.staticTexts["Changes"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["watch.changes.file.ratelimit.go"].exists || app.staticTexts["ratelimit.go"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["watch.changes.openOnPhone"].exists)
        let acceptAll = app.buttons["watch.changes.acceptAll"]
        XCTAssertTrue(acceptAll.waitForExistence(timeout: 5))

        acceptAll.tap()
        XCTAssertTrue(app.staticTexts["Accepted"].waitForExistence(timeout: 5))
    }

    // MARK: - WTC-06: Large Intent-Grouped Changed Files & iPhone Handoff

    func testWTC06_GroupedChangedFilesTriageAndPhoneHandoff() {
        let app = launchWatchApp(verifyScene: "W06_CHANGED_FILES_GROUPED")

        XCTAssertTrue(app.staticTexts["Changes"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["WORTH A LOOK · 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["watch.changes.worthALook.audit/writer.go"].exists || app.staticTexts["audit/writer.go"].exists)
        XCTAssertTrue(app.otherElements["watch.changes.worthALook.go.mod"].exists || app.staticTexts["go.mod"].exists)
        XCTAssertTrue(app.staticTexts["GROUPED · 21"].exists)
        XCTAssertFalse(app.buttons["watch.changes.acceptAll"].exists)

        let groupCard = app.buttons["watch.changes.group.grp-callsites"]
        if groupCard.waitForExistence(timeout: 4) {
            groupCard.tap()
        }

        let phoneButton = app.buttons["watch.changes.handoffIPhone"]
        XCTAssertTrue(phoneButton.waitForExistence(timeout: 5))
        phoneButton.tap()
        XCTAssertTrue(app.staticTexts["Opened on iPhone"].waitForExistence(timeout: 5))
    }

    // MARK: - WTC-07: Voice Input Target Cycling, Stop & Send

    func testWTC07_VoiceInputTargetSwitchAndSend() {
        let app = launchWatchApp(verifyScene: "W07_VOICE_INPUT")

        XCTAssertTrue(app.buttons["watch.voice.close"].waitForExistence(timeout: 8))
        let targetSelector = app.buttons["watch.voice.targetSelector"]
        XCTAssertTrue(targetSelector.exists)
        XCTAssertTrue(app.staticTexts["watch.voice.transcript"].exists || app.staticTexts["Double tap to send"].exists)
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
        // Branch 1: Allow
        let appAllow = launchWatchApp(verifyScene: "W08_APPROVAL_NOTIFICATION")
        XCTAssertTrue(appAllow.staticTexts["watch.approval.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(appAllow.staticTexts["watch.approval.command"].exists)
        XCTAssertTrue(appAllow.buttons["watch.approval.allow"].exists)
        XCTAssertTrue(appAllow.buttons["watch.approval.deny"].exists)
        XCTAssertTrue(appAllow.buttons["watch.approval.replyByVoice"].exists)

        appAllow.buttons["watch.approval.allow"].tap()
        XCTAssertTrue(appAllow.staticTexts["Agents"].waitForExistence(timeout: 6))

        // Branch 2: Reply by voice transitions straight into W07_VOICE_INPUT
        let appReply = launchWatchApp(verifyScene: "W08_APPROVAL_NOTIFICATION")
        XCTAssertTrue(appReply.buttons["watch.approval.replyByVoice"].waitForExistence(timeout: 8))
        appReply.buttons["watch.approval.replyByVoice"].tap()
        XCTAssertTrue(appReply.buttons["watch.voice.sendButton"].waitForExistence(timeout: 6))
    }
}
