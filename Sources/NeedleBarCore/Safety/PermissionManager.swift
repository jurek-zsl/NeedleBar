import Foundation
import AppKit
import EventKit

public enum PermissionType: String, CaseIterable, Codable, Sendable {
    case reminders
    case calendar
    case filesAndFolders
    case automation

    public var title: String {
        switch self {
        case .reminders: return "Reminders Access"
        case .calendar: return "Calendar Access"
        case .filesAndFolders: return "Files & Folders"
        case .automation: return "Automation & AppleScript"
        }
    }

    public var reasonDescription: String {
        switch self {
        case .reminders:
            return "NeedleBar needs Reminders access so you can create reminders and to-do items with natural language."
        case .calendar:
            return "NeedleBar needs Calendar access so you can schedule meetings and events directly."
        case .filesAndFolders:
            return "NeedleBar needs file access to search, organize, and reveal documents in your selected folders."
        case .automation:
            return "NeedleBar uses Apple Events to interact with native macOS applications like Apple Notes and System Settings."
        }
    }

    public var settingsURL: URL? {
        switch self {
        case .reminders:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        case .calendar:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .filesAndFolders:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
        case .automation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }
}

public enum PermissionStatus: String, Codable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public final class PermissionManager: @unchecked Sendable {
    public static let shared = PermissionManager()
    private let eventStore = EKEventStore()

    public init() {}

    public func status(for permission: PermissionType) -> PermissionStatus {
        switch permission {
        case .reminders:
            let ekStatus = EKEventStore.authorizationStatus(for: .reminder)
            return mapEKStatus(ekStatus)
        case .calendar:
            let ekStatus = EKEventStore.authorizationStatus(for: .event)
            return mapEKStatus(ekStatus)
        case .filesAndFolders:
            // Standard user folders are readable by default unless restricted by sandbox
            return .authorized
        case .automation:
            return .authorized
        }
    }

    public func requestPermission(for permission: PermissionType) async -> Bool {
        switch permission {
        case .reminders:
            do {
                if #available(macOS 14.0, *) {
                    return try await eventStore.requestFullAccessToReminders()
                } else {
                    return try await withCheckedThrowingContinuation { continuation in
                        eventStore.requestAccess(to: .reminder) { granted, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: granted)
                            }
                        }
                    }
                }
            } catch {
                return false
            }

        case .calendar:
            do {
                if #available(macOS 14.0, *) {
                    return try await eventStore.requestFullAccessToEvents()
                } else {
                    return try await withCheckedThrowingContinuation { continuation in
                        eventStore.requestAccess(to: .event) { granted, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: granted)
                            }
                        }
                    }
                }
            } catch {
                return false
            }

        case .filesAndFolders, .automation:
            return true
        }
    }

    public func openSystemSettings(for permission: PermissionType) {
        if let url = permission.settingsURL {
            NSWorkspace.shared.open(url)
        } else if let generalPrivacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(generalPrivacy)
        }
    }

    private func mapEKStatus(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized, .fullAccess: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .writeOnly: return .authorized
        @unknown default: return .notDetermined
        }
    }
}
