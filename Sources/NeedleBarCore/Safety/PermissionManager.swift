import AppKit
import ApplicationServices
import CoreServices
import EventKit
import Foundation

public enum PermissionType: String, CaseIterable, Codable, Sendable {
    case accessibility
    case reminders
    case calendar
    case notesAutomation

    public var title: String {
        switch self {
        case .accessibility: return "Control Clock"
        case .reminders: return "Create reminders"
        case .calendar: return "Create calendar events"
        case .notesAutomation: return "Search Apple Notes"
        }
    }

    public var reasonDescription: String {
        switch self {
        case .accessibility:
            return "Used only to enter and start timers in the macOS Clock app."
        case .reminders:
            return "Used only when you ask NeedleBar to add an item to Reminders."
        case .calendar:
            return "Used only when you ask NeedleBar to create a Calendar event."
        case .notesAutomation:
            return "Used only to search note titles and contents in Apple Notes."
        }
    }

    public var systemImage: String {
        switch self {
        case .accessibility: return "timer"
        case .reminders: return "checklist"
        case .calendar: return "calendar"
        case .notesAutomation: return "note.text"
        }
    }

    public var settingsURL: URL? {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .reminders:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        case .calendar:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .notesAutomation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }
}

public enum PermissionStatus: String, Codable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    public var isAuthorized: Bool { self == .authorized }
}

public final class PermissionManager: @unchecked Sendable {
    public static let shared = PermissionManager()

    private enum DefaultsKey {
        static let accessibilityRequestAttempted = "NeedleBar.permission.accessibility.requestAttempted"
        static let notesRequestAttempted = "NeedleBar.permission.notes.requestAttempted"
        static let notesWasAuthorized = "NeedleBar.permission.notes.wasAuthorized"
    }

    private static let notesBundleIdentifier = "com.apple.Notes"

    private let eventStore: EKEventStore
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.eventStore = EKEventStore()
    }

    public func status(for permission: PermissionType) -> PermissionStatus {
        switch permission {
        case .accessibility:
            if AXIsProcessTrusted() { return .authorized }
            return defaults.bool(forKey: DefaultsKey.accessibilityRequestAttempted) ? .denied : .notDetermined

        case .reminders:
            return mapEKStatus(EKEventStore.authorizationStatus(for: .reminder))

        case .calendar:
            return mapEKStatus(EKEventStore.authorizationStatus(for: .event))

        case .notesAutomation:
            return notesAutomationStatus(askUserIfNeeded: false)
        }
    }

    /// Requests access using the native API for the selected capability.
    public func requestPermission(for permission: PermissionType) async -> Bool {
        switch permission {
        case .accessibility:
            defaults.set(true, forKey: DefaultsKey.accessibilityRequestAttempted)
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            try? await Task.sleep(for: .milliseconds(350))
            return AXIsProcessTrusted()

        case .reminders:
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                return false
            }

        case .calendar:
            do {
                return try await eventStore.requestWriteOnlyAccessToEvents()
            } catch {
                return false
            }

        case .notesAutomation:
            return await requestNotesAutomationPermission()
        }
    }

    public func openSystemSettings(for permission: PermissionType) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestNotesAutomationPermission() async -> Bool {
        defaults.set(true, forKey: DefaultsKey.notesRequestAttempted)

        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == Self.notesBundleIdentifier
        }) == false,
           let notesURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.notesBundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: notesURL, configuration: configuration)
        }

        let granted = notesAutomationStatus(askUserIfNeeded: true) == .authorized
        defaults.set(granted, forKey: DefaultsKey.notesWasAuthorized)
        return granted
    }

    private func notesAutomationStatus(askUserIfNeeded: Bool) -> PermissionStatus {
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == Self.notesBundleIdentifier
        }) else {
            if defaults.bool(forKey: DefaultsKey.notesWasAuthorized) {
                return .authorized
            }
            return defaults.bool(forKey: DefaultsKey.notesRequestAttempted) ? .denied : .notDetermined
        }

        var target = AEAddressDesc()
        let bundleIdentifier = Self.notesBundleIdentifier
        let createStatus = bundleIdentifier.withCString { pointer in
            AECreateDesc(
                typeApplicationBundleID,
                pointer,
                bundleIdentifier.lengthOfBytes(using: .utf8),
                &target
            )
        }
        guard createStatus == noErr else { return .restricted }
        defer { AEDisposeDesc(&target) }

        let result = AEDeterminePermissionToAutomateTarget(
            &target,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )

        switch result {
        case noErr:
            return .authorized
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .restricted
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
