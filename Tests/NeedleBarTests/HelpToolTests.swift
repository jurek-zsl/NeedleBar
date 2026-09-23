import XCTest
@testable import NeedleBarCore

final class HelpToolTests: XCTestCase {

    func testHelpToolDefinition() {
        let tool = HelpTool()
        XCTAssertEqual(tool.definition.name, "show_help")
        XCTAssertEqual(tool.riskLevel, .safe)
        XCTAssertTrue(tool.definition.parameters.properties.keys.contains("category"))
        XCTAssertTrue(tool.definition.triggers?.contains { $0.contains("help") } == true)
    }

    func testHelpToolExecutionReturnsFormattedCatalog() async throws {
        final class FlagBox: @unchecked Sendable {
            var value = false
        }
        let box = FlagBox()
        let tool = HelpTool(onPresentHelp: {
            box.value = true
        })

        let result = try await tool.execute(arguments: [:])
        XCTAssertTrue(result.success)
        XCTAssertTrue(box.value)
        XCTAssertTrue(result.message.contains("NeedleBar Capabilities & Examples Guide"))
        XCTAssertTrue(result.message.contains("System & Audio"))
        XCTAssertTrue(result.message.contains("Productivity & Timers"))
        XCTAssertTrue(result.message.contains("Window Tiling"))
    }

    func testHelpToolCategoryFiltering() async throws {
        let tool = HelpTool()
        let result = try await tool.execute(arguments: ["category": AnyCodable("productivity")])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.message.contains("Productivity & Timers"))
        XCTAssertFalse(result.message.contains("Window Tiling"))
    }

    func testHelpCatalogIntegrity() {
        let all = HelpCatalog.allCapabilities
        XCTAssertFalse(all.isEmpty)

        // Verify each capability has valid metadata and examples
        for item in all {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.description.isEmpty)
            XCTAssertFalse(item.icon.isEmpty)
            XCTAssertFalse(item.examples.isEmpty, "Item \(item.title) must have examples")
        }

        // Verify all non-all categories are represented
        let coveredCategories = Set(all.map { $0.category })
        for cat in CapabilityCategory.allCases where cat != .all {
            XCTAssertTrue(coveredCategories.contains(cat), "Category \(cat.rawValue) has no registered capabilities")
        }
    }

    @MainActor
    func testAppStateHelpCommandFastPath() async {
        let appState = AppState(
            needleClient: MockNeedleClient(),
            preferencesStore: PreferencesStore.shared
        )

        XCTAssertFalse(appState.isHelpPresented)

        // Test "help"
        await appState.submitCommand("help")
        XCTAssertTrue(appState.isHelpPresented)
        XCTAssertFalse(appState.isProcessing)
        XCTAssertNil(appState.errorMessage)

        // Test dismiss
        appState.dismissHelp()
        XCTAssertFalse(appState.isHelpPresented)

        // Test "/help"
        await appState.submitCommand("/help")
        XCTAssertTrue(appState.isHelpPresented)

        // Test dismissal when regular command starts
        appState.inputQuery = "start timer 5 min"
        // Starting another command resets help
        await appState.submitCommand("start timer 5 min")
        XCTAssertFalse(appState.isHelpPresented)
    }
}
