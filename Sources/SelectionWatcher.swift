import AppKit
import ApplicationServices
import SwiftUI
import ApplicationServices.HIServices

/// Watches text selection system-wide; shows a small "译" bubble near the cursor.
@MainActor
final class SelectionWatcher {
    static let shared = SelectionWatcher()

    private var monitor: Any?
    private var installed = false
    private var debounceTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var bubble: SelectionBubblePanel?
    private var lastSelection: String = ""

    private init() {}

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func startIfNeeded() {
        guard !installed else { return }
        installed = true
        _ = requestAccessibilityIfNeeded()

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleSelectionCheck()
            }
        }

        // Hide bubble if user clicks inside our own quick dialog
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                self?.hideBubble()
            }
            return event
        }
    }

    private func scheduleSelectionCheck() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self else { return }
            self.refreshSelectionBubble()
        }
    }

    func refreshSelectionBubble() {
        // Don't fight our own panels
        if QuickPanelController.shared.isVisible {
            hideBubble()
            return
        }

        guard isTrusted else { return }

        let text = (HotKeyManager.frontmostSelectedText() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Too short or empty → hide
        guard text.count >= 2, text.count <= 4000 else {
            lastSelection = ""
            hideBubble()
            return
        }

        // Same selection already showing
        if text == lastSelection, bubble?.isVisible == true {
            scheduleAutoHide()
            return
        }

        lastSelection = text
        showBubble(with: text)
        scheduleAutoHide()
    }

    private func showBubble(with text: String) {
        if bubble == nil {
            let size = NSSize(width: 72, height: 32)
            let panel = SelectionBubblePanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isMovableByWindowBackground = false

            let host = NSHostingView(
                rootView: SelectionBubbleView {
                    Task { @MainActor in
                        SelectionWatcher.shared.handleTranslateTap()
                    }
                }
            )
            host.frame = NSRect(origin: .zero, size: size)
            panel.contentView = host
            bubble = panel
        }

        guard let panel = bubble else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(
            NSPoint(x: mouse.x + 12, y: mouse.y - 40)
        )
        panel.orderFrontRegardless()
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hideBubble()
        }
    }

    func hideBubble() {
        bubble?.orderOut(nil)
    }

    private func handleTranslateTap() {
        let text = lastSelection
        hideBubble()
        guard !text.isEmpty else { return }
        AppStore.shared.ingestSelectionForQuickTranslate(text)
        QuickPanelController.shared.showQuick()
    }
}

final class SelectionBubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

struct SelectionBubbleView: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("翻译")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.9))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .frame(width: 72, height: 32)
        .help("用 Sakura Translator 翻译选中内容")
    }
}
