import Foundation
import AppKit

public struct MediaControlTool: ToolProtocol {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "media_control",
            description: "Control audio playback in Apple Music or Spotify (play_pause, next, previous, stop).",
            parameters: ParametersSchema(
                properties: [
                    "action": PropertyDefinition(type: "string", description: "Media playback action: play_pause, next, previous, stop")
                ],
                required: ["action"]
            ),
            triggers: ["\\b(play|pause|music|track|song|next track|previous track|spotify)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let action = arguments["action"]?.stringValue?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "play_pause"

        let isSpotifyRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }
        let appTarget = isSpotifyRunning ? "Spotify" : "Music"

        let scriptText: String
        switch action {
        case "play", "pause", "play_pause", "playpause", "toggle":
            scriptText = "tell application \"\(appTarget)\" to playpause"
        case "next", "next_track", "skip":
            scriptText = "tell application \"\(appTarget)\" to next track"
        case "previous", "prev", "previous_track", "back":
            scriptText = "tell application \"\(appTarget)\" to previous track"
        case "stop":
            scriptText = "tell application \"\(appTarget)\" to pause"
        default:
            scriptText = "tell application \"\(appTarget)\" to playpause"
        }

        let appleScript = NSAppleScript(source: scriptText)
        var errorDict: NSDictionary?
        appleScript?.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            return .failure(tool: definition.name, error: "Media control failed: \(msg)")
        }

        return .success(tool: definition.name, message: "Triggered \(action) in \(appTarget).")
    }
}

public struct SetVolumeTool: ToolProtocol {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "set_volume",
            description: "Set macOS system audio volume level (0 to 100) or toggle mute.",
            parameters: ParametersSchema(
                properties: [
                    "level": PropertyDefinition(type: "integer", description: "Volume level from 0 to 100"),
                    "mute": PropertyDefinition(type: "boolean", description: "Whether to mute (true) or unmute (false) audio")
                ]
            ),
            triggers: ["\\b(volume|mute|unmute|sound level|audio)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let mute = arguments["mute"]?.boolValue
        let level = arguments["level"]?.intValue

        var scriptParts: [String] = []

        if let mute = mute {
            scriptParts.append("set volume output muted \(mute ? "true" : "false")")
        }

        if let level = level {
            let clamped = max(0, min(100, level))
            scriptParts.append("set volume output volume \(clamped)")
        }

        guard !scriptParts.isEmpty else {
            return .failure(tool: definition.name, error: "Provide either 'level' (0-100) or 'mute' argument.")
        }

        let scriptText = scriptParts.joined(separator: "\n")
        let appleScript = NSAppleScript(source: scriptText)
        var errorDict: NSDictionary?
        appleScript?.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error setting volume"
            return .failure(tool: definition.name, error: "Failed to set volume: \(msg)")
        }

        if let level = level {
            return .success(tool: definition.name, message: "Set system volume to \(level)%.")
        } else if let mute = mute {
            return .success(tool: definition.name, message: mute ? "Muted system audio." : "Unmuted system audio.")
        }

        return .success(tool: definition.name, message: "Updated audio volume settings.")
    }
}
