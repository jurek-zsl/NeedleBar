import Foundation
import AppKit

public final class GlobalHotkeyMonitor: @unchecked Sendable {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let onTrigger: @Sendable () -> Void

    public init(onTrigger: @escaping @Sendable () -> Void) {
        self.onTrigger = onTrigger
    }

    public func start() {
        stop()

        // Local monitor when application is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.matchesHotkey(event) == true {
                self?.onTrigger()
                return nil
            }
            return event
        }

        // Global monitor when other applications are active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.matchesHotkey(event) == true {
                self?.onTrigger()
            }
        }
    }

    public func stop() {
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
    }

    deinit {
        stop()
    }

    private func matchesHotkey(_ event: NSEvent) -> Bool {
        // Default hotkey: Option + Space (keyCode 49 with option modifier)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.option) && event.keyCode == 49
    }
}
