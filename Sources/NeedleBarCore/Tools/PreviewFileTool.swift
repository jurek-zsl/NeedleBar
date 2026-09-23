import Foundation

public struct PreviewFileTool: ToolProtocol {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "preview_file",
            description: "Open a file in macOS Quick Look preview.",
            parameters: ParametersSchema(
                properties: [
                    "path": PropertyDefinition(type: "string", description: "Path to the file to preview")
                ],
                required: ["path"]
            ),
            triggers: ["\\b(preview|quick look|look at file|preview file)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let rawPath = arguments["path"]?.stringValue, !rawPath.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'path' argument.")
        }

        let expandedPath = (rawPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .failure(tool: definition.name, error: "File does not exist at '\(rawPath)'.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", expandedPath]

        // Suppress stdout/stderr noise from qlmanage
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            let fileName = URL(fileURLWithPath: expandedPath).lastPathComponent
            return .success(tool: definition.name, message: "Opened Quick Look preview for '\(fileName)'.")
        } catch {
            return .failure(tool: definition.name, error: "Failed to open preview: \(error.localizedDescription)")
        }
    }
}
