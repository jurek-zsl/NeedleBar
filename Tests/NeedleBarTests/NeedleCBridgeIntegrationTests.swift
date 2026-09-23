import XCTest
@testable import NeedleBarCore

final class NeedleCBridgeIntegrationTests: XCTestCase {

    func testLiveNeedleCBridgeIfPresent() async throws {
        let home = NSHomeDirectory()
        var dylibPath = "\(home)/.cache/cactus-needle/v3/3.0.1/libneedle3.dylib"
        var modelPath = "\(home)/.cache/cactus-needle/v3/3.0.1/needle3.cact"

        if !FileManager.default.fileExists(atPath: dylibPath) {
            dylibPath = "/tmp/needle-test/libneedle3.dylib"
            modelPath = "/tmp/needle-test/needle3.cact"
        }

        guard FileManager.default.fileExists(atPath: dylibPath),
              FileManager.default.fileExists(atPath: modelPath) else {
            print("Skipping live integration test: model weights or dylib not found")
            return
        }

        let bridge = NeedleCBridge(libraryPath: dylibPath, modelPath: modelPath)
        let registry = ToolRegistry.createDefaultRegistry()
        let schemas = try registry.generateSchemasJSON()
        try await bridge.initialize(toolsJSON: schemas, systemPrompt: "date: 2026-09-22 Tue 21:00; locale: en-US; device: mac")

        let status = await bridge.status()
        XCTAssertTrue(status.isLoaded)

        // 1. Test live inference
        let response = try await bridge.complete(prompt: "open youtube.com in Safari", maxTokens: 128)
        print(">>> LIVE RESULT for 'open youtube.com in Safari':")
        print(">>> TYPE: \(String(describing: response.type)), CALLS: \(response.effectiveCalls.map { "\($0.name): \($0.arguments)" }), CONF: \(response.confidence ?? 0), REASON: \(response.reasoning ?? "")")

        // 2. Test live embeddings
        let embedding = try await bridge.embed(text: "Test embedding generation")
        XCTAssertEqual(embedding.count, 3072)
        XCTAssertNotEqual(embedding.reduce(0, +), 0.0)
    }
}
