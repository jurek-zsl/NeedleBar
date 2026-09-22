import Foundation

public protocol WorkspaceServiceProtocol: Sendable {
    func openApplication(named name: String) async throws
    func quitApplication(named name: String) async throws
    func openURL(_ url: URL) async throws
    func openFolder(at url: URL) async throws
    func getFrontmostApplication() -> (name: String, bundleId: String)?
}

public protocol FileSystemServiceProtocol: Sendable {
    func searchFiles(query: String, in directory: URL) throws -> [URL]
    func listRecentFiles(in directory: URL, limit: Int) throws -> [URL]
    func createFolder(at url: URL) throws
    func moveFile(from source: URL, to destination: URL) throws
    func renameFile(at url: URL, newName: String) throws -> URL
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
}

public protocol ProductivityServiceProtocol: Sendable {
    func startTimer(minutes: Int, label: String?) async throws
    func createReminder(title: String, dueDate: Date?) async throws
    func createCalendarEvent(title: String, start: Date, end: Date, location: String?) async throws
}

public protocol SystemInfoServiceProtocol: Sendable {
    func getBatteryStatus() -> (percentage: Int, isCharging: Bool, powerSource: String)
    func getSystemSummary() -> (osVersion: String, hostName: String, physicalMemory: String, uptime: String)
}

public protocol NotesServiceProtocol: Sendable {
    func searchNotes(query: String) async throws -> [String]
}
