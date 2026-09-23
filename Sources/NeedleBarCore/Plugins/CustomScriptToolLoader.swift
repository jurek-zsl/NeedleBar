import Foundation

public struct CustomToolManifest: Codable, Sendable {
    public let name: String
    public let description: String
    public let executable: String
    public let args: [String]?
    public let riskLevel: String?
    public let triggers: [String]?
    public let parameters: ParametersSchema?

    public init(
        name: String,
        description: String,
        executable: String,
        args: [String]? = nil,
        riskLevel: String? = nil,
        triggers: [String]? = nil,
        parameters: ParametersSchema? = nil
    ) {
        self.name = name
        self.description = description
        self.executable = executable
        self.args = args
        self.riskLevel = riskLevel
        self.triggers = triggers
        self.parameters = parameters
    }
}

public struct CustomScriptTool: ToolProtocol {
    public let definition: ToolDefinition
    public let riskLevel: RiskLevel
    public let executable: String
    public let baseArgs: [String]

    public init(manifest: CustomToolManifest) {
        let risk: RiskLevel
        switch manifest.riskLevel?.lowercased() {
        case "safe": risk = .safe
        case "destructive": risk = .destructive
        default: risk = .requiresConfirmation
        }

        self.definition = ToolDefinition(
            name: manifest.name,
            description: manifest.description,
            parameters: manifest.parameters ?? ParametersSchema(properties: [:]),
            triggers: manifest.triggers ?? []
        )
        self.riskLevel = risk
        self.executable = manifest.executable
        self.baseArgs = manifest.args ?? []
    }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: (executable as NSString).expandingTildeInPath)

        // Inject arguments as environment variables NEEDLE_ARG_<KEY>
        var env = ProcessInfo.processInfo.environment
        for (key, val) in arguments {
            let envKey = "NEEDLE_ARG_" + key.uppercased().replacingOccurrences(of: "-", with: "_")
            if let str = val.stringValue {
                env[envKey] = str
            } else if let num = val.intValue {
                env[envKey] = "\(num)"
            } else if let b = val.boolValue {
                env[envKey] = b ? "true" : "false"
            }
        }
        process.environment = env
        process.arguments = baseArgs

        // Also pass JSON arguments via stdin
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            let jsonArgData = try? JSONEncoder().encode(arguments)
            if let data = jsonArgData {
                stdinPipe.fileHandleForWriting.write(data)
            }
            try? stdinPipe.fileHandleForWriting.close()

            process.waitUntilExit()

            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                let msg = output.isEmpty ? "Executed custom tool '\(definition.name)' successfully." : output
                return .success(tool: definition.name, message: msg)
            } else {
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown script error"
                return .failure(tool: definition.name, error: "Custom tool '\(definition.name)' exited with code \(process.terminationStatus): \(err)")
            }
        } catch {
            return .failure(tool: definition.name, error: "Failed to execute custom tool: \(error.localizedDescription)")
        }
    }
}

public final class CustomScriptToolLoader: @unchecked Sendable {
    public static let shared = CustomScriptToolLoader()

    public static var defaultToolsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/needlebar/tools", isDirectory: true)
    }

    public init() {}

    public func loadTools(from directory: URL? = nil) -> [any ToolProtocol] {
        let dir = directory ?? Self.defaultToolsDirectory
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            createExampleTemplate(in: dir)
            return []
        }

        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        var loadedTools: [any ToolProtocol] = []
        let decoder = JSONDecoder()

        for file in files where file.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: file),
                  let manifest = try? decoder.decode(CustomToolManifest.self, from: data) else {
                continue
            }
            loadedTools.append(CustomScriptTool(manifest: manifest))
        }

        return loadedTools
    }

    private func createExampleTemplate(in directory: URL) {
        let templateURL = directory.appendingPathComponent("example_tool.json.template")
        guard !FileManager.default.fileExists(atPath: templateURL.path) else { return }

        let exampleJSON = """
        {
          "name": "echo_custom",
          "description": "Echoes back input from a custom bash script",
          "executable": "/bin/bash",
          "args": ["-c", "echo Custom Tool Received: $NEEDLE_ARG_MESSAGE"],
          "riskLevel": "safe",
          "triggers": ["custom echo", "echo test"],
          "parameters": {
            "properties": {
              "message": {
                "type": "string",
                "description": "Message to echo"
              }
            },
            "required": ["message"]
          }
        }
        """
        try? exampleJSON.write(to: templateURL, atomically: true, encoding: .utf8)
    }
}
