import XCTest
@testable import NeedleBarCore

final class EmbeddingIndexTests: XCTestCase {

    func testEmbeddingIndexKeywordSearchFallback() async {
        let index = EmbeddingIndex(client: nil) // No client -> fallback mode
        await index.addItem(text: "Safari Web Browser", category: "apps")
        await index.addItem(text: "Xcode Developer Tools", category: "apps")
        await index.addItem(text: "Monthly Invoice March", category: "files")

        let count = await index.count()
        XCTAssertEqual(count, 3)

        let matches = await index.search(query: "Safari", topK: 2)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.first?.item.text, "Safari Web Browser")
        XCTAssertGreaterThan(matches.first?.score ?? 0, 0.5)
    }

    func testEmbeddingIndexWithMockVectorEmbeddings() async {
        let mockClient = MockNeedleClient()
        let index = EmbeddingIndex(client: mockClient)

        await index.addItem(text: "Open Safari", category: "command")
        await index.addItem(text: "Start a focus timer", category: "command")

        let results = await index.search(query: "Open Safari", topK: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.text, "Open Safari")
        XCTAssertGreaterThan(results.first?.score ?? 0, 0.9)
    }
}
