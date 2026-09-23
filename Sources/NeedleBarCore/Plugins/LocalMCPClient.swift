import Foundation

public struct MCPServerConfig: Codable, Sendable {
    public let command: String
    public let args: [String]?
    public let env: [String: String]?

    public init(command: String, args: [String]? = nil, env: [String: String]? = nil) {
        self.command = command
        self.args = args
        self.env = env
    }
}

public struct MCPConfigFile: Codable, Sendable {
    public let mcpServers: [String: MCPServerConfig]

    public init(mcpServers: [String: MCPServerConfig] = [:]) {
        self.mcpServers = mcpServers
    }
}

public struct MCPToolBridge: ToolProtocol {
    public let definition: ToolDefinition
    public let riskLevel: RiskLevel
    public let serverName: String
    public let mcpToolName: String
    private let client: LocalMCPClient

    public init(
        serverName: String,
        mcpToolName: String,
        description: String,
        parameters: ParametersSchema,
        client: LocalMCPClient,
        riskLevel: RiskLevel = .requiresConfirmation
    ) {
        self.serverName = serverName
        self.mcpToolName = mcpToolName
        self.client = client
        self.riskLevel = riskLevel
        self.definition = ToolDefinition(
            name: "mcp_\(serverName)_\(mcpToolName)",
            description: description,
            parameters: parameters,
            triggers: [mcpToolName, serverName]
        )
    }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        return try await client.callTool(serverName: serverName, toolName: mcpToolName, arguments: arguments)
    }
}

public actor LocalMCPClient {
    public static let shared = LocalMCPClient()

    private var runningProcesses: [String: Process] = [:]
    private var stdinPipes: [String: Pipe] = [:]
    private var stdoutPipes: [String: Pipe] = [:]
    private var requestId: Int = 1

    public static var defaultConfigFile: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/needlebar/mcp_servers.json")
    }

    public init() {}

    public func discoverTools(from configFile: URL? = nil) async -> [any ToolProtocol] {
        let configURL = configFile ?? Self.defaultConfigFile
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(MCPConfigFile.self, from: data) else {
            return []
        }

        var discovered: [any ToolProtocol] = []

        for (name, serverConfig) in config.mcpServers {
            do {
                let tools = try await startAndDiscover(serverName: name, config: serverConfig)
                discovered.append(contentsOf: tools)
            } catch {
                // Silently skip offline or misconfigured MCP servers
            }
        }

        return discovered
    }

    private func startAndDiscover(serverName: String, config: MCPServerConfig) async throws -> [any ToolProtocol] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: (config.command as NSString).expandingTildeInPath)
        if let args = config.args {
            process.arguments = args
        }
        if let env = config.env {
            var fullEnv = ProcessInfo.processInfo.environment
            for (k, v) in env { fullEnv[k] = v }
            process.environment = fullEnv
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        runningProcesses[serverName] = process
        stdinPipes[serverName] = stdinPipe
        stdoutPipes[serverName] = stdoutPipe

        // Send JSON-RPC initialize
        let initRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextRequestId(),
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "NeedleBar", "version": "1.0.0"]
            ]
        ]
        sendJsonRpc(initRequest, to: stdinPipe)

        // Read response line
        _ = readJsonRpcResponse(from: stdoutPipe)

        // Request tools/list
        let listRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextRequestId(),
            "method": "tools/list",
            "params": [:] as [String: Any]
        ]
        sendJsonRpc(listRequest, to: stdinPipe)

        guard let response = readJsonRpcResponse(from: stdoutPipe),
              let result = response["result"] as? [String: Any],
              let toolsList = result["tools"] as? [[String: Any]] else {
            return []
        }

        var bridged: [any ToolProtocol] = []
        for toolDict in toolsList {
            guard let tName = toolDict["name"] as? String else { continue }
            let desc = toolDict["description"] as? String ?? ""
            let schema = parseSchema(from: toolDict["inputSchema"] as? [String: Any])

            bridged.append(MCPToolBridge(
                serverName: serverName,
                mcpToolName: tName,
                description: desc,
                parameters: schema,
                client: self
            ))
        }

        return bridged
    }

    public func callTool(serverName: String, toolName: String, arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let inPipe = stdinPipes[serverName],
              let outPipe = stdoutPipes[serverName],
              let proc = runningProcesses[serverName], proc.isRunning else {
            return .failure(tool: toolName, error: "MCP server '\(serverName)' is not running.")
        }

        var rawArgs: [String: Any] = [:]
        for (k, v) in arguments {
            rawArgs[k] = v.value.base
        }

        let id = nextRequestId()
        let callRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "tools/call",
            "params": [
                "name": toolName,
                "arguments": rawArgs
            ]
        ]

        sendJsonRpc(callRequest, to: inPipe)
        let response = readJsonRpcResponse(from: outPipe)

        guard let resp = response else {
            return .failure(tool: toolName, error: "No response from MCP server '\(serverName)'.")
        }

        if let error = resp["error"] as? [String: Any], let msg = error["message"] as? String {
            return .failure(tool: toolName, error: "MCP error: \(msg)")
        }

        if let result = resp["result"] as? [String: Any] {
            var output = ""
            if let content = result["content"] as? [[String: Any]] {
                for item in content {
                    if let text = item["text"] as? String {
                        output += text + "\n"
                    }
                }
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(tool: toolName, message: trimmed.isEmpty ? "MCP tool executed." : trimmed)
        }

        return .success(tool: toolName, message: "Executed tool on '\(serverName)'.")
    }

    private func nextRequestId() -> Int {
        let current = requestId
        requestId += 1
        return current
    }

    private func sendJsonRpc(_ dict: [String: Any], to pipe: Pipe) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        var packet = data
        packet.append(contentsOf: [0x0A]) // Newline delimited JSON
        pipe.fileHandleForWriting.write(packet)
    }

    private func readJsonRpcResponse(from pipe: Pipe) -> [String: Any]? {
        let handle = pipe.fileHandleForReading
        let rawData = handle.availableData
        guard !rawData.isEmpty else { return nil }

        if let line = String(data: rawData, encoding: .utf8)?.split(separator: "\n").first,
           let lineData = line.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
            return obj
        }
        return nil
    }

    private func parseSchema(from dict: [String: Any]?) -> ParametersSchema {
        guard let dict = dict else { return ParametersSchema(properties: [:]) }
        var props: [String: PropertyDefinition] = [:]
        if let propMap = dict["properties"] as? [String: [String: Any]] {
            for (k, v) in propMap {
                let type = v["type"] as? String ?? "string"
                let desc = v["description"] as? String ?? ""
                props[k] = PropertyDefinition(type: type, description: desc)
            }
        }
        let req = dict["required"] as? [String]
        return ParametersSchema(properties: props, required: req)
    }

    deinit {
        for (_, proc) in runningProcesses {
            proc.terminate()
        }
    }
}
