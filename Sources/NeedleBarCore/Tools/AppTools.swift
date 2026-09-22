import Foundation

public struct OpenApplicationTool: ToolProtocol {
    private let workspaceService: WorkspaceServiceProtocol

    public init(workspaceService: WorkspaceServiceProtocol = DefaultWorkspaceService()) {
        self.workspaceService = workspaceService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "open_application",
            description: "Open an installed macOS application by name.",
            parameters: ParametersSchema(
                properties: [
                    "name": PropertyDefinition(type: "string", description: "Name of the application, e.g. Safari, Xcode")
                ],
                required: ["name"]
            )
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let name = arguments["name"]?.stringValue, !name.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'name' argument for application.")
        }
        try await workspaceService.openApplication(named: name)
        return .success(tool: definition.name, message: "Opened application '\(name)'.")
    }
}

public struct QuitApplicationTool: ToolProtocol {
    private let workspaceService: WorkspaceServiceProtocol

    public init(workspaceService: WorkspaceServiceProtocol = DefaultWorkspaceService()) {
        self.workspaceService = workspaceService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "quit_application",
            description: "Quit a running macOS application.",
            parameters: ParametersSchema(
                properties: [
                    "name": PropertyDefinition(type: "string", description: "Name of the application to quit")
                ],
                required: ["name"]
            )
        )
    }

    public var riskLevel: RiskLevel { .requiresConfirmation }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let name = arguments["name"]?.stringValue, !name.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'name' argument for application.")
        }
        try await workspaceService.quitApplication(named: name)
        return .success(tool: definition.name, message: "Quit application '\(name)'.")
    }
}

public struct OpenURLTool: ToolProtocol {
    private let workspaceService: WorkspaceServiceProtocol

    public init(workspaceService: WorkspaceServiceProtocol = DefaultWorkspaceService()) {
        self.workspaceService = workspaceService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "open_url",
            description: "Open a web URL in the default web browser.",
            parameters: ParametersSchema(
                properties: [
                    "url": PropertyDefinition(type: "string", description: "Full URL to open, e.g. https://apple.com")
                ],
                required: ["url"]
            )
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard var urlString = arguments["url"]?.stringValue, !urlString.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'url' argument.")
        }
        if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        guard let url = URL(string: urlString) else {
            return .failure(tool: definition.name, error: "Invalid URL: \(urlString)")
        }
        try await workspaceService.openURL(url)
        return .success(tool: definition.name, message: "Opened URL: \(urlString)")
    }
}

public struct OpenFolderTool: ToolProtocol {
    private let workspaceService: WorkspaceServiceProtocol
    private let pathSafety: PathSafety

    public init(
        workspaceService: WorkspaceServiceProtocol = DefaultWorkspaceService(),
        pathSafety: PathSafety = .shared
    ) {
        self.workspaceService = workspaceService
        self.pathSafety = pathSafety
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "open_folder",
            description: "Reveal and open a directory in Finder.",
            parameters: ParametersSchema(
                properties: [
                    "path": PropertyDefinition(type: "string", description: "Directory path to reveal, e.g. ~/Documents")
                ],
                required: ["path"]
            )
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let pathString = arguments["path"]?.stringValue, !pathString.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'path' argument.")
        }
        let url = try pathSafety.validatePath(pathString, allowNonExistent: false)
        try await workspaceService.openFolder(at: url)
        return .success(tool: definition.name, message: "Revealed folder in Finder: \(url.path)")
    }
}
