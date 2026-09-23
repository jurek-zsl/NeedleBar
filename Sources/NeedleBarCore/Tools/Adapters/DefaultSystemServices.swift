import Foundation
import AppKit
import EventKit
import IOKit.ps

public final class DefaultWorkspaceService: WorkspaceServiceProtocol, @unchecked Sendable {
    public init() {}

    public func openApplication(named name: String) async throws {
        let appName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchPaths = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            NSHomeDirectory() + "/Applications/\(appName).app"
        ]

        var targetURL: URL?
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                targetURL = url
                break
            }
        }

        if targetURL == nil {
            if let discovered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) {
                targetURL = discovered
            }
        }

        guard let appURL = targetURL else {
            let running = NSWorkspace.shared.runningApplications.first {
                $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
            }
            if let running = running {
                running.activate()
                return
            }

            // Safety Fallback 1: If argument is an obvious URL
            let lowerName = appName.lowercased()
            if lowerName.hasPrefix("http://") || lowerName.hasPrefix("https://") ||
               lowerName.hasPrefix("www.") ||
               [".com", ".org", ".net", ".io", ".app", ".dev", ".edu", ".co", ".ai"].contains(where: { lowerName.hasSuffix($0) }) {
                var urlString = appName
                if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
                    urlString = "https://" + urlString
                }
                if let url = URL(string: urlString) {
                    try await openURL(url)
                    return
                }
            }

            // Safety Fallback 2: If argument is an obvious user folder
            let folderMap: [String: String] = [
                "downloads": NSHomeDirectory() + "/Downloads",
                "documents": NSHomeDirectory() + "/Documents",
                "desktop": NSHomeDirectory() + "/Desktop",
                "movies": NSHomeDirectory() + "/Movies",
                "music": NSHomeDirectory() + "/Music",
                "pictures": NSHomeDirectory() + "/Pictures"
            ]
            if let folderPath = folderMap[lowerName] {
                let url = URL(fileURLWithPath: folderPath)
                try await openFolder(at: url)
                return
            }
            if lowerName.hasPrefix("~/") || lowerName.hasPrefix("/") {
                let expanded = (appName as NSString).expandingTildeInPath
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                    try await openFolder(at: URL(fileURLWithPath: expanded))
                    return
                }
            }

            throw NSError(domain: "NeedleBar", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Application '\(appName)' could not be found in standard application directories."
            ])
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }

    public func quitApplication(named name: String) async throws {
        let appName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.localizedCaseInsensitiveCompare(appName) == .orderedSame ||
            $0.bundleIdentifier?.localizedCaseInsensitiveCompare(appName) == .orderedSame
        }

        guard !runningApps.isEmpty else {
            throw NSError(domain: "NeedleBar", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Application '\(appName)' is not currently running."
            ])
        }

        for app in runningApps {
            app.terminate()
        }
    }

    public func openURL(_ url: URL) async throws {
        let success = NSWorkspace.shared.open(url)
        if !success {
            throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Failed to open URL: \(url.absoluteString)"
            ])
        }
    }

    public func openFolder(at url: URL) async throws {
        let success = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        if !success {
            let openDirect = NSWorkspace.shared.open(url)
            if !openDirect {
                throw NSError(domain: "NeedleBar", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to reveal directory in Finder: \(url.path)"
                ])
            }
        }
    }

    public func getFrontmostApplication() -> (name: String, bundleId: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return (app.localizedName ?? "Unknown", app.bundleIdentifier ?? "unknown")
    }
}

public final class DefaultFileSystemService: FileSystemServiceProtocol, @unchecked Sendable {
    public init() {}

    public func searchFiles(query: String, in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.nameKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        let lowerQuery = query.lowercased()

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.lowercased().contains(lowerQuery) {
                results.append(fileURL)
                if results.count >= 50 { break }
            }
        }

