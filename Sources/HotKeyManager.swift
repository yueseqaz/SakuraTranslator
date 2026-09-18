import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Hotkeys open a blank quick-translate dialog (user types/pastes).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var installed = false

    private init() {}

    func registerIfNeeded() {
        guard !installed else { return }
        installed = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard status == noErr else { return noErr }
            Task { @MainActor in
                HotKeyManager.shared.handle(id: Int(hkID.id))
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        var ref1: EventHotKeyRef?
        let id1 = EventHotKeyID(signature: OSType(0x534B5452), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(optionKey | cmdKey),
            id1,
            GetApplicationEventTarget(),
            0,
            &ref1
        )
        if let ref1 { hotKeyRefs.append(ref1) }

        var ref2: EventHotKeyRef?
        let id2 = EventHotKeyID(signature: OSType(0x534B5452), id: 2)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(optionKey | cmdKey),
            id2,
            GetApplicationEventTarget(),
            0,
            &ref2
        )
        if let ref2 { hotKeyRefs.append(ref2) }
    }

    private func handle(id: Int) {
        AppStore.shared.openBlankQuickDialog()
        QuickPanelController.shared.showQuick()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Floating compact dialog — borderless, no traffic-light buttons.
@MainActor
final class QuickPanelController {
    static let shared = QuickPanelController()

    private var panel: NSPanel?

    func showQuick() {
        NSApp.activate(ignoringOtherApps: true)

        if panel == nil {
            let size = NSSize(width: 360, height: 420)
            let panel = NSPanel(
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
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true

            let host = NSHostingView(
                rootView: QuickTranslateView(store: .shared, prefs: AppStore.shared.preferences)
            )
            host.frame = NSRect(origin: .zero, size: size)
            panel.contentView = host
            self.panel = panel
        }

        if let panel {
            position(panel)
            panel.makeKeyAndOrderFront(nil)
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
