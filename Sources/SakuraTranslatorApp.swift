import SwiftUI
import AppKit

@main
struct SakuraTranslatorApp: App {
    @StateObject private var bootstrap = HotKeyBootstrap()

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

/// Registers global hotkeys once at launch (even if menu panel never opens).
@MainActor
final class HotKeyBootstrap: ObservableObject {
    init() {
        HotKeyManager.shared.registerIfNeeded()
    }
}
