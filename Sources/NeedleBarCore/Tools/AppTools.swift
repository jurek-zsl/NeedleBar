import Foundation

public struct OpenApplicationTool: ToolProtocol {
    private let workspaceService: WorkspaceServiceProtocol

    public init(workspaceService: WorkspaceServiceProtocol = DefaultWorkspaceService()) {
        self.workspaceService = workspaceService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "open_application",
            description: "Open an installed macOS application by application name (e.g. Safari, Xcode, Terminal). Do NOT use for websites, web links, or folder paths.",
            parameters: ParametersSchema(
                properties: [
                    "name": PropertyDefinition(type: "string", description: "Name of the application, e.g. Safari, Xcode")
                ],
                required: ["name"]
            ),
            triggers: ["\\b(open app|launch app|open application|open)\\b"]
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
            ),
            triggers: ["\\b(quit|close|terminate|kill)\\b"]
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
            description: "Open a web URL or domain in the default web browser (e.g. https://apple.com, google.com).",
            parameters: ParametersSchema(
                properties: [
                    "url": PropertyDefinition(type: "string", description: "Full URL to open, e.g. https://apple.com")
                ],
                required: ["url"]
            ),
            triggers: ["\\b(open url|open website|open link|browse|http|https|\\.com|\\.org|\\.net)\\b"]
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
            description: "Reveal and open a directory or folder in Finder (e.g. ~/Downloads, ~/Documents, ~/Desktop).",
            parameters: ParametersSchema(
                properties: [
                    "path": PropertyDefinition(type: "string", description: "Directory path to reveal, e.g. ~/Documents")
                ],
                required: ["path"]
            ),
            triggers: ["\\b(open folder|open directory|reveal folder|show in finder|downloads|documents|desktop)\\b"]
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
