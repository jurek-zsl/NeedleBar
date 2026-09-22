import Foundation

public struct IndexedItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let category: String
    public let metadata: [String: String]
    public let vector: [Float]?

    public init(
        id: UUID = UUID(),
        text: String,
        category: String,
        metadata: [String: String] = [:],
        vector: [Float]? = nil
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.metadata = metadata
        self.vector = vector
    }
}

public struct SearchMatch: Identifiable, Equatable, Sendable {
    public var id: UUID { item.id }
    public let item: IndexedItem
    public let score: Float

    public init(item: IndexedItem, score: Float) {
        self.item = item
        self.score = score
    }
}

public actor EmbeddingIndex {
    private var items: [IndexedItem] = []
    private let client: (any NeedleClientProtocol)?

    public init(client: (any NeedleClientProtocol)? = nil) {
        self.client = client
    }

    public func addItem(text: String, category: String, metadata: [String: String] = [:]) async {
        var vector: [Float]? = nil
        if let client = client {
            do {
                let vec = try await client.embed(text: text)
                if !vec.isEmpty {
                    vector = vec
                }
            } catch {
                // Fallback: keep vector as nil
            }
        }
        let item = IndexedItem(text: text, category: category, metadata: metadata, vector: vector)
        items.append(item)
    }

    public func search(query: String, topK: Int = 5) async -> [SearchMatch] {
        guard !items.isEmpty else { return [] }

        var queryVec: [Float]? = nil
        if let client = client {
            queryVec = try? await client.embed(text: query)
        }

        if let qVec = queryVec, !qVec.isEmpty {
            var scored: [SearchMatch] = []
            for item in items {
                if let iVec = item.vector, iVec.count == qVec.count {
                    let sim = cosineSimilarity(qVec, iVec)
                    scored.append(SearchMatch(item: item, score: sim))
                } else {
                    // Keyword match fallback score
                    let sim = keywordScore(query: query, target: item.text)
                    scored.append(SearchMatch(item: item, score: sim))
                }
            }
            return Array(scored.sorted { $0.score > $1.score }.prefix(topK))
        } else {
            // Keyword match fallback
            let scored = items.map { item in
                SearchMatch(item: item, score: keywordScore(query: query, target: item.text))
            }
            return Array(scored.sorted { $0.score > $1.score }.prefix(topK))
        }
    }

    public func count() -> Int {
        items.count
    }

    public func clear() {
        items.removeAll()
    }

    // MARK: - Mathematical Helpers

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0

        for i in 0..<a.count {
            let va = a[i]
            let vb = b[i]
            dotProduct += va * vb
            normA += va * va
            normB += vb * vb
        }

        let denom = sqrt(normA) * sqrt(normB)
        if denom == 0.0 { return 0.0 }
        return dotProduct / denom
    }

    private func keywordScore(query: String, target: String) -> Float {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let t = target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if q == t { return 1.0 }
        if t.contains(q) { return 0.8 }
        let qTokens = Set(q.split(separator: " "))
        let tTokens = Set(t.split(separator: " "))
        let common = qTokens.intersection(tTokens)
        if !qTokens.isEmpty {
            return Float(common.count) / Float(qTokens.count) * 0.6
        }
        return 0.0
    }
}
