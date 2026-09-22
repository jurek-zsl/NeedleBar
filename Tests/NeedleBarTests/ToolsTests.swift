import XCTest
@testable import NeedleBarCore

final class ToolsTests: XCTestCase {
    var workspace: MockWorkspaceService!
    var fileSystem: MockFileSystemService!
    var productivity: MockProductivityService!
    var systemInfo: MockSystemInfoService!
    var notes: MockNotesService!

    override func setUp() {
        super.setUp()
        workspace = MockWorkspaceService()
        fileSystem = MockFileSystemService()
        productivity = MockProductivityService()
        systemInfo = MockSystemInfoService()
        notes = MockNotesService()
    }

    // MARK: - App Tools

    func testOpenApplicationTool() async throws {
        let tool = OpenApplicationTool(workspaceService: workspace)
        let result = try await tool.execute(arguments: ["name": AnyCodable("Safari")])
        XCTAssertTrue(result.success)
        XCTAssertEqual(workspace.openedApps, ["Safari"])

        // Test missing argument
        let badResult = try await tool.execute(arguments: [:])
        XCTAssertFalse(badResult.success)
    }

    func testQuitApplicationTool() async throws {
        let tool = QuitApplicationTool(workspaceService: workspace)
        let result = try await tool.execute(arguments: ["name": AnyCodable("Slack")])
        XCTAssertTrue(result.success)
        XCTAssertEqual(workspace.quitApps, ["Slack"])
        XCTAssertEqual(tool.riskLevel, .requiresConfirmation)
    }

    func testOpenURLTool() async throws {
        let tool = OpenURLTool(workspaceService: workspace)
        let result = try await tool.execute(arguments: ["url": AnyCodable("apple.com")])
        XCTAssertTrue(result.success)
        XCTAssertEqual(workspace.openedURLs.first?.absoluteString, "https://apple.com")
    }

