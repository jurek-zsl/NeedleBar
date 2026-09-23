import XCTest
@testable import NeedleBarCore

@MainActor
final class EndToEndPipelineTests: XCTestCase {
    var mockClient: MockNeedleClient!
    var mockWorkspace: MockWorkspaceService!
    var mockFileSystem: MockFileSystemService!
    var mockProductivity: MockProductivityService!
    var mockSystemInfo: MockSystemInfoService!
    var mockNotes: MockNotesService!
    var historyStore: CommandHistoryStore!
    var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockNeedleClient()
        mockWorkspace = MockWorkspaceService()
        mockFileSystem = MockFileSystemService()
        mockProductivity = MockProductivityService()
        mockSystemInfo = MockSystemInfoService()
        mockNotes = MockNotesService()

        let tmpHistoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_history_\(UUID().uuidString).json")
        historyStore = CommandHistoryStore(storageURL: tmpHistoryURL)

        let registry = ToolRegistry.createDefaultRegistry(
            workspaceService: mockWorkspace,
            fileService: mockFileSystem,
            productivityService: mockProductivity,
            systemInfoService: mockSystemInfo,
            notesService: mockNotes,
            historySearch: { [historyStore] q in historyStore!.search(query: q) }
        )

        appState = AppState(
            needleClient: mockClient,
            toolRegistry: registry,
            historyStore: historyStore
        )
    }

    func testSafeCommandEndToEndExecution() async {
        await appState.submitCommand("Open Safari")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)
        XCTAssertEqual(mockWorkspace.openedApps, ["Safari"])

        // Check history
        let history = appState.recentHistory
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.query, "Open Safari")
        XCTAssertEqual(history.first?.toolNames, ["open_application"])
        XCTAssertEqual(history.first?.success, true)
    }

    func testMultipleToolCallsEndToEnd() async {
        await appState.submitCommand("Open Xcode and Terminal")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)
        XCTAssertEqual(mockWorkspace.openedApps, ["Xcode", "Terminal"])

        let plan = appState.currentPlan
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].status, .succeeded)
        XCTAssertEqual(plan?.steps[1].status, .succeeded)
    }

    func testConfirmationGateAndExecution() async {
        let tmp = FileManager.default.temporaryDirectory
        let src = tmp.appendingPathComponent("screenshot_\(UUID().uuidString).png")
        let dst = tmp.appendingPathComponent("Screenshots")
        try? "data".write(to: src, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: src) }

        await mockClient.setCustomResponse(
            for: "move screenshots from downloads into a screenshots folder",
            response: NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "move_file", arguments: [
                        "source": AnyCodable(src.path),
                        "destination": AnyCodable(dst.path)
                    ])
                ],
                confidence: 0.95
            )
        )

        // "Move screenshots..." requires confirmation
        await appState.submitCommand("Move screenshots from Downloads into a Screenshots folder")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNotNil(appState.confirmationPlan, "Plan must be paused awaiting confirmation")
        XCTAssertNil(appState.activeResult, "Actions must not run prior to confirmation")
        XCTAssertEqual(mockFileSystem.movedFiles.count, 0)

        // User confirms
        await appState.confirmPlan()

        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)
        XCTAssertEqual(mockFileSystem.movedFiles.count, 1)
    }

    func testCancellationOfConfirmatoryPlan() async {
        await appState.submitCommand("Move screenshots from Downloads into a Screenshots folder")
        XCTAssertNotNil(appState.confirmationPlan)

        // User cancels
        appState.cancelPlan()

        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNil(appState.activeResult)
        XCTAssertEqual(mockFileSystem.movedFiles.count, 0)

        let record = appState.recentHistory.first
        XCTAssertEqual(record?.success, false)
        XCTAssertTrue(record?.summary.contains("cancelled") == true)
    }

    func testUnsupportedQueryHandling() async {
        await appState.submitCommand("What is the meaning of life?")

        XCTAssertNotNil(appState.errorMessage)
        XCTAssertTrue(appState.errorMessage?.contains("cannot perform this request") == true)
        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNil(appState.activeResult)
    }

    func testStartTimerCommandExtractsFiveMinutesAndExecutes() async {
        await appState.submitCommand("start timer 5 min")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNil(appState.confirmationPlan, "Timer is safe action, should execute automatically")
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)
        XCTAssertEqual(mockProductivity.startedTimers.count, 1)
        XCTAssertEqual(mockProductivity.startedTimers.first?.durationSeconds, 300)

        // Ensure it did NOT create a reminder
        XCTAssertEqual(mockProductivity.createdReminders.count, 0)

        // Check history
        let record = appState.recentHistory.first
        XCTAssertEqual(record?.toolNames, ["start_timer"])
        XCTAssertTrue(record?.summary.contains("5-minute timer") == true)
    }

    func testStartTimerCommandPreservesSeconds() async {
        await appState.submitCommand("start timer 30 seconds")

        XCTAssertNil(appState.errorMessage)
        XCTAssertEqual(mockProductivity.startedTimers.first?.durationSeconds, 30)
        XCTAssertTrue(appState.activeResult?.summary.contains("30-second timer") == true)
    }

    func testCreateReminderCommandEndToEnd() async {
        await appState.submitCommand("remind me to buy groceries")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNotNil(appState.confirmationPlan, "Reminder creates persistent data, requires confirmation")

        await appState.confirmPlan()
        XCTAssertEqual(mockProductivity.createdReminders.count, 1)
        XCTAssertEqual(mockProductivity.startedTimers.count, 0)
    }

    func testChainedCommandWithAfterExecutesInCorrectOrder() async {
        await appState.submitCommand("start timer 5 min after opening Safari")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)

        // Verifies Safari was opened first, then timer started
        XCTAssertEqual(mockWorkspace.openedApps, ["Safari"])
        XCTAssertEqual(mockProductivity.startedTimers.count, 1)
        XCTAssertEqual(mockProductivity.startedTimers.first?.durationSeconds, 300)

        let steps = appState.currentPlan?.steps ?? []
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].toolCall.name, "open_application")
        XCTAssertEqual(steps[1].toolCall.name, "start_timer")
    }

    func testChainedCommandWithAndThenExecutesInOrder() async {
        await appState.submitCommand("open Safari and then start timer 5 min")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)

        XCTAssertEqual(mockWorkspace.openedApps, ["Safari"])
        XCTAssertEqual(mockProductivity.startedTimers.count, 1)

        let steps = appState.currentPlan?.steps ?? []
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].toolCall.name, "open_application")
        XCTAssertEqual(steps[1].toolCall.name, "start_timer")
    }

    func testLowConfidencePresentsConfirmationPlanInsteadOfDropping() async {
        let lowConfClient = MockNeedleClient(simulatedConfidence: 0.40) // Low confidence below 0.50
        let lowConfAppState = AppState(
            needleClient: lowConfClient,
            toolRegistry: appState.toolRegistry,
            historyStore: appState.historyStore,
            preferencesStore: appState.preferencesStore,
            permissionManager: appState.permissionManager
        )

        await lowConfAppState.submitCommand("open Safari")

        // Should NOT throw an unhandled error or drop the command
        XCTAssertNil(lowConfAppState.errorMessage)
        // Should require confirmation because of low confidence
        XCTAssertNotNil(lowConfAppState.confirmationPlan)
        XCTAssertEqual(lowConfAppState.confirmationPlan?.steps.count, 1)
        XCTAssertEqual(lowConfAppState.confirmationPlan?.steps.first?.toolCall.name, "open_application")

        // Confirming should execute the plan
        await lowConfAppState.confirmPlan()
        XCTAssertEqual(mockWorkspace.openedApps, ["Safari"])
    }

    func testFastPathOpenURL() async {
        await appState.submitCommand("open google.com")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)
        XCTAssertEqual(mockWorkspace.openedURLs.count, 1)
        XCTAssertEqual(mockWorkspace.openedURLs.first?.absoluteString, "https://google.com")
    }

    func testFastPathOpenURLWithBrowserName() async {
        await appState.submitCommand("open youtube.com in Safari")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)
        XCTAssertEqual(mockWorkspace.openedURLs.count, 1)
        XCTAssertEqual(mockWorkspace.openedURLs.first?.absoluteString, "https://youtube.com")
    }

    func testFastPathOpenFolder() async {
        await appState.submitCommand("open downloads")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)
        XCTAssertEqual(mockWorkspace.openedFolders.count, 1)
        XCTAssertTrue(mockWorkspace.openedFolders.first?.path.contains("Downloads") == true)
    }

    func testFastPathBatteryStatus() async {
        await appState.submitCommand("what is my battery status")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)
        XCTAssertTrue(appState.activeResult?.summary.contains("Battery") == true)
    }

    func testHealedCommandExecutionEndToEnd() async {
        // Simulate engine returning open_application("apple.com")
        await mockClient.setCustomResponse(
            for: "browse apple.com",
            response: NeedleResponse(
                type: "call",
                success: true,
                functionCalls: [
                    ToolCall(name: "open_application", arguments: ["name": AnyCodable("apple.com")])
                ],
                confidence: 0.90
            )
        )

        await appState.submitCommand("browse apple.com")

        XCTAssertNil(appState.errorMessage)
        XCTAssertNil(appState.confirmationPlan)
        XCTAssertNotNil(appState.activeResult)
        XCTAssertTrue(appState.activeResult?.success == true)
        // Should have healed to open_url
        XCTAssertEqual(mockWorkspace.openedURLs.count, 1)
        XCTAssertEqual(mockWorkspace.openedURLs.first?.absoluteString, "https://apple.com")
    }
}
