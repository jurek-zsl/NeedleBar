import XCTest
@testable import NeedleBarCore

final class ExtendedToolsTests: XCTestCase {

    // MARK: - Category 1: System Controls

    func testRunShortcutToolDefinitionAndValidation() async throws {
        let tool = RunShortcutTool()
        XCTAssertEqual(tool.definition.name, "run_shortcut")
        XCTAssertEqual(tool.riskLevel, .requiresConfirmation)

        // Missing argument should fail gracefully
        let missingArgResult = try await tool.execute(arguments: [:])
        XCTAssertFalse(missingArgResult.success)
        XCTAssertTrue(missingArgResult.error?.contains("name") == true)
    }

    func testMediaControlToolDefinition() async throws {
        let tool = MediaControlTool()
        XCTAssertEqual(tool.definition.name, "media_control")
        XCTAssertEqual(tool.riskLevel, .safe)
        XCTAssertTrue(tool.definition.triggers?.contains { $0.contains("pause") } == true)
    }

    func testSetVolumeToolValidation() async throws {
        let tool = SetVolumeTool()
        XCTAssertEqual(tool.definition.name, "set_volume")
        XCTAssertEqual(tool.riskLevel, .safe)

        // Missing both level and mute
        let noArgs = try await tool.execute(arguments: [:])
        XCTAssertFalse(noArgs.success)
    }

    func testWindowManagementToolDefinition() async throws {
        let tool = WindowManagementTool()
        XCTAssertEqual(tool.definition.name, "manage_window")
        XCTAssertEqual(tool.riskLevel, .safe)
        XCTAssertTrue(tool.definition.parameters.properties.keys.contains("action"))
    }

    func testSystemToggleTools() async throws {
        let darkMode = ToggleDarkModeTool()
        XCTAssertEqual(darkMode.definition.name, "toggle_dark_mode")
        XCTAssertEqual(darkMode.riskLevel, .safe)

        let lockScreen = LockScreenTool()
        XCTAssertEqual(lockScreen.definition.name, "lock_screen")
        XCTAssertEqual(lockScreen.riskLevel, .safe)

        let emptyTrash = EmptyTrashTool()
        XCTAssertEqual(emptyTrash.definition.name, "empty_trash")
        XCTAssertEqual(emptyTrash.riskLevel, .destructive)

        let dnd = ToggleDNDTool()
        XCTAssertEqual(dnd.definition.name, "toggle_dnd")
        XCTAssertEqual(dnd.riskLevel, .safe)
    }

