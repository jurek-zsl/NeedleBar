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
}
