import SwiftUI
import AppKit
import NeedleBarCore

@main
public struct NeedleBarApp: App {
    @StateObject private var appState = AppState()
    @State private var hotkeyMonitor: GlobalHotkeyMonitor?

    public init() {
        // Set accessory activation policy to behave as a pure menu-bar utility
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    public var body: some Scene {
        MenuBarExtra("NeedleBar", systemImage: "sparkle.magnifyingglass") {
            CommandPopoverView(appState: appState)
                .onAppear {
                    setupHotkey()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
                .frame(width: 500, height: 500)
        }
    }

    private func setupHotkey() {
        guard hotkeyMonitor == nil else { return }
        let monitor = GlobalHotkeyMonitor {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        monitor.start()
        self.hotkeyMonitor = monitor
    }
}
