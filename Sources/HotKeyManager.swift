import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Global hotkeys:
///  - ⌥⌘T : clipboard → translate panel
///  - ⌥⌘S : selected text (Accessibility) → translate panel + auto start
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

        // ⌥⌘T — clipboard
        var ref1: EventHotKeyRef?
        let id1 = EventHotKeyID(signature: OSType(0x534B5452), id: 1) // SKTR
        RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(optionKey | cmdKey),
            id1,
            GetApplicationEventTarget(),
            0,
            &ref1
        )
        if let ref1 { hotKeyRefs.append(ref1) }

        // ⌥⌘S — selection
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
        switch id {
        case 1:
            handleClipboard()
        case 2:
            handleSelection()
        default:
            break
        }
    }

    private func handleClipboard() {
        let store = AppStore.shared
        var text = NSPasteboard.general.string(forType: .string) ?? ""
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            store.ingestHotkeyText("", autoStart: false)
            store.quickError = "剪贴板没有文本"
        } else {
            store.ingestHotkeyText(text, autoStart: false)
        }
        QuickPanelController.shared.showQuick()
    }

    private func handleSelection() {
        let store = AppStore.shared
        let selected = Self.frontmostSelectedText()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let selected, !selected.isEmpty {
            store.ingestHotkeyText(selected, autoStart: true)
        } else {
            let clip = (NSPasteboard.general.string(forType: .string) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if clip.isEmpty {
                store.ingestHotkeyText("", autoStart: false)
                store.quickError = "未读到选中文本。请在系统设置授予辅助功能权限，或先选中文字"
            } else {
                store.ingestHotkeyText(clip, autoStart: true)
            }
        }
        QuickPanelController.shared.showQuick()
    }

    /// Best-effort read of selected text via Accessibility API.
    static func frontmostSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        let appStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )
        guard appStatus == .success, let focusedAppRef else { return nil }
        let appElement = focusedAppRef as! AXUIElement

        var focusedUIRef: CFTypeRef?
        let uiStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedUIRef
        )
        guard uiStatus == .success, let focusedUIRef else { return nil }
        let uiElement = focusedUIRef as! AXUIElement

        var selectedRef: CFTypeRef?
        let selStatus = AXUIElementCopyAttributeValue(
            uiElement,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        guard selStatus == .success, let selectedRef else { return nil }
        return selectedRef as? String
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

/// Floating compact dialog used by hotkeys and Services.
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
                styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "快速翻译"
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

    func show() { showQuick() }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 72
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hide() {
        panel?.orderOut(nil)
        AppStore.shared.surface = .menuBar
    }
}
