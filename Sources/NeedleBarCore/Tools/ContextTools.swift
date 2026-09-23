import Foundation

public struct GetActiveContextTool: ToolProtocol {
    private let contextService: ContextServiceProtocol

    public init(contextService: ContextServiceProtocol = DefaultContextService()) {
        self.contextService = contextService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "get_active_context",
            description: "Get context of the active macOS workspace (frontmost app, browser URL/title, Finder selection, or highlighted text).",
            parameters: ParametersSchema(properties: [:]),
            triggers: ["\\b(active app|current app|current page|selected file|selection|this page|what am i looking at|context)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let info = await contextService.getActiveContext()

        var lines: [String] = ["Active Application: \(info.appName) (\(info.bundleId))"]
        var data: [String: AnyCodable] = [
            "appName": AnyCodable(info.appName),
            "bundleId": AnyCodable(info.bundleId)
        ]

        if let winTitle = info.windowTitle {
            lines.append("Window: \"\(winTitle)\"")
            data["windowTitle"] = AnyCodable(winTitle)
        }

        if let url = info.browserURL {
            let title = info.browserTitle ?? ""
            lines.append("Active Tab: \(title.isEmpty ? url : "\(title) (\(url))")")
            data["browserURL"] = AnyCodable(url)
            data["browserTitle"] = AnyCodable(title)
        }

        if let files = info.selectedFiles, !files.isEmpty {
            lines.append("Selected Files:\n" + files.map { "  • \($0)" }.joined(separator: "\n"))
            data["selectedFiles"] = AnyCodable(files)
        }

        if let text = info.selectedText, !text.isEmpty {
            let preview = text.count > 100 ? String(text.prefix(97)) + "..." : text
            lines.append("Selected Text: \"\(preview)\"")
            data["selectedText"] = AnyCodable(text)
        }

        return .success(tool: definition.name, message: lines.joined(separator: "\n"), data: data)
    }
}
