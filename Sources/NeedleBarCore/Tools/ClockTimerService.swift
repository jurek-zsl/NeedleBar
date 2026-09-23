import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

protocol ClockTimerServiceProtocol: Sendable {
    func startTimer(durationSeconds: Int, label: String?) async throws
}

struct TimerDuration: Equatable, Sendable {
    static let maximumSeconds = (23 * 60 * 60) + (59 * 60) + 59

    let totalSeconds: Int

    init(totalSeconds: Int) throws {
        guard (1...Self.maximumSeconds).contains(totalSeconds) else {
            throw ClockTimerError.invalidDuration
        }
        self.totalSeconds = totalSeconds
    }

    var hours: Int { totalSeconds / 3_600 }
    var minutes: Int { (totalSeconds % 3_600) / 60 }
    var seconds: Int { totalSeconds % 60 }

    var displayText: String {
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if seconds > 0 { parts.append("\(seconds) second\(seconds == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }
}

enum ClockTimerError: LocalizedError, Equatable {
    case invalidDuration
    case accessibilityPermissionRequired
    case clockUnavailable
    case clockWindowUnavailable
    case timerTabUnavailable
    case timerEditorUnavailable
    case timerControlsUnavailable
    case couldNotSetDuration(component: String)
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Timer duration must be between 1 second and 23 hours, 59 minutes, 59 seconds."
        case .accessibilityPermissionRequired:
            return "NeedleBar needs Accessibility access to control the macOS Clock app. If NeedleBar is already enabled, remove the old entry, add this copy again, relaunch NeedleBar, and retry."
        case .clockUnavailable:
            return "The macOS Clock app could not be opened."
        case .clockWindowUnavailable:
            return "The macOS Clock window did not become available."
        case .timerTabUnavailable:
            return "NeedleBar could not open the Timers tab in Clock."
        case .timerEditorUnavailable:
            return "NeedleBar could not open Clock's new timer controls."
        case .timerControlsUnavailable:
            return "NeedleBar could not find Clock's hour, minute, and second controls."
        case .couldNotSetDuration(let component):
            return "NeedleBar could not set the timer's \(component) value in Clock."
        case .couldNotStart:
            return "Clock did not start the timer. Please try again."
        }
    }
}

/// Starts timers in Apple's Clock app by driving its accessible, keyboard-based
/// duration picker. Clock does not expose an AppleScript timer API on macOS.
final class MacOSClockTimerService: ClockTimerServiceProtocol, @unchecked Sendable {
    private static let clockBundleIdentifier = "com.apple.clock"

    func startTimer(durationSeconds: Int, label: String?) async throws {
        let duration = try TimerDuration(totalSeconds: durationSeconds)
        try requireAccessibilityPermission()

        let clockApp = try await openClock()
        clockApp.activate()

        let applicationElement = AXUIElementCreateApplication(clockApp.processIdentifier)
        let window = try await waitForWindow(in: applicationElement)
        try await openTimersTab(in: window)

        let editor = try await openTimerEditorIfNeeded(in: window)
        let sliders = children(of: editor).filter { role(of: $0) == kAXSliderRole as String }
        guard sliders.count >= 3 else {
            throw ClockTimerError.timerControlsUnavailable
        }

        let values = [duration.hours, duration.minutes, duration.seconds]
        let names = ["hour", "minute", "second"]
        for index in values.indices {
            try await enter(values[index], in: sliders[index], component: names[index], pid: clockApp.processIdentifier)
        }

        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let labelField = elements(in: window).first(where: { role(of: $0) == kAXTextFieldRole as String }) {
            let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = AXUIElementSetAttributeValue(labelField, kAXValueAttribute as CFString, trimmedLabel as CFString)
        }

        guard let startButton = elements(in: window).first(where: {
            identifier(of: $0) == "PauseResumeButton" && role(of: $0) == kAXButtonRole as String
        }) else {
            throw ClockTimerError.couldNotStart
        }

        let startButtonDescription = description(of: startButton)
        guard AXUIElementPerformAction(startButton, kAXPressAction as CFString) == .success else {
            throw ClockTimerError.couldNotStart
        }

        try await verifyTimerStarted(
            in: window,
            originalStartButton: startButton,
            originalDescription: startButtonDescription
        )
    }

