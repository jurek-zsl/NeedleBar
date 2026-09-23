import Foundation
import AppKit

public struct GetClipboardHistoryTool: ToolProtocol {
    private let clipboardService: ClipboardService

    public init(clipboardService: ClipboardService = .shared) {
        self.clipboardService = clipboardService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "get_clipboard_history",
            description: "Retrieve recent items copied to the clipboard.",
            parameters: ParametersSchema(
                properties: [
                    "limit": PropertyDefinition(type: "integer", description: "Number of clipboard items to retrieve (default: 5)")
                ]
            ),
            triggers: ["\\b(clipboard|pasteboard|copied items|clipboard history)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let limit = arguments["limit"]?.intValue ?? 5
        let items = await clipboardService.getRecent(limit: limit)

        if items.isEmpty {
            return .success(tool: definition.name, message: "Clipboard history is empty.", data: ["items": AnyCodable([String]())])
        }

        let summaries = items.enumerated().map { index, item in
            let snippet = item.content.replacingOccurrences(of: "\n", with: " ")
            let truncated = snippet.count > 60 ? String(snippet.prefix(57)) + "..." : snippet
            return "\(index + 1). \"\(truncated)\""
        }.joined(separator: "\n")

        return .success(
            tool: definition.name,
            message: "Recent clipboard items:\n\(summaries)",
            data: ["items": AnyCodable(items.map { $0.content })]
        )
    }
}

public struct CopyToClipboardTool: ToolProtocol {
    private let clipboardService: ClipboardService

    public init(clipboardService: ClipboardService = .shared) {
        self.clipboardService = clipboardService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "copy_to_clipboard",
            description: "Copy text to the system clipboard.",
            parameters: ParametersSchema(
                properties: [
                    "text": PropertyDefinition(type: "string", description: "Text content to copy to the clipboard")
                ],
                required: ["text"]
            ),
            triggers: ["\\b(copy to clipboard|copy text|clipboard copy)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let text = arguments["text"]?.stringValue, !text.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'text' argument to copy.")
        }

        await clipboardService.copyToPasteboard(text: text)
        let preview = text.count > 40 ? String(text.prefix(37)) + "..." : text
        return .success(tool: definition.name, message: "Copied \"\(preview)\" to clipboard.")
    }
}
