import Foundation
import AppKit
import Combine
import SwiftUI
import NeedleBarCore

public final class FloatingBarWindow: NSPanel {
    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    override public func cancelOperation(_ sender: Any?) {
        MainActor.assumeIsolated {
            FloatingBarWindowController.shared.handleCancel()
        }
    }

    override public func keyDown(with event: NSEvent) {
        // Return key (keyCode 36) or keypad Enter (keyCode 76)
        if event.keyCode == 36 || event.keyCode == 76 {
            var handled = false
            MainActor.assumeIsolated {
                if FloatingBarWindowController.shared.hasActiveConfirmation {
                    FloatingBarWindowController.shared.handleConfirm()
                    handled = true
                }
            }
            if handled {
                return
            }
        }
        super.keyDown(with: event)
    }
}

@MainActor
public final class FloatingBarWindowController: NSObject, ObservableObject {
    public static let shared = FloatingBarWindowController()

    private var panel: FloatingBarWindow?
    private var appState: AppState?
    private var localEventMonitor: Any?
    private var confirmationObservation: AnyCancellable?

    public var hasActiveConfirmation: Bool {
        appState?.confirmationPlan != nil
    }

    public func handleCancel() {
        if let appState = appState, appState.confirmationPlan != nil {
            appState.cancelPlan()
        } else if let appState = appState, appState.isHelpPresented {
            appState.dismissHelp()
        } else {
            hide()
        }
    }

    public func handleConfirm() {
        guard let appState = appState, appState.confirmationPlan != nil else { return }
        Task {
            await appState.confirmPlan()
        }
    }

    private let defaultWidth: CGFloat = 600
    private let defaultHeight: CGFloat = 340
    private let confirmationHeight: CGFloat = 470
    private let helpHeight: CGFloat = 530
    private var preferredHeight: CGFloat = 340

    public override init() {
        super.init()
    }

    public func configure(appState: AppState) {
        self.appState = appState
        setupPanel()
        observePresentation(in: appState)
    }

    private func observePresentation(in appState: AppState) {
        confirmationObservation = Publishers.CombineLatest(appState.$confirmationPlan, appState.$isHelpPresented)
            .map { [defaultHeight, confirmationHeight, helpHeight] plan, isHelp in
                if isHelp {
                    return helpHeight
                } else if plan != nil {
                    return confirmationHeight
                } else {
                    return defaultHeight
                }
            }
            .removeDuplicates()
            .sink { [weak self] height in
                Task { @MainActor [weak self] in
                    self?.setPreferredHeight(height)
                }
            }
    }

    private func setPreferredHeight(_ height: CGFloat) {
        guard preferredHeight != height else { return }
        preferredHeight = height
        repositionToCenter(animated: panel?.isVisible == true)
    }

    private func setupPanel() {
        guard let appState = self.appState else { return }

        let window = FloatingBarWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isFloatingPanel = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = LiquidGlassPillBarView(
            appState: appState,
            onDismiss: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        window.contentView = hostingView
        self.panel = window

        // Monitor clicks outside to dismiss
        self.localEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel, panel.isVisible else { return }
            let clickLocation = NSEvent.mouseLocation
            if !panel.frame.contains(clickLocation) {
                // If clicked outside, close
                self.hide()
            }
        }
    }

    public func toggle() {
        guard let panel = panel else { return }
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        guard let panel = panel else { return }

        repositionToCenter()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func hide() {
        panel?.orderOut(nil)
        NSApp.deactivate()
    }

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private func repositionToCenter(animated: Bool = false) {
        guard let panel = panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame

        let width = defaultWidth
        let height = preferredHeight
        let x = visibleFrame.midX - (width / 2)
        // Position comfortably in the center (slightly above center like Spotlight for optimal eye-level ergonomic input)
        let y = visibleFrame.midY - (height / 2) + (visibleFrame.height * 0.08)

        panel.setFrame(
            NSRect(x: x, y: y, width: width, height: height),
            display: true,
            animate: animated
        )
    }

    deinit {
        MainActor.assumeIsolated {
            if let monitor = localEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
