import Foundation
import AppKit
import SwiftUI
import NeedleBarCore

@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var appState: AppState?

    public func show(appState: AppState) {
        self.appState = appState

        if let win = window {
            win.center()
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "NeedleBar Settings"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.toolbarStyle = .unifiedCompact
        win.minSize = NSSize(width: 760, height: 600)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.contentView = NSHostingView(rootView: SettingsView(appState: appState))

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        // If the floating bar is not visible when settings closes, return focus to previous app
        if !FloatingBarWindowController.shared.isVisible {
            NSApp.deactivate()
        }
    }
}
