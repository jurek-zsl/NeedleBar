import Foundation

public final class ToolRegistry: @unchecked Sendable {
    private var tools: [String: any ToolProtocol] = [:]
    private let lock = NSLock()

    public init() {}

    public func register(tool: any ToolProtocol) {
        lock.lock()
        defer { lock.unlock() }
        tools[tool.definition.name] = tool
    }

    public func tool(named name: String) -> (any ToolProtocol)? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]
    }

    public var allTools: [any ToolProtocol] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tools.values).sorted { $0.definition.name < $1.definition.name }
    }

    public func generateSchemasJSON() throws -> String {
        let defs = allTools.map { $0.definition }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(defs)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode tool schemas to UTF-8 JSON."
            ])
        }
        return jsonString
    }

    public static func createDefaultRegistry(
        workspaceService: WorkspaceServiceProtocol = DefaultWorkspaceService(),
        fileService: FileSystemServiceProtocol = DefaultFileSystemService(),
        productivityService: ProductivityServiceProtocol = DefaultProductivityService(),
        systemInfoService: SystemInfoServiceProtocol = DefaultSystemInfoService(),
        notesService: NotesServiceProtocol = DefaultNotesService(),
        clipboardService: ClipboardService = .shared,
        contextService: ContextServiceProtocol = DefaultContextService(),
        documentIndexer: LocalDocumentIndexer = .shared,
        historySearch: (@Sendable (String) async -> [HistoryRecord])? = nil,
        customToolsDirectory: URL? = nil,
        onPresentHelp: (@Sendable () -> Void)? = nil
    ) -> ToolRegistry {
        let registry = ToolRegistry()

        // App Tools (4)
        registry.register(tool: OpenApplicationTool(workspaceService: workspaceService))
        registry.register(tool: QuitApplicationTool(workspaceService: workspaceService))
        registry.register(tool: OpenURLTool(workspaceService: workspaceService))
        registry.register(tool: OpenFolderTool(workspaceService: workspaceService))

        // File Tools (5)
        registry.register(tool: SearchFilesTool(fileService: fileService))
        registry.register(tool: ListRecentFilesTool(fileService: fileService))
        registry.register(tool: CreateFolderTool(fileService: fileService))
        registry.register(tool: MoveFileTool(fileService: fileService))
        registry.register(tool: RenameFileTool(fileService: fileService))

        // Productivity Tools (3)
        registry.register(tool: StartTimerTool(productivityService: productivityService))
        registry.register(tool: CreateReminderTool(productivityService: productivityService))
        registry.register(tool: CreateCalendarEventTool(productivityService: productivityService))

        // System Tools (3)
        registry.register(tool: GetBatteryStatusTool(systemInfoService: systemInfoService))
        registry.register(tool: GetFrontmostApplicationTool(workspaceService: workspaceService))
        registry.register(tool: GetSystemSummaryTool(systemInfoService: systemInfoService))

        // Search Tools (2)
        registry.register(tool: SearchNotesTool(notesService: notesService))
        registry.register(tool: SearchCommandHistoryTool(searchCallback: historySearch))

        // Shortcuts & Automation (1)
        registry.register(tool: RunShortcutTool())

        // Media & Volume (2)
        registry.register(tool: MediaControlTool())
        registry.register(tool: SetVolumeTool())

        // Window Management (1)
        registry.register(tool: WindowManagementTool())

        // System Toggles & Controls (4)
        registry.register(tool: ToggleDarkModeTool())
        registry.register(tool: LockScreenTool())
        registry.register(tool: EmptyTrashTool())
        registry.register(tool: ToggleDNDTool())

        // Clipboard Tools (2)
        registry.register(tool: GetClipboardHistoryTool(clipboardService: clipboardService))
        registry.register(tool: CopyToClipboardTool(clipboardService: clipboardService))

        // Context-Aware & Selection Tools (2)
        registry.register(tool: GetActiveContextTool(contextService: contextService))
        registry.register(tool: PreviewFileTool())

        // Document RAG (1)
        registry.register(tool: SearchLocalDocumentsTool(indexer: documentIndexer))

        // Help & Command Documentation (1)
        registry.register(tool: HelpTool(onPresentHelp: onPresentHelp))

        // Custom User Scripts (~/.config/needlebar/tools/*.json)
        for customTool in CustomScriptToolLoader.shared.loadTools(from: customToolsDirectory) {
            registry.register(tool: customTool)
        }

        return registry
    }
}
