import Foundation

public struct RunShortcutTool: ToolProtocol {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "run_shortcut",
            description: "Run an Apple Shortcut by name.",
            parameters: ParametersSchema(
                properties: [
                    "name": PropertyDefinition(type: "string", description: "Name of the shortcut to run"),
                    "input": PropertyDefinition(type: "string", description: "Optional text input to pass to the shortcut")
                ],
                required: ["name"]
            ),
            triggers: ["\\b(shortcut|run shortcut|trigger shortcut)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .requiresConfirmation }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let name = arguments["name"]?.stringValue, !name.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'name' argument for shortcut.")
        }

        let input = arguments["input"]?.stringValue
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        var args = ["run", name]
        if let input = input, !input.isEmpty {
            args.append(contentsOf: ["--input-path", "-"])
        }
        process.arguments = args

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        if let input = input, !input.isEmpty {
            let inPipe = Pipe()
            process.standardInput = inPipe
            if let data = input.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
                try? inPipe.fileHandleForWriting.close()
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                let msg = output.isEmpty ? "Executed shortcut '\(name)'." : "Executed shortcut '\(name)': \(output)"
                return .success(tool: definition.name, message: msg, data: ["output": AnyCodable(output)])
            } else {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown shortcuts error"
                return .failure(tool: definition.name, error: "Shortcut '\(name)' failed: \(err)")
            }
        } catch {
            return .failure(tool: definition.name, error: "Failed to execute shortcut: \(error.localizedDescription)")
        }
    }
}
