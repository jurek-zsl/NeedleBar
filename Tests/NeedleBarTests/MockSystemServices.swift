import Foundation
import NeedleBarCore

public final class MockWorkspaceService: WorkspaceServiceProtocol, @unchecked Sendable {
    public var openedApps: [String] = []
    public var quitApps: [String] = []
    public var openedURLs: [URL] = []
    public var openedFolders: [URL] = []
    public var frontmostApp: (name: String, bundleId: String)? = ("Safari", "com.apple.Safari")
    public var shouldThrowError: Error?

    public init() {}

    public func openApplication(named name: String) async throws {
        if let err = shouldThrowError { throw err }
        openedApps.append(name)
    }

    public func quitApplication(named name: String) async throws {
        if let err = shouldThrowError { throw err }
        quitApps.append(name)
    }

    public func openURL(_ url: URL) async throws {
        if let err = shouldThrowError { throw err }
        openedURLs.append(url)
    }

    public func openFolder(at url: URL) async throws {
        if let err = shouldThrowError { throw err }
        openedFolders.append(url)
    }

    public func getFrontmostApplication() -> (name: String, bundleId: String)? {
        frontmostApp
    }
}

public final class MockFileSystemService: FileSystemServiceProtocol, @unchecked Sendable {
    public var existingFiles: Set<String> = []
    public var movedFiles: [(from: URL, to: URL)] = []
    public var renamedFiles: [(at: URL, newName: String)] = []
    public var createdFolders: [URL] = []
    public var shouldThrowError: Error?

    public init() {}

    public func searchFiles(query: String, in directory: URL) throws -> [URL] {
        if let err = shouldThrowError { throw err }
        return existingFiles
            .filter { $0.lowercased().contains(query.lowercased()) }
            .map { URL(fileURLWithPath: $0) }
    }

    public func listRecentFiles(in directory: URL, limit: Int) throws -> [URL] {
        if let err = shouldThrowError { throw err }
        return Array(existingFiles.prefix(limit)).map { URL(fileURLWithPath: $0) }
    }

    public func createFolder(at url: URL) throws {
        if let err = shouldThrowError { throw err }
        createdFolders.append(url)
        existingFiles.insert(url.path)
    }

    public func moveFile(from source: URL, to destination: URL) throws {
        if let err = shouldThrowError { throw err }
        movedFiles.append((source, destination))
        existingFiles.remove(source.path)
        existingFiles.insert(destination.path)
    }

    public func renameFile(at url: URL, newName: String) throws -> URL {
        if let err = shouldThrowError { throw err }
        renamedFiles.append((url, newName))
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        existingFiles.remove(url.path)
        existingFiles.insert(newURL.path)
        return newURL
    }

    public func fileExists(at url: URL) -> Bool {
        existingFiles.contains(url.path)
    }

    public func isDirectory(at url: URL) -> Bool {
        false
    }
}

public final class MockProductivityService: ProductivityServiceProtocol, @unchecked Sendable {
    public var startedTimers: [(durationSeconds: Int, label: String?)] = []
    public var createdReminders: [(title: String, dueDate: Date?)] = []
    public var createdEvents: [(title: String, start: Date, end: Date, location: String?)] = []
    public var shouldThrowError: Error?

    public init() {}

    public func startTimer(durationSeconds: Int, label: String?) async throws {
        if let err = shouldThrowError { throw err }
        startedTimers.append((durationSeconds, label))
    }

    public func createReminder(title: String, dueDate: Date?) async throws {
        if let err = shouldThrowError { throw err }
        createdReminders.append((title, dueDate))
    }

    public func createCalendarEvent(title: String, start: Date, end: Date, location: String?) async throws {
        if let err = shouldThrowError { throw err }
        createdEvents.append((title, start, end, location))
    }
}

public final class MockSystemInfoService: SystemInfoServiceProtocol, @unchecked Sendable {
    public var batteryStatus: (percentage: Int, isCharging: Bool, powerSource: String) = (88, true, "AC Power")
    public var systemSummary: (osVersion: String, hostName: String, physicalMemory: String, uptime: String) = (
        "macOS 15.0", "MacBook-Pro.local", "32.0 GB RAM", "4h 12m"
    )

    public init() {}

    public func getBatteryStatus() -> (percentage: Int, isCharging: Bool, powerSource: String) {
        batteryStatus
    }

    public func getSystemSummary() -> (osVersion: String, hostName: String, physicalMemory: String, uptime: String) {
        systemSummary
    }
}

public final class MockNotesService: NotesServiceProtocol, @unchecked Sendable {
    public var notesToReturn: [String] = ["Deployment Checklist", "Project Needle Plan"]
    public var shouldThrowError: Error?

    public init() {}

    public func searchNotes(query: String) async throws -> [String] {
        if let err = shouldThrowError { throw err }
        return notesToReturn.filter { $0.lowercased().contains(query.lowercased()) }
    }
}
