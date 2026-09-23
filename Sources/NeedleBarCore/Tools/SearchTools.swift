import Foundation

public struct SearchNotesTool: ToolProtocol {
    private let notesService: NotesServiceProtocol

    public init(notesService: NotesServiceProtocol = DefaultNotesService()) {
        self.notesService = notesService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "search_notes",
            description: "Search notes in Apple Notes by keyword.",
            parameters: ParametersSchema(
                properties: [
                    "query": PropertyDefinition(type: "string", description: "Search term or phrase in Apple Notes")
                ],
                required: ["query"]
            )
        )
    }

    public var riskLevel: RiskLevel { .safe }
    public var requiredPermission: PermissionType? { .notesAutomation }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'query' argument.")
        }
        let titles = try await notesService.searchNotes(query: query)
        let count = titles.count
        let msg = count == 0 ? "No notes found matching '\(query)'." : "Found \(count) note(s) matching '\(query)': \(titles.prefix(5).joined(separator: ", "))."
        return .success(
            tool: definition.name,
            message: msg,
            data: ["notes": AnyCodable(titles), "count": AnyCodable(count)]
        )
    }
}

public struct SearchCommandHistoryTool: ToolProtocol {
    private let searchCallback: (@Sendable (String) async -> [HistoryRecord])?

    public init(searchCallback: (@Sendable (String) async -> [HistoryRecord])? = nil) {
        self.searchCallback = searchCallback
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "search_command_history",
            description: "Search previous NeedleBar commands and actions.",
            parameters: ParametersSchema(
                properties: [
                    "query": PropertyDefinition(type: "string", description: "Search query for command history")
                ],
                required: ["query"]
            )
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'query' argument.")
        }

        if let searchCallback = searchCallback {
            let records = await searchCallback(query)
            let summaries = records.map { "\($0.query) -> \($0.summary)" }
            return .success(
                tool: definition.name,
                message: "Found \(records.count) past command(s) matching '\(query)'.",
                data: ["results": AnyCodable(summaries)]
            )
        }

        return .success(tool: definition.name, message: "Searched command history for '\(query)'.")
    }
}
