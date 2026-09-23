import Foundation
import AppKit
import ApplicationServices

public struct ActiveContextInfo: Codable, Sendable {
    public let appName: String
    public let bundleId: String
    public let windowTitle: String?
    public let selectedText: String?
    public let selectedFiles: [String]?
    public let browserURL: String?
    public let browserTitle: String?

    public init(
        appName: String,
        bundleId: String,
        windowTitle: String? = nil,
        selectedText: String? = nil,
        selectedFiles: [String]? = nil,
        browserURL: String? = nil,
        browserTitle: String? = nil
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.selectedText = selectedText
        self.selectedFiles = selectedFiles
        self.browserURL = browserURL
        self.browserTitle = browserTitle
    }
}

public protocol ContextServiceProtocol: Sendable {
    func getActiveContext() async -> ActiveContextInfo
}

public final class DefaultContextService: ContextServiceProtocol, @unchecked Sendable {
    public init() {}

    public func getActiveContext() async -> ActiveContextInfo {
        let myBundleId = Bundle.main.bundleIdentifier
        let targetApp = (NSWorkspace.shared.frontmostApplication?.bundleIdentifier != myBundleId ? NSWorkspace.shared.frontmostApplication : nil)
            ?? NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular && $0.bundleIdentifier != myBundleId }

        guard let app = targetApp else {
            return ActiveContextInfo(appName: "None", bundleId: "none")
        }

        let appName = app.localizedName ?? "Unknown"
        let bundleId = app.bundleIdentifier ?? "unknown"

        // 1. If Finder, retrieve selected items
        if bundleId == "com.apple.finder" {
            let files = getFinderSelection()
            return ActiveContextInfo(
                appName: appName,
                bundleId: bundleId,
                selectedFiles: files.isEmpty ? nil : files
            )
        }

        // 2. If Safari, retrieve current tab
        if bundleId == "com.apple.Safari" {
            if let tab = getSafariCurrentTab() {
                return ActiveContextInfo(
                    appName: appName,
                    bundleId: bundleId,
                    browserURL: tab.url,
                    browserTitle: tab.title
                )
            }
        }

        // 3. If Chrome / Chromium-based
        if bundleId == "com.google.Chrome" || bundleId == "company.thebrowser.Browser" || bundleId == "com.brave.Browser" {
            if let tab = getChromiumCurrentTab(appName: appName) {
                return ActiveContextInfo(
                    appName: appName,
                    bundleId: bundleId,
                    browserURL: tab.url,
                    browserTitle: tab.title
                )
            }
        }

        // 4. For any other app, attempt to extract highlighted / selected text via Accessibility
        let selectedText = getAXSelectedText(for: app.processIdentifier)
        let windowTitle = getAXWindowTitle(for: app.processIdentifier)

        return ActiveContextInfo(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            selectedText: selectedText
        )
    }

    private func getFinderSelection() -> [String] {
        let scriptSource = """
        tell application "Finder"
            set sel to (selection as alias list)
            set res to {}
            repeat with itemRef in sel
                copy (POSIX path of itemRef) to end of res
            end repeat
            return res
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return [] }
        var errorDict: NSDictionary?
        let desc = script.executeAndReturnError(&errorDict)
        guard errorDict == nil else { return [] }

        var results: [String] = []
        let count = desc.numberOfItems
        if count > 0 {
            for i in 1...count {
                if let str = desc.atIndex(i)?.stringValue {
                    results.append(str)
                }
            }
        }
        return results
    }

    private func getSafariCurrentTab() -> (url: String, title: String)? {
        let scriptSource = """
        tell application "Safari"
            if (count of windows) > 0 then
                tell current tab of front window
                    return (URL as string) & "|||" & (name as string)
                end tell
            end if
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorDict: NSDictionary?
        let desc = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let raw = desc.stringValue else { return nil }

        let parts = raw.components(separatedBy: "|||")
        if parts.count >= 2 {
            return (parts[0], parts[1])
        }
        return (raw, "")
    }

    private func getChromiumCurrentTab(appName: String) -> (url: String, title: String)? {
        let scriptSource = """
        tell application "\(appName)"
            if (count of windows) > 0 then
                tell active tab of front window
                    return (URL as string) & "|||" & (title as string)
                end tell
            end if
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var errorDict: NSDictionary?
        let desc = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let raw = desc.stringValue else { return nil }

        let parts = raw.components(separatedBy: "|||")
        if parts.count >= 2 {
            return (parts[0], parts[1])
        }
        return (raw, "")
    }

    private func getAXSelectedText(for pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        var focusedUIVal: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedUIVal)
        guard status == .success, let focusedElem = focusedUIVal as! AXUIElement? else { return nil }

        var selectedTextVal: CFTypeRef?
        let textStatus = AXUIElementCopyAttributeValue(focusedElem, kAXSelectedTextAttribute as CFString, &selectedTextVal)
        guard textStatus == .success, let str = selectedTextVal as? String, !str.isEmpty else { return nil }
        return str
    }

    private func getAXWindowTitle(for pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        var focusedWinVal: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWinVal)
        guard status == .success, let winElem = focusedWinVal as! AXUIElement? else { return nil }

        var titleVal: CFTypeRef?
        let titleStatus = AXUIElementCopyAttributeValue(winElem, kAXTitleAttribute as CFString, &titleVal)
        guard titleStatus == .success, let str = titleVal as? String, !str.isEmpty else { return nil }
        return str
    }
}