    private func requireAccessibilityPermission() throws {
        // The SDK imports this constant as mutable global state, which Swift 6
        // rejects from Sendable code. Its documented CFString value is stable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw ClockTimerError.accessibilityPermissionRequired
        }
    }

    private func openClock() async throws -> NSRunningApplication {
        guard let clockURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.clockBundleIdentifier) else {
            throw ClockTimerError.clockUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            return try await NSWorkspace.shared.openApplication(at: clockURL, configuration: configuration)
        } catch {
            throw ClockTimerError.clockUnavailable
        }
    }

    private func waitForWindow(in application: AXUIElement) async throws -> AXUIElement {
        for _ in 0..<30 {
            if let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] {
                // Clock can expose a small private auxiliary window before its
                // actual SceneWindow. Selecting `windows.first` makes the
                // timer toolbar and editor appear to be missing.
                if let sceneWindow = windows.first(where: {
                    identifier(of: $0) == "SceneWindow"
                }) {
                    return sceneWindow
                }

                if let contentWindow = windows.first(where: { candidate in
                    elements(in: candidate).contains(where: {
                        role(of: $0) == kAXToolbarRole as String ||
                            identifier(of: $0) == "TimePicker"
                    })
                }) {
                    return contentWindow
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ClockTimerError.clockWindowUnavailable
    }

    private func openTimersTab(in window: AXUIElement) async throws {
        // If Clock is already showing its timer editor/list, do not rely on
        // the selected-state representation of the toolbar radio button.
        // That value differs between AppKit and newer SwiftUI Clock builds.
        if hasTimerInterface(in: window) {
            return
        }

        let radioButtons = elements(in: window).filter { role(of: $0) == kAXRadioButtonRole as String }
        let timerTab = radioButtons.first(where: {
            description(of: $0).localizedCaseInsensitiveContains("timer")
        }) ?? (radioButtons.count >= 4 ? radioButtons[3] : nil)

        guard let timerTab else {
            throw ClockTimerError.timerTabUnavailable
        }

        if integerValue(of: timerTab) != 1 {
            guard AXUIElementPerformAction(timerTab, kAXPressAction as CFString) == .success else {
                throw ClockTimerError.timerTabUnavailable
            }
        }

        for _ in 0..<20 {
            if hasTimerInterface(in: window) {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ClockTimerError.timerTabUnavailable
    }

    private func hasTimerInterface(in window: AXUIElement) -> Bool {
        let currentElements = elements(in: window)
        return currentElements.contains(where: { identifier(of: $0) == "TimePicker" }) ||
            currentElements.contains(where: {
                role(of: $0) == kAXMenuButtonRole as String &&
                    description(of: $0).localizedCaseInsensitiveContains("add")
            })
    }

    private func openTimerEditorIfNeeded(in window: AXUIElement) async throws -> AXUIElement {
        if let picker = elements(in: window).first(where: { identifier(of: $0) == "TimePicker" }) {
            return picker
        }

        // Modern Clock supports multiple concurrent timers. Open the add editor
        // instead of cancelling a timer that is already running.
        guard let addButton = elements(in: window).first(where: {
            role(of: $0) == kAXMenuButtonRole as String
        }), AXUIElementPerformAction(addButton, kAXPressAction as CFString) == .success else {
            throw ClockTimerError.timerEditorUnavailable
        }

        for _ in 0..<20 {
            if let picker = elements(in: window).first(where: { identifier(of: $0) == "TimePicker" }) {
                return picker
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ClockTimerError.timerEditorUnavailable
    }

    private func enter(
        _ value: Int,
        in slider: AXUIElement,
        component: String,
        pid: pid_t
    ) async throws {
        // Clock exposes each duration wheel as a settable AX slider. Setting
        // AXValue directly is both more reliable and less disruptive than
        // synthesizing keyboard input, especially on newer SwiftUI builds of
        // Clock where the wheels no longer accept typed digits.
        let setStatus = AXUIElementSetAttributeValue(
            slider,
            kAXValueAttribute as CFString,
            NSNumber(value: value)
        )
        if setStatus == .success, await waitForValue(value, in: slider) {
            return
        }

        // Some macOS releases expose the slider as settable but reject a
        // direct AXValue write. In that case, walk from its current value with
        // the standard accessibility actions before falling back to typing.
        if var currentValue = integerValue(of: slider), currentValue != value {
            let isIncrementing = currentValue < value
            let action = isIncrementing ? kAXIncrementAction : kAXDecrementAction
            let step = isIncrementing ? 1 : -1

            while currentValue != value {
                guard AXUIElementPerformAction(slider, action as CFString) == .success else {
                    break
                }

                let expectedValue = currentValue + step
                if await waitForValue(expectedValue, in: slider) {
                    currentValue = expectedValue
                } else if let observedValue = integerValue(of: slider), observedValue != currentValue {
                    currentValue = observedValue
                } else {
                    break
                }
            }

            if currentValue == value {
                return
            }
            if await waitForValue(value, in: slider) {
                return
            }
        }

        guard let point = center(of: slider) else {
            throw ClockTimerError.couldNotSetDuration(component: component)
        }

        postMouseClick(at: point)
        try await Task.sleep(for: .milliseconds(80))

        for character in String(value) {
            guard let keyCode = keyCode(for: character) else {
                throw ClockTimerError.couldNotSetDuration(component: component)
            }
            postKey(keyCode, to: pid)
            try await Task.sleep(for: .milliseconds(35))
        }

        try await Task.sleep(for: .milliseconds(80))
        guard integerValue(of: slider) == value else {
            throw ClockTimerError.couldNotSetDuration(component: component)
        }
    }

    private func waitForValue(_ expectedValue: Int, in slider: AXUIElement) async -> Bool {
        for _ in 0..<10 {
            if integerValue(of: slider) == expectedValue {
                return true
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }

    private func verifyTimerStarted(
        in window: AXUIElement,
        originalStartButton: AXUIElement,
        originalDescription: String
    ) async throws {
        for _ in 0..<20 {
            if identifier(of: originalStartButton) != "PauseResumeButton" ||
                description(of: originalStartButton) != originalDescription ||
                !elements(in: window).contains(where: { identifier(of: $0) == "TimePicker" }) {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ClockTimerError.couldNotStart
    }

    private func elements(in root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var pending: [AXUIElement] = [root]

        while !pending.isEmpty, result.count < 1_000 {
            let element = pending.removeFirst()
            result.append(element)
            pending.append(contentsOf: children(of: element))
        }
        return result
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    private func role(of element: AXUIElement) -> String {
        attribute(kAXRoleAttribute, of: element) as? String ?? ""
    }

    private func identifier(of element: AXUIElement) -> String {
        attribute(kAXIdentifierAttribute, of: element) as? String ?? ""
    }

    private func description(of element: AXUIElement) -> String {
        attribute(kAXDescriptionAttribute, of: element) as? String ?? ""
    }

    private func integerValue(of element: AXUIElement) -> Int? {
        if let number = attribute(kAXValueAttribute, of: element) as? NSNumber {
            return number.intValue
        }
        guard let text = attribute(kAXValueAttribute, of: element) as? String else {
            return nil
        }
        return text.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
    }

    private func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func center(of element: AXUIElement) -> CGPoint? {
        guard let positionObject = attribute(kAXPositionAttribute, of: element),
              let sizeObject = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(positionObject) == AXValueGetTypeID(),
              CFGetTypeID(sizeObject) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionObject as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeObject as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }

    private func postMouseClick(at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func postKey(_ keyCode: CGKeyCode, to pid: pid_t) {
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)?.postToPid(pid)
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)?.postToPid(pid)
    }

    private func keyCode(for character: Character) -> CGKeyCode? {
        switch character {
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        default: return nil
        }
    }
}
