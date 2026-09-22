import XCTest
@testable import NeedleBarCore

final class NeedleCBridgeIntegrationTests: XCTestCase {

    func testLiveNeedleCBridgeIfPresent() async throws {
        let dylibPath = "/tmp/needle-test/libneedle3.dylib"
        let modelPath = "/tmp/needle-test/needle3.cact"

        guard FileManager.default.fileExists(atPath: dylibPath),
              FileManager.default.fileExists(atPath: modelPath) else {
            print("Skipping live integration test: model weights or dylib not found at /tmp/needle-test")
            return
        }

        let bridge = NeedleCBridge(libraryPath: dylibPath, modelPath: modelPath)
        let registry = ToolRegistry.createDefaultRegistry()
        let schemas = try registry.generateSchemasJSON()

        try await bridge.initialize(toolsJSON: schemas, systemPrompt: "date: 2026-09-22 Tue; locale: en-US; device: mac")

        let status = await bridge.status()
        XCTAssertTrue(status.isLoaded)

        // 1. Test live inference
        let response = try await bridge.complete(prompt: "Open Safari", maxTokens: 128)
        XCTAssertEqual(response.type, "call")
        XCTAssertEqual(response.effectiveCalls.first?.name, "open_application")
        XCTAssertEqual(response.effectiveCalls.first?.string(for: "name"), "Safari")

        // 2. Test live embeddings
        let embedding = try await bridge.embed(text: "Test embedding generation")
        XCTAssertEqual(embedding.count, 3072)
        XCTAssertNotEqual(embedding.reduce(0, +), 0.0)
    }
}
