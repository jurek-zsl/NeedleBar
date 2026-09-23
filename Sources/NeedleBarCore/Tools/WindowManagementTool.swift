import Foundation
import AppKit
import ApplicationServices

public struct WindowManagementTool: ToolProtocol {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            name: "manage_window",
            description: "Manage window position and size for the active application (left_half, right_half, top_half, bottom_half, maximize, center, minimize).",
            parameters: ParametersSchema(
                properties: [
                    "action": PropertyDefinition(
                        type: "string",
                        description: "Window layout action: left_half, right_half, top_half, bottom_half, maximize, center, minimize"
                    )
                ],
                required: ["action"]
            ),
            triggers: ["\\b(tile|snap|window|maximize|minimize|center window|left half|right half|top half|bottom half)\\b"]
        )
    }

    public var riskLevel: RiskLevel { .safe }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let rawAction = arguments["action"]?.stringValue?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "maximize"

        if !AXIsProcessTrusted() {
            return .failure(
                tool: definition.name,
                error: "Accessibility permission is required for window management. Please enable NeedleBar in System Settings > Privacy & Security > Accessibility."
            )
        }

        let myBundleId = Bundle.main.bundleIdentifier
        let targetApp = (NSWorkspace.shared.frontmostApplication?.bundleIdentifier != myBundleId ? NSWorkspace.shared.frontmostApplication : nil)
            ?? NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular && $0.bundleIdentifier != myBundleId }

        guard let app = targetApp else {
            return .failure(tool: definition.name, error: "No active application found to manage.")
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowVal: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowVal)
        if result != .success || focusedWindowVal == nil {
            result = AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &focusedWindowVal)
        }

        guard let windowRef = focusedWindowVal as! AXUIElement? else {
            return .failure(tool: definition.name, error: "Could not find an active window for \(app.localizedName ?? "frontmost app").")
        }

        if rawAction == "minimize" {
            let err = AXUIElementSetAttributeValue(windowRef, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            if err == .success {
                return .success(tool: definition.name, message: "Minimized window for \(app.localizedName ?? "app").")
            } else {
                return .failure(tool: definition.name, error: "Failed to minimize window.")
            }
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return .failure(tool: definition.name, error: "No screen detected.")
        }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height

        let screenLeft = visibleFrame.origin.x
        let screenTop = primaryHeight - (visibleFrame.origin.y + visibleFrame.height)
        let screenWidth = visibleFrame.width
        let screenHeight = visibleFrame.height

        var targetX: CGFloat = screenLeft
        var targetY: CGFloat = screenTop
        var targetW: CGFloat = screenWidth
        var targetH: CGFloat = screenHeight

        switch rawAction {
        case "left_half", "left", "tile_left":
            targetW = screenWidth / 2.0
        case "right_half", "right", "tile_right":
            targetX = screenLeft + screenWidth / 2.0
            targetW = screenWidth / 2.0
        case "top_half", "top", "tile_top":
            targetH = screenHeight / 2.0
        case "bottom_half", "bottom", "tile_bottom":
            targetY = screenTop + screenHeight / 2.0
            targetH = screenHeight / 2.0
        case "center":
            targetW = screenWidth * 0.75
            targetH = screenHeight * 0.8
            targetX = screenLeft + (screenWidth - targetW) / 2.0
            targetY = screenTop + (screenHeight - targetH) / 2.0
        case "maximize", "full", "fullscreen", "fill", "max":
            targetW = screenWidth
            targetH = screenHeight
        default:
            targetW = screenWidth
            targetH = screenHeight
        }

        var newPos = CGPoint(x: targetX, y: targetY)
        var newSize = CGSize(width: targetW, height: targetH)

        if let posVal = AXValueCreate(.cgPoint, &newPos) {
            AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &newSize) {
            AXUIElementSetAttributeValue(windowRef, kAXSizeAttribute as CFString, sizeVal)
        }
        if let posVal = AXValueCreate(.cgPoint, &newPos) {
            AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute as CFString, posVal)
        }

        return .success(
            tool: definition.name,
            message: "Applied '\(rawAction)' layout to \(app.localizedName ?? "frontmost window")."
        )
    }
}
