import Foundation
import AppKit

public struct ToggleDarkModeTool: ToolProtocol {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "toggle_dark_mode",
            description: "Toggle macOS Dark Mode appearance or set explicitly to dark or light.",
            parameters: ParametersSchema(
                properties: [
                    "mode": PropertyDefinition(
                        type: "string",
                        description: "Optional target mode: 'dark', 'light', or 'toggle' (default is 'toggle')"
                    )
                ]
            ),
            triggers: ["\\b(dark mode|light mode|appearance|toggle dark|toggle light)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let requestedMode = arguments["mode"]?.stringValue?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "toggle"

        let scriptSource: String
        switch requestedMode {
        case "dark":
            scriptSource = "tell application \"System Events\" to tell appearance preferences to set dark mode to true"
        case "light":
            scriptSource = "tell application \"System Events\" to tell appearance preferences to set dark mode to false"
        default:
            scriptSource = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        }

        let script = NSAppleScript(source: scriptSource)
        var errorDict: NSDictionary?
        script?.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error toggling appearance"
            return .failure(tool: definition.name, error: "Failed to change appearance mode: \(msg)")
        }

        return .success(tool: definition.name, message: "System appearance updated (\(requestedMode)).")
    }
}

public struct LockScreenTool: ToolProtocol {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "lock_screen",
            description: "Lock the macOS screen display immediately.",
            parameters: ParametersSchema(properties: [:]),
            triggers: ["\\b(lock screen|lock mac|lock computer|display sleep)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let libHandle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
        if let lib = libHandle, let sym = dlsym(lib, "SACLockScreenImmediate") {
            typealias SACLockFn = @convention(c) () -> Void
            let lockFn = unsafeBitCast(sym, to: SACLockFn.self)
            lockFn()
            dlclose(lib)
            return .success(tool: definition.name, message: "Locked screen.")
        }

        // Fallback to pmset displaysleepnow
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
            return .success(tool: definition.name, message: "Display put to sleep.")
        } catch {
            return .failure(tool: definition.name, error: "Failed to lock screen: \(error.localizedDescription)")
        }
    }
}

public struct EmptyTrashTool: ToolProtocol {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "empty_trash",
            description: "Empty the macOS Finder trash permanently.",
            parameters: ParametersSchema(properties: [:]),
            triggers: ["\\b(empty trash|clean trash|clear trash|dump trash)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .destructive }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let scriptSource = "tell application \"Finder\" to empty trash"
        let script = NSAppleScript(source: scriptSource)
        var errorDict: NSDictionary?
        script?.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error emptying trash"
            return .failure(tool: definition.name, error: "Failed to empty trash: \(msg)")
        }

        return .success(tool: definition.name, message: "Finder trash emptied.")
    }
}

public struct ToggleDNDTool: ToolProtocol {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "toggle_dnd",
            description: "Toggle Do Not Disturb or Focus mode on macOS.",
            parameters: ParametersSchema(properties: [:]),
            triggers: ["\\b(dnd|do not disturb|toggle focus|focus mode)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        // First check if user has a shortcut for Focus or Do Not Disturb
        let shortcutProcess = Process()
        shortcutProcess.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        shortcutProcess.arguments = ["run", "Do Not Disturb"]
        let pipe = Pipe()
        shortcutProcess.standardError = pipe

        if (try? shortcutProcess.run()) != nil {
            shortcutProcess.waitUntilExit()
            if shortcutProcess.terminationStatus == 0 {
                return .success(tool: definition.name, message: "Toggled Do Not Disturb via Shortcuts.")
            }
        }

        // Alternative: open Focus settings or return status
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")
        if let url = settingsURL {
            NSWorkspace.shared.open(url)
            return .success(tool: definition.name, message: "Opened Focus / Do Not Disturb settings.")
        }

        return .failure(tool: definition.name, error: "Could not toggle Do Not Disturb directly.")
    }
}
