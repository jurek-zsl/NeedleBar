import Foundation
import AppKit
import Carbon

private let _hotkeyLock = NSLock()
nonisolated(unsafe) private var _globalHotkeyCallback: (@Sendable () -> Void)?

private func _carbonHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    _hotkeyLock.lock()
    let callback = _globalHotkeyCallback
    _hotkeyLock.unlock()

    if let callback = callback {
        DispatchQueue.main.async {
            callback()
        }
    }
    return noErr
}

public final class GlobalHotkeyMonitor: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private let onTrigger: @Sendable () -> Void

    public init(onTrigger: @escaping @Sendable () -> Void) {
        self.onTrigger = onTrigger
    }

    public func start() {
        stop()

        _hotkeyLock.lock()
        _globalHotkeyCallback = onTrigger
        _hotkeyLock.unlock()

        // 1. Install Carbon Event Handler (Works globally without Accessibility permissions)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            _carbonHotkeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        // 2. Register unique shortcut: ⌃⌥N (Control + Option + N)
        // kVK_ANSI_N is key code 45 ('N' for NeedleBar)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E424152), id: 1) // 'NBAR'
        let carbonModifiers = UInt32(controlKey | optionKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_N),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        // 3. Local monitor when NeedleBar is active (for Escape or Command+Escape)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.matchesLocalHotkey(event) == true {
                self?.onTrigger()
                return nil
            }
            return event
        }
    }

    public func stop() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }

        _hotkeyLock.lock()
        _globalHotkeyCallback = nil
        _hotkeyLock.unlock()
    }

    deinit {
        stop()
    }

    private func matchesLocalHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Control + Option + N
        let isCtrlOptN = flags.contains(.control) && flags.contains(.option) && event.keyCode == 45
        // Command + Escape
        let isCommandEscape = flags.contains(.command) && event.keyCode == 53
        return isCtrlOptN || isCommandEscape
    }
}
