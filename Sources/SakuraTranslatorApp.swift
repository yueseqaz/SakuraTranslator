import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.registerIfNeeded()
        NSApp.setActivationPolicy(.accessory)
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
