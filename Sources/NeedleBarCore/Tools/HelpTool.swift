import Foundation

public struct HelpTool: ToolProtocol {
    public let onPresentHelp: (@Sendable () -> Void)?

    public init(onPresentHelp: (@Sendable () -> Void)? = nil) {
        self.onPresentHelp = onPresentHelp
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "show_help",
            description: "Shows help, command documentation, and interactive examples of what NeedleBar can do.",
            parameters: ParametersSchema(
                properties: [
                    "category": PropertyDefinition(
                        type: "string",
                        description: "Optional category to filter help for: 'all', 'system', 'apps', 'productivity', 'windows', 'files', 'clipboard', 'shortcuts', or 'multistep'"
                    )
                ]
            ),
            triggers: [
                "\\b(help|commands|what can you do|what can i ask|how to use|usage guide|examples)\\b"
            ]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let requestedCategory = arguments["category"]?.stringValue?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "all"

        onPresentHelp?()

        let categoriesToInclude: [CapabilityCategory]
        if requestedCategory == "all" || requestedCategory.isEmpty {
            categoriesToInclude = CapabilityCategory.allCases.filter { $0 != .all }
        } else {
            categoriesToInclude = CapabilityCategory.allCases.filter {
                $0.rawValue.lowercased().contains(requestedCategory) ||
                $0.id.lowercased().contains(requestedCategory)
            }
        }

        var lines: [String] = [
            "NeedleBar Capabilities & Examples Guide:",
            "Type any query or click an example to run it immediately.",
            ""
        ]

        let capabilities = HelpCatalog.allCapabilities
        for cat in categoriesToInclude {
            let items = capabilities.filter { $0.category == cat }
            guard !items.isEmpty else { continue }

            lines.append("## \(cat.rawValue)")
            for item in items {
                lines.append("• \(item.title): \(item.description)")
                let egStr = item.examples.map { "\"\"\($0)\"\"" }.joined(separator: ", ")
                lines.append("  Examples: \(egStr)")
            }
            lines.append("")
        }

        return .success(
            tool: definition.name,
            message: lines.joined(separator: "\n"),
            data: ["categories_count": AnyCodable(categoriesToInclude.count)]
        )
    }
}

// MARK: - Capabilities Catalog Data Model

public enum CapabilityCategory: String, CaseIterable, Identifiable, Sendable {
    public var id: String { rawValue }
    case all = "All"
    case system = "System & Audio"
    case apps = "Apps & Web"
    case productivity = "Productivity & Timers"
    case windows = "Window Tiling"
    case files = "Files & Search"
    case clipboard = "Clipboard & Context"
    case shortcuts = "Shortcuts & Plugins"
    case multistep = "Chained Actions"
}

public struct CapabilityItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let icon: String
    public let category: CapabilityCategory
    public let examples: [String]

    public init(
        id: String,
        title: String,
        description: String,
        icon: String,
        category: CapabilityCategory,
        examples: [String]
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.icon = icon
        self.category = category
        self.examples = examples
    }
}