    func testOpenFolderTool() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let tool = OpenFolderTool(workspaceService: workspace)
        let result = try await tool.execute(arguments: ["path": AnyCodable(tmp.path)])
        XCTAssertTrue(result.success)
        XCTAssertEqual(workspace.openedFolders.first?.standardizedFileURL.path, tmp.standardizedFileURL.path)
    }

    // MARK: - File Tools

    func testSearchFilesTool() async throws {
        let tmp = FileManager.default.temporaryDirectory
        fileSystem.existingFiles = [tmp.path + "/invoice_march.pdf", tmp.path + "/photo.png"]
        let tool = SearchFilesTool(fileService: fileSystem)

        let result = try await tool.execute(arguments: [
            "query": AnyCodable("invoice"),
            "directory": AnyCodable(tmp.path)
        ])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("Found 1 file(s)"))
    }

    func testListRecentFilesTool() async throws {
        let tmp = FileManager.default.temporaryDirectory
        fileSystem.existingFiles = [tmp.path + "/doc1.txt", tmp.path + "/doc2.txt"]
        let tool = ListRecentFilesTool(fileService: fileSystem)

        let result = try await tool.execute(arguments: [
            "directory": AnyCodable(tmp.path),
            "limit": AnyCodable(5)
        ])
        XCTAssertTrue(result.success)
    }

    func testCreateFolderTool() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let target = tmp.appendingPathComponent("NewSubfolder_\(UUID().uuidString)")
        let tool = CreateFolderTool(fileService: fileSystem)

        let result = try await tool.execute(arguments: ["path": AnyCodable(target.path)])
        XCTAssertTrue(result.success)
        XCTAssertTrue(fileSystem.createdFolders.contains(target.standardizedFileURL))
    }

    func testMoveFileTool() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let src = tmp.appendingPathComponent("src_\(UUID().uuidString).txt")
        let dst = tmp.appendingPathComponent("dst_\(UUID().uuidString).txt")
        try "content".write(to: src, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: src) }

        let tool = MoveFileTool(fileService: fileSystem)
        let result = try await tool.execute(arguments: [
            "source": AnyCodable(src.path),
            "destination": AnyCodable(dst.path)
        ])
        XCTAssertTrue(result.success)
        XCTAssertEqual(fileSystem.movedFiles.count, 1)
        XCTAssertEqual(tool.riskLevel, .requiresConfirmation)
    }

    func testRenameFileTool() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let src = tmp.appendingPathComponent("orig_\(UUID().uuidString).txt")
        try "content".write(to: src, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: src) }

        let tool = RenameFileTool(fileService: fileSystem)
        let result = try await tool.execute(arguments: [
            "path": AnyCodable(src.path),
            "new_name": AnyCodable("renamed.txt")
        ])
        XCTAssertTrue(result.success)
        XCTAssertEqual(fileSystem.renamedFiles.count, 1)
    }

    // MARK: - Productivity Tools

    func testStartTimerTool() async throws {
        let tool = StartTimerTool(productivityService: productivity)
        let result = try await tool.execute(arguments: [
            "minutes": AnyCodable(25),
            "label": AnyCodable("Focus session")
        ])
        XCTAssertTrue(result.success)
        XCTAssertEqual(productivity.startedTimers.first?.minutes, 25)
        XCTAssertEqual(productivity.startedTimers.first?.label, "Focus session")

        // Test invalid minutes
        let badResult = try await tool.execute(arguments: ["minutes": AnyCodable(-5)])
        XCTAssertFalse(badResult.success)
    }

    func testCreateReminderTool() async throws {
        let tool = CreateReminderTool(productivityService: productivity)
        let result = try await tool.execute(arguments: [
            "title": AnyCodable("Call Alex"),
            "due_date": AnyCodable("tomorrow")
        ])
        XCTAssertTrue(result.success)
        XCTAssertEqual(productivity.createdReminders.first?.title, "Call Alex")
        XCTAssertNotNil(productivity.createdReminders.first?.dueDate)
        XCTAssertEqual(tool.riskLevel, .requiresConfirmation)
    }

    func testCreateCalendarEventTool() async throws {
        let tool = CreateCalendarEventTool(productivityService: productivity)
        let result = try await tool.execute(arguments: [
            "title": AnyCodable("Sprint Planning"),
            "start": AnyCodable("tomorrow 10:00"),
            "location": AnyCodable("Room A")
        ])
        XCTAssertTrue(result.success)
        XCTAssertEqual(productivity.createdEvents.first?.title, "Sprint Planning")
        XCTAssertEqual(productivity.createdEvents.first?.location, "Room A")
    }

    // MARK: - System Tools

    func testGetBatteryStatusTool() async throws {
        let tool = GetBatteryStatusTool(systemInfoService: systemInfo)
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("88%"))
    }

    func testGetFrontmostApplicationTool() async throws {
        let tool = GetFrontmostApplicationTool(workspaceService: workspace)
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("Safari"))
    }

    func testGetSystemSummaryTool() async throws {
        let tool = GetSystemSummaryTool(systemInfoService: systemInfo)
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("macOS 15.0"))
        XCTAssertTrue(result.message.contains("32.0 GB RAM"))
    }

    // MARK: - Search Tools

    func testSearchNotesTool() async throws {
        notes.notesToReturn = ["Deployment Checklist", "Grocery List"]
        let tool = SearchNotesTool(notesService: notes)
        let result = try await tool.execute(arguments: ["query": AnyCodable("Deployment")])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("Found 1 note(s)"))
    }

    func testSearchCommandHistoryTool() async throws {
        let tool = SearchCommandHistoryTool { _ in
            [
                HistoryRecord(
                    query: "Open Safari",
                    toolNames: ["open_application"],
                    success: true,
                    summary: "Opened Safari",
                    confidence: 1.0,
                    riskLevel: .safe
                )
            ]
        }
        let result = try await tool.execute(arguments: ["query": AnyCodable("Safari")])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("Found 1 past command(s)"))
    }
}