    func testClipboardServiceAndTools() async throws {
        let service = ClipboardService(maxItems: 10, monitorSystemPasteboard: false)
        await service.record(text: "Hello NeedleBar")
        await service.record(text: "Second item")

        let recent = await service.getRecent(limit: 5)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].content, "Second item")
        XCTAssertEqual(recent[1].content, "Hello NeedleBar")

        // Test GetClipboardHistoryTool
        let getTool = GetClipboardHistoryTool(clipboardService: service)
        let getRes = try await getTool.execute(arguments: ["limit": AnyCodable(5)])
        XCTAssertTrue(getRes.success)
        XCTAssertTrue(getRes.message.contains("Second item"))

        // Test CopyToClipboardTool missing text
        let copyTool = CopyToClipboardTool(clipboardService: service)
        let failRes = try await copyTool.execute(arguments: [:])
        XCTAssertFalse(failRes.success)
    }

    // MARK: - Category 2: Context Awareness

    struct MockContextService: ContextServiceProtocol {
        let mockInfo: ActiveContextInfo
        func getActiveContext() async -> ActiveContextInfo { mockInfo }
    }

    func testGetActiveContextTool() async throws {
        let mock = MockContextService(mockInfo: ActiveContextInfo(
            appName: "Safari",
            bundleId: "com.apple.Safari",
            browserURL: "https://apple.com",
            browserTitle: "Apple"
        ))

        let tool = GetActiveContextTool(contextService: mock)
        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("Safari"))
        XCTAssertTrue(result.message.contains("https://apple.com"))
    }

    func testPreviewFileToolValidation() async throws {
        let tool = PreviewFileTool()
        XCTAssertEqual(tool.definition.name, "preview_file")
        XCTAssertEqual(tool.riskLevel, .safe)

        // Non-existent file
        let badRes = try await tool.execute(arguments: ["path": AnyCodable("/path/that/does/not/exist/999.txt")])
        XCTAssertFalse(badRes.success)
        XCTAssertTrue(badRes.error?.contains("does not exist") == true)
    }

    // MARK: - Category 3: Document RAG

    func testLocalDocumentIndexerAndSearch() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let doc1URL = tempDir.appendingPathComponent("project_meeting.txt")
        try "NeedleBar release roadmap and architecture discussion for macOS local automation.".write(to: doc1URL, atomically: true, encoding: .utf8)

        let indexer = LocalDocumentIndexer(autoIndexCommonDirectories: false)
        await indexer.indexFile(at: doc1URL)

        let results = await indexer.search(query: "roadmap architecture", topK: 3)
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.fileName, "project_meeting.txt")

        let searchTool = SearchLocalDocumentsTool(indexer: indexer)
        let toolRes = try await searchTool.execute(arguments: ["query": AnyCodable("roadmap")])
        XCTAssertTrue(toolRes.success)
        XCTAssertTrue(toolRes.message.contains("project_meeting.txt"))
    }

    // MARK: - Category 4: Custom Script Plugins

    func testCustomScriptToolLoader() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("custom_tools_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestJSON = """
        {
          "name": "custom_echo_test",
          "description": "Echoes back test message",
          "executable": "/bin/echo",
          "args": ["Hello From Plugin"],
          "riskLevel": "safe",
          "triggers": ["echo plugin"],
          "parameters": {
            "properties": {}
          }
        }
        """
        let manifestFile = tempDir.appendingPathComponent("test_tool.json")
        try manifestJSON.write(to: manifestFile, atomically: true, encoding: .utf8)

        let tools = CustomScriptToolLoader.shared.loadTools(from: tempDir)
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.definition.name, "custom_echo_test")
        XCTAssertEqual(tools.first?.riskLevel, .safe)

        let execResult = try await tools.first?.execute(arguments: [:])
        XCTAssertEqual(execResult?.success, true)
        XCTAssertEqual(execResult?.message, "Hello From Plugin")
    }

    // MARK: - Category 5: Active Timer Tracker

    @MainActor
    func testActiveTimerTracker() async throws {
        let tracker = ActiveTimerTracker()
        tracker.startCountdown(durationSeconds: 120, label: "Coffee")
        XCTAssertTrue(tracker.isTimerActive)
        XCTAssertEqual(tracker.remainingSeconds, 120)
        XCTAssertEqual(tracker.timerLabel, "Coffee")

        tracker.cancel()
        XCTAssertFalse(tracker.isTimerActive)
        XCTAssertEqual(tracker.remainingSeconds, 0)
    }

    // MARK: - Tool Registry Expansion

    func testDefaultRegistryIncludesAllNewTools() {
        let registry = ToolRegistry.createDefaultRegistry()
        let allToolNames = Set(registry.allTools.map { $0.definition.name })

        let expectedTools = [
            "open_application", "quit_application", "open_url", "open_folder",
            "search_files", "list_recent_files", "create_folder", "move_file", "rename_file",
            "start_timer", "create_reminder", "create_calendar_event",
            "get_battery_status", "get_frontmost_application", "get_system_summary",
            "search_notes", "search_command_history",
            // New Categories:
            "run_shortcut", "media_control", "set_volume",
            "manage_window", "toggle_dark_mode", "lock_screen", "empty_trash", "toggle_dnd",
            "get_clipboard_history", "copy_to_clipboard",
            "get_active_context", "preview_file",
            "search_local_documents"
        ]

        for tool in expectedTools {
            XCTAssertTrue(allToolNames.contains(tool), "Registry should include '\(tool)'")
        }
        XCTAssertGreaterThanOrEqual(allToolNames.count, 27)
    }
}
