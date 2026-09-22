import Foundation

public struct SearchFilesTool: ToolProtocol {
    private let fileService: FileSystemServiceProtocol
    private let pathSafety: PathSafety

    public init(
        fileService: FileSystemServiceProtocol = DefaultFileSystemService(),
        pathSafety: PathSafety = .shared
    ) {
        self.fileService = fileService
        self.pathSafety = pathSafety
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "search_files",
            description: "Search for files by filename query in a directory.",
            parameters: ParametersSchema(
                properties: [
                    "query": PropertyDefinition(type: "string", description: "Search query or file pattern"),
                    "directory": PropertyDefinition(type: "string", description: "Optional directory to search in, defaults to user home")
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
        let dirString = arguments["directory"]?.stringValue ?? NSHomeDirectory()
        let dirURL = try pathSafety.validatePath(dirString, allowNonExistent: false)

        let matches = try fileService.searchFiles(query: query, in: dirURL)
        let count = matches.count
        let paths = matches.map { $0.path }
        let summary = count == 0 ? "No files found matching '\(query)' in \(dirURL.path)." : "Found \(count) file(s) matching '\(query)'."
        return .success(
            tool: definition.name,
            message: summary,
            data: ["files": AnyCodable(paths), "count": AnyCodable(count)]
        )
    }
}

public struct ListRecentFilesTool: ToolProtocol {
    private let fileService: FileSystemServiceProtocol
    private let pathSafety: PathSafety

    public init(
        fileService: FileSystemServiceProtocol = DefaultFileSystemService(),
        pathSafety: PathSafety = .shared
    ) {
        self.fileService = fileService
        self.pathSafety = pathSafety
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "list_recent_files",
            description: "List recently modified files in a specified directory.",
            parameters: ParametersSchema(
                properties: [
                    "directory": PropertyDefinition(type: "string", description: "Directory to inspect, defaults to ~/Downloads"),
                    "limit": PropertyDefinition(type: "integer", description: "Maximum number of files to return (default 10)")
                ]
            )
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let dirString = arguments["directory"]?.stringValue ?? (NSHomeDirectory() + "/Downloads")
        let limit = arguments["limit"]?.intValue ?? 10
        let dirURL = try pathSafety.validatePath(dirString, allowNonExistent: false)

        let files = try fileService.listRecentFiles(in: dirURL, limit: limit)
        let fileNames = files.map { $0.lastPathComponent }
        return .success(
            tool: definition.name,
            message: "Found \(files.count) recent file(s) in \(dirURL.lastPathComponent).",
            data: ["files": AnyCodable(fileNames)]
        )
    }
}

public struct CreateFolderTool: ToolProtocol {
    private let fileService: FileSystemServiceProtocol
    private let pathSafety: PathSafety

    public init(
        fileService: FileSystemServiceProtocol = DefaultFileSystemService(),
        pathSafety: PathSafety = .shared
    ) {
        self.fileService = fileService
        self.pathSafety = pathSafety
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "create_folder",
            description: "Create a new folder at the specified path.",
            parameters: ParametersSchema(
                properties: [
                    "path": PropertyDefinition(type: "string", description: "Directory path of the new folder")
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
        let url = pathSafety.resolvePath(pathString)
        try fileService.createFolder(at: url)
        return .success(tool: definition.name, message: "Created folder: \(url.path)")
    }
}

public struct MoveFileTool: ToolProtocol {
    private let fileService: FileSystemServiceProtocol
    private let pathSafety: PathSafety

    public init(
        fileService: FileSystemServiceProtocol = DefaultFileSystemService(),
        pathSafety: PathSafety = .shared
    ) {
        self.fileService = fileService
        self.pathSafety = pathSafety
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "move_file",
            description: "Move a file from a source path to a destination directory or file path.",
            parameters: ParametersSchema(
                properties: [
                    "source": PropertyDefinition(type: "string", description: "Source file path"),
                    "destination": PropertyDefinition(type: "string", description: "Destination path or folder")
                ],
                required: ["source", "destination"]
            )
        )
    }

    public var riskLevel: RiskLevel { .requiresConfirmation }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let src = arguments["source"]?.stringValue, !src.isEmpty,
              let dst = arguments["destination"]?.stringValue, !dst.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'source' or 'destination' argument.")
        }

        let preview = try pathSafety.previewOperation(source: src, destination: dst)
        let srcURL = URL(fileURLWithPath: preview.sourcePath)
        let dstURL = URL(fileURLWithPath: preview.destinationPath)

        try fileService.moveFile(from: srcURL, to: dstURL)
        return .success(
            tool: definition.name,
            message: "Moved file from \(srcURL.lastPathComponent) to \(dstURL.path)."
        )
    }
}

public struct RenameFileTool: ToolProtocol {
    private let fileService: FileSystemServiceProtocol
    private let pathSafety: PathSafety

    public init(
        fileService: FileSystemServiceProtocol = DefaultFileSystemService(),
        pathSafety: PathSafety = .shared
    ) {
        self.fileService = fileService
        self.pathSafety = pathSafety
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "rename_file",
            description: "Rename a file or folder to a new name.",
            parameters: ParametersSchema(
                properties: [
                    "path": PropertyDefinition(type: "string", description: "Existing file path"),
                    "new_name": PropertyDefinition(type: "string", description: "New name with extension")
                ],
                required: ["path", "new_name"]
            )
        )
    }

    public var riskLevel: RiskLevel { .requiresConfirmation }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let path = arguments["path"]?.stringValue, !path.isEmpty,
              let newName = arguments["new_name"]?.stringValue, !newName.isEmpty else {
            return .failure(tool: definition.name, error: "Missing required 'path' or 'new_name' argument.")
        }

        let url = try pathSafety.validatePath(path, allowNonExistent: false)
        let finalURL = try fileService.renameFile(at: url, newName: newName)
        return .success(
            tool: definition.name,
            message: "Renamed '\(url.lastPathComponent)' to '\(finalURL.lastPathComponent)'."
        )
    }
}
