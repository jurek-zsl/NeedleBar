import SwiftUI
import AppKit
import Combine
import NeedleBarCore

@main
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    public var statusItem: NSStatusItem?
    public var hotkeyMonitor: GlobalHotkeyMonitor?
    public let appState = AppState()
    private var timerSubscription: AnyCancellable?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        FloatingBarWindowController.shared.configure(appState: appState)

        setupMainMenu()
        setupStatusItem()
        setupHotkey()

        // Automatically show the centered floating pill bar on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            FloatingBarWindowController.shared.show()
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit NeedleBar",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        applicationMenu.addItem(quitItem)

        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)
        NSApp.mainMenu = mainMenu
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        FloatingBarWindowController.shared.show()
        return false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = createNeedleIcon()
            button.toolTip = "NeedleBar (⌃⌥N)"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        observeActiveTimer()
    }

    private func observeActiveTimer() {
        timerSubscription = ActiveTimerTracker.shared.$remainingSeconds
            .combineLatest(ActiveTimerTracker.shared.$isTimerActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds, isActive in
                guard let self = self, let button = self.statusItem?.button else { return }
                if isActive && seconds > 0 {
                    let m = seconds / 60
                    let s = seconds % 60
                    button.title = String(format: " %02d:%02d", m, s)
                } else {
                    button.title = ""
                }
            }
    }

    /// Creates a crisp vector needle icon for the macOS menu bar
    private func createNeedleIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            context.saveGState()
            context.translateBy(x: 9, y: 9)
            context.rotate(by: -45 * .pi / 180)

            let path = NSBezierPath()

            // Sharp tip at bottom: (0, -7.5)
            path.move(to: NSPoint(x: 0, y: -7.5))
            path.curve(to: NSPoint(x: 1.1, y: 3.5),
                       controlPoint1: NSPoint(x: 0.2, y: -3.0),
                       controlPoint2: NSPoint(x: 0.8, y: 1.0))
            path.line(to: NSPoint(x: 1.3, y: 5.8))
            path.curve(to: NSPoint(x: 0, y: 7.5),
                       controlPoint1: NSPoint(x: 1.3, y: 7.2),
                       controlPoint2: NSPoint(x: 0.8, y: 7.5))
            path.curve(to: NSPoint(x: -1.3, y: 5.8),
                       controlPoint1: NSPoint(x: -0.8, y: 7.5),
                       controlPoint2: NSPoint(x: -1.3, y: 7.2))
            path.line(to: NSPoint(x: -1.1, y: 3.5))
            path.curve(to: NSPoint(x: 0, y: -7.5),
                       controlPoint1: NSPoint(x: -0.8, y: 1.0),
                       controlPoint2: NSPoint(x: -0.2, y: -3.0))
            path.close()

            // Eye hole cutout
            let eyePath = NSBezierPath(
                roundedRect: NSRect(x: -0.38, y: 3.8, width: 0.76, height: 2.6),
                xRadius: 0.38,
                yRadius: 0.38
            )
            path.append(eyePath)
            path.windingRule = .evenOdd

            NSColor.black.setFill()
            path.fill()

            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu(sender)
        } else {
            FloatingBarWindowController.shared.toggle()
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle NeedleBar (⌃⌥N)", action: #selector(toggleFloatingBar), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit NeedleBar", action: #selector(quitApp), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func toggleFloatingBar() {
        FloatingBarWindowController.shared.toggle()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(appState: appState)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func setupHotkey() {
        guard hotkeyMonitor == nil else { return }
        let monitor = GlobalHotkeyMonitor {
            DispatchQueue.main.async {
                FloatingBarWindowController.shared.toggle()
            }
        }
        monitor.start()
        self.hotkeyMonitor = monitor
    }
}
