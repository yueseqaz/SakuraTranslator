import AppKit
import SwiftUI

extension Notification.Name {
    static let sakuraFocusQuickInput = Notification.Name("SakuraTranslator.FocusQuickInput")
}

/// Global gesture: double-tap Command (⌘) toggles the blank quick-translate dialog.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var installed = false
    private var lastCommandDown: TimeInterval = 0
    private var commandIsDown = false
    private let doubleTapWindow: TimeInterval = 0.35

    private init() {}

    func registerIfNeeded() {
        guard !installed else { return }
        installed = true

        let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
        globalMonitor = global

        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
        localMonitor = local
    }

    /// keyCode 55 = left ⌘, 54 = right ⌘
    private func handleFlagsChanged(_ event: NSEvent) {
        let code = Int(event.keyCode)
        guard code == 55 || code == 54 else { return }

        let commandDown = event.modifierFlags.contains(.command)
        let now = ProcessInfo.processInfo.systemUptime

        if commandDown && !commandIsDown {
            if now - lastCommandDown <= doubleTapWindow {
                lastCommandDown = 0
                commandIsDown = true
                toggleQuickDialog()
                return
            }
            lastCommandDown = now
            commandIsDown = true
        } else if !commandDown {
            commandIsDown = false
        }
    }

    /// Double-tap ⌘: open if closed, close if open.
    private func toggleQuickDialog() {
        if QuickPanelController.shared.isVisible {
            QuickPanelController.shared.hide()
        } else {
            AppStore.shared.openBlankQuickDialog()
            QuickPanelController.shared.showQuick()
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Borderless floating panel that can become key and signal input focus.
final class QuickKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        // After the window is key, ask SwiftUI to focus the TextEditor
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sakuraFocusQuickInput, object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .sakuraFocusQuickInput, object: nil)
        }
    }
}

@MainActor
final class QuickPanelController {
    static let shared = QuickPanelController()

    private var panel: QuickKeyPanel?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func showQuick() {
        NSApp.activate(ignoringOtherApps: true)

        if panel == nil {
            let size = NSSize(width: 360, height: 420)
            let panel = QuickKeyPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true

            let host = NSHostingView(
                rootView: QuickTranslateView(store: .shared, prefs: AppStore.shared.preferences)
            )
            host.frame = NSRect(origin: .zero, size: size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            self.panel = panel
        }

        if let panel {
            position(panel)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            // Extra nudge after the run loop settles
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sakuraFocusQuickInput, object: nil)
            }
        }
        AppStore.shared.surface = .hotkey
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - 72
            )
        )
    }

    func hide() {
        panel?.orderOut(nil)
        AppStore.shared.surface = .menuBar
    }
}
