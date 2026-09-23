import Foundation

public struct SearchLocalDocumentsTool: ToolProtocol {
    private let indexer: LocalDocumentIndexer

    public init(indexer: LocalDocumentIndexer = .shared) {
        self.indexer = indexer
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "search_local_documents",
            description: "Search local documents and notes in ~/Documents and ~/Desktop semantically or by keyword.",
            parameters: ParametersSchema(
                properties: [
                    "query": PropertyDefinition(type: "string", description: "Search term or semantic topic to find in documents"),
                    "limit": PropertyDefinition(type: "integer", description: "Maximum number of document results to return (default: 5)")
                ],
                required: ["query"]
            ),
            triggers: ["\\b(search documents|find document|search pdf|find note|search files content|document search)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'query' argument.")
        }

        let limit = arguments["limit"]?.intValue ?? 5
        let results = await indexer.search(query: query, topK: limit)

        if results.isEmpty {
            return .success(
                tool: definition.name,
                message: "No matching local documents found for '\(query)'.",
                data: ["results": AnyCodable([String]())]
            )
        }

        let formatted = results.enumerated().map { index, doc in
            let snippetClean = doc.snippet.replacingOccurrences(of: "\n", with: " ")
            let preview = snippetClean.count > 100 ? String(snippetClean.prefix(97)) + "..." : snippetClean
            return "\(index + 1). \(doc.fileName)\n   Path: \(doc.filePath)\n   Snippet: \"\(preview)\""
        }.joined(separator: "\n\n")

        return .success(
            tool: definition.name,
            message: "Found \(results.count) matching document(s):\n\n\(formatted)",
            data: [
                "results": AnyCodable(results.map { [
                    "fileName": AnyCodable($0.fileName),
                    "filePath": AnyCodable($0.filePath),
                    "score": AnyCodable(Double($0.score))
                ]})
            ]
        )
    }
}