        return results
    }

    public func listRecentFiles(in directory: URL, limit: Int) throws -> [URL] {
        let fileManager = FileManager.default
        let items = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let sorted = items.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return d1 > d2
        }

        return Array(sorted.prefix(max(1, limit)))
    }

    public func createFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func moveFile(from source: URL, to destination: URL) throws {
        var finalDest = destination
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue {
            finalDest = destination.appendingPathComponent(source.lastPathComponent)
        }
        try FileManager.default.moveItem(at: source, to: finalDest)
    }

    public func renameFile(at url: URL, newName: String) throws -> URL {
        let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

public final class DefaultProductivityService: ProductivityServiceProtocol, @unchecked Sendable {
    private let eventStore = EKEventStore()
    private let clockTimerService: any ClockTimerServiceProtocol

    public init() {
        self.clockTimerService = MacOSClockTimerService()
    }

    public func startTimer(durationSeconds: Int, label: String?) async throws {
        try await clockTimerService.startTimer(durationSeconds: durationSeconds, label: label)
        await MainActor.run {
            ActiveTimerTracker.shared.startCountdown(durationSeconds: durationSeconds, label: label)
        }
    }

    public func createReminder(title: String, dueDate: Date?) async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await eventStore.requestFullAccessToReminders()
        } else {
            granted = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { allowed, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: allowed)
                    }
                }
            }
        }

        guard granted else {
            throw NSError(domain: "NeedleBar", code: 403, userInfo: [
                NSLocalizedDescriptionKey: "Reminders permission was denied. Please grant access in System Settings > Privacy & Security > Reminders."
            ])
        }

        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw NSError(domain: "NeedleBar", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No default Reminders list configured."
            ])
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar

        if let dueDate = dueDate {
            let comp = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = comp
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
        }

        try eventStore.save(reminder, commit: true)
    }

    public func createCalendarEvent(title: String, start: Date, end: Date, location: String?) async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await eventStore.requestWriteOnlyAccessToEvents()
        } else {
            granted = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { allowed, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: allowed)
                    }
                }
            }
        }

        guard granted else {
            throw NSError(domain: "NeedleBar", code: 403, userInfo: [
                NSLocalizedDescriptionKey: "Calendar permission was denied. Please grant access in System Settings > Privacy & Security > Calendar."
            ])
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw NSError(domain: "NeedleBar", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No default Calendar configured."
            ])
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.location = location
        event.calendar = calendar

        try eventStore.save(event, span: .thisEvent, commit: true)
    }
}

public final class DefaultSystemInfoService: SystemInfoServiceProtocol, @unchecked Sendable {
    public init() {}

    public func getBatteryStatus() -> (percentage: Int, isCharging: Bool, powerSource: String) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                let current = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
                let max = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
                let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
                let powerSource = desc[kIOPSPowerSourceStateKey as String] as? String ?? "AC Power"
                let percentage = max > 0 ? Int((Double(current) / Double(max)) * 100.0) : current
                return (percentage, isCharging, powerSource)
            }
        }
        return (100, true, "AC Power")
    }

    public func getSystemSummary() -> (osVersion: String, hostName: String, physicalMemory: String, uptime: String) {
        let pInfo = ProcessInfo.processInfo
        let osVersion = pInfo.operatingSystemVersionString
        let hostName = pInfo.hostName
        let memGB = Double(pInfo.physicalMemory) / (1024 * 1024 * 1024)
        let memStr = String(format: "%.1f GB RAM", memGB)

        let uptimeSec = Int(pInfo.systemUptime)
        let hours = uptimeSec / 3600
        let minutes = (uptimeSec % 3600) / 60
        let uptimeStr = "\(hours)h \(minutes)m"

        return (osVersion, hostName, memStr, uptimeStr)
    }
}

public final class DefaultNotesService: NotesServiceProtocol, @unchecked Sendable {
    public init() {}

    public func searchNotes(query: String) async throws -> [String] {
        let cleanQuery = query.replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application "Notes"
            set matchingNotes to every note whose name contains "\(cleanQuery)" or body contains "\(cleanQuery)"
            set noteTitles to {}
            repeat with n in matchingNotes
                copy (name of n) to end of noteTitles
            end repeat
            return noteTitles
        end tell
        """

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            return []
        }

        let result = script.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw NSError(domain: "NeedleBar", code: 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        var titles: [String] = []
        let count = result.numberOfItems
        if count > 0 {
            for i in 1...count {
                if let str = result.atIndex(i)?.stringValue {
                    titles.append(str)
                }
            }
        }
        return titles
    }
}