public enum HelpCatalog {
    public static let allCapabilities: [CapabilityItem] = [
        // 1. System & Audio
        CapabilityItem(
            id: "volume",
            title: "Volume & Mute Control",
            description: "Set system audio volume level (0-100%) or toggle mute instantly.",
            icon: "speaker.wave.2.fill",
            category: .system,
            examples: ["set volume to 50%", "mute audio", "unmute volume", "turn volume up to 80%"]
        ),
        CapabilityItem(
            id: "media",
            title: "Music & Media Playback",
            description: "Control playback in Apple Music or Spotify without leaving your workflow.",
            icon: "play.circle.fill",
            category: .system,
            examples: ["play music", "pause music", "next track", "previous track"]
        ),
        CapabilityItem(
            id: "appearance",
            title: "Dark Mode & Appearance",
            description: "Switch macOS appearance between Dark Mode and Light Mode.",
            icon: "moon.stars.fill",
            category: .system,
            examples: ["toggle dark mode", "turn on dark mode", "set light mode"]
        ),
        CapabilityItem(
            id: "lock_dnd",
            title: "Lock Screen & Focus",
            description: "Instantly lock your Mac or toggle Do Not Disturb / Focus state.",
            icon: "lock.shield.fill",
            category: .system,
            examples: ["lock screen", "toggle dnd", "turn on focus mode"]
        ),
        CapabilityItem(
            id: "system_info",
            title: "Battery & System Diagnostics",
            description: "Check battery percentage, power status, CPU and memory usage.",
            icon: "battery.100.bolt",
            category: .system,
            examples: ["What is my battery status?", "Show system summary", "check battery level"]
        ),
        CapabilityItem(
            id: "trash",
            title: "Empty Trash",
            description: "Safely purge Trash in Finder with built-in confirmation protection.",
            icon: "trash.fill",
            category: .system,
            examples: ["empty trash"]
        ),

        // 2. Apps & Web
        CapabilityItem(
            id: "open_apps",
            title: "Open Applications",
            description: "Launch or switch to any installed application by name.",
            icon: "app.fill",
            category: .apps,
            examples: ["Open Safari", "Open Slack", "Open Notes", "Open Terminal"]
        ),
        CapabilityItem(
            id: "quit_apps",
            title: "Quit Applications",
            description: "Safely quit running applications.",
            icon: "xmark.app.fill",
            category: .apps,
            examples: ["Quit Music", "Close Slack", "Quit Safari"]
        ),
        CapabilityItem(
            id: "open_urls",
            title: "Web Browsing & URLs",
            description: "Open websites in your default browser or target specific browsers.",
            icon: "safari.fill",
            category: .apps,
            examples: ["Open https://github.com", "Open youtube.com in Safari", "Open news.ycombinator.com"]
        ),
        CapabilityItem(
            id: "open_folders",
            title: "Folder Navigation",
            description: "Reveal any folder on your Mac directly in Finder.",
            icon: "folder.fill",
            category: .apps,
            examples: ["Open ~/Downloads", "Open Documents folder", "Open Desktop"]
        ),

        // 3. Productivity & Timers
        CapabilityItem(
            id: "timers",
            title: "Active Countdown Timers",
            description: "Start countdown timers with a live menu bar ticker and completion chime.",
            icon: "timer",
            category: .productivity,
            examples: ["start timer 5 min", "start a 25 minute timer for Focus session", "start timer 90 seconds"]
        ),
        CapabilityItem(
            id: "reminders",
            title: "Apple Reminders",
            description: "Create reminders with titles and due dates in Apple Reminders.",
            icon: "checklist",
            category: .productivity,
            examples: ["Create reminder Buy milk tomorrow", "remind me to call Mom at 6pm", "Create reminder Review pull request"]
        ),
        CapabilityItem(
            id: "calendar",
            title: "Calendar Events",
            description: "Schedule events and meetings in Apple Calendar.",
            icon: "calendar",
            category: .productivity,
            examples: ["Create calendar event Team Standup tomorrow at 10am", "schedule event Design Review on Friday at 2pm"]
        ),
        CapabilityItem(
            id: "notes",
            title: "Search Notes",
            description: "Search Apple Notes by keyword.",
            icon: "note.text",
            category: .productivity,
            examples: ["search notes meeting agenda", "search notes grocery list"]
        ),

        // 4. Window Management
        CapabilityItem(
            id: "window_tiling",
            title: "Window Tiling & Snapping",
            description: "Snap and reposition the active window without third-party utilities.",
            icon: "macwindow.on.rectangle",
            category: .windows,
            examples: ["tile window left", "tile window right", "maximize window", "center window", "minimize window"]
        ),

        // 5. Files & Knowledge Search
        CapabilityItem(
            id: "search_files",
            title: "Spotlight File Search",
            description: "Locate files, documents, and archives across your system.",
            icon: "magnifyingglass",
            category: .files,
            examples: ["search files invoice.pdf", "find report.docx", "search files budget"]
        ),
        CapabilityItem(
            id: "recent_files",
            title: "Recent Files & Documents",
            description: "List recently accessed or modified files.",
            icon: "clock.arrow.circlepath",
            category: .files,
            examples: ["list recent files"]
        ),
        CapabilityItem(
            id: "preview_files",
            title: "Quick Look Preview",
            description: "Open native macOS Quick Look previews for any file.",
            icon: "eye.fill",
            category: .files,
            examples: ["preview document report.pdf", "preview image screenshot.png"]
        ),
        CapabilityItem(
            id: "rag_documents",
            title: "Semantic Document Search (RAG)",
            description: "AI-powered semantic search inside your local PDFs, Markdown, and notes in ~/Documents.",
            icon: "doc.text.magnifyingglass",
            category: .files,
            examples: ["search documents quarterly goals", "search documents meeting takeaways", "search documents architecture"]
        ),
        CapabilityItem(
            id: "file_operations",
            title: "File Organization",
            description: "Safely move or rename files on your disk.",
            icon: "folder.badge.gearshape",
            category: .files,
            examples: ["move file draft.txt to Documents", "rename old.txt to final.txt"]
        ),

        // 6. Clipboard & Context
        CapabilityItem(
            id: "clipboard",
            title: "Clipboard & Pasteboard",
            description: "Copy text to clipboard or inspect recent clipboard history items.",
            icon: "doc.on.clipboard.fill",
            category: .clipboard,
            examples: ["copy Hello World to clipboard", "show clipboard history"]
        ),
        CapabilityItem(
            id: "active_context",
            title: "Active Screen & Browser Context",
            description: "Inspect the frontmost window: active browser URL, highlighted text, or Finder selection.",
            icon: "sparkle.magnifyingglass",
            category: .clipboard,
            examples: ["What am I looking at?", "summarize this page", "what is selected?"]
        ),

        // 7. Shortcuts & Extensibility
        CapabilityItem(
            id: "shortcuts",
            title: "Apple Shortcuts",
            description: "Trigger any Apple Shortcut automation by name with optional input.",
            icon: "square.stack.3d.up.fill",
            category: .shortcuts,
            examples: ["run shortcut Morning Routine", "run shortcut Convert Image to PNG"]
        ),
        CapabilityItem(
            id: "custom_plugins",
            title: "Custom User Scripts & MCP",
            description: "Run custom user scripts from ~/.config/needlebar/tools or connect MCP servers.",
            icon: "puzzlepiece.extension.fill",
            category: .shortcuts,
            examples: ["run custom script", "check available tools"]
        ),

        // 8. Chained Actions
        CapabilityItem(
            id: "chained_actions",
            title: "Sequential & Chained Commands",
            description: "Chain multiple independent actions using 'then', 'and then', or commas.",
            icon: "arrow.triangle.swap",
            category: .multistep,
            examples: [
                "Open Safari, then set volume to 40%",
                "mute audio and lock screen",
                "start timer 25 min and toggle dark mode"
            ]
        )
    ]
}
