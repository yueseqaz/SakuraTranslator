import SwiftUI
import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.registerIfNeeded()
        // Right-click → Services → translate
        NSApp.servicesProvider = self
        NSApp.setActivationPolicy(.accessory)
    }

    /// macOS Services entry: selected text → quick translate popup.
    @objc func translateSelection(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let text = (pboard.string(forType: .string) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            if text.isEmpty {
                AppStore.shared.quickError = "服务未收到选中文本"
                QuickPanelController.shared.showQuick()
            } else {
                AppStore.shared.ingestServicesText(text)
            }
        }
    }
}

@main
struct SakuraTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: AppStore.shared)
                .onAppear {
                    AppStore.shared.surface = .menuBar
                    HotKeyManager.shared.registerIfNeeded()
                }
        } label: {
            Image(systemName: "character.bubble.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
