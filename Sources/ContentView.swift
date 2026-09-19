import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: AppStore = .shared

    var body: some View {
        ZStack {
            // withinWindow + system MenuBarExtra chrome: cheaper than behindWindow blur
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .withinWindow,
                emphasized: false
            )

            VStack(spacing: 8) {
                header
                tabBar

                // Single tab switch path — no implicit animation, no shadow
                Group {
                    switch store.activeTab {
                    case .translate:
                        languageBar
                        sourceCard
                            .frame(minHeight: 100, maxHeight: .infinity)
                        resultCard
                            .frame(minHeight: 110, maxHeight: .infinity)
                        translateFooter
                    case .history:
                        HistoryPageView(store: store)
                    case .usage:
                        UsagePageView(store: store, usage: store.usage)
                    case .settings:
                        SettingsPageView(store: store)
                    }
                }
                .transaction { $0.disablesAnimations = true }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(width: 400, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(GlassPalette.windowStroke, lineWidth: 0.5)
        )
        // No .shadow() — full-panel shadow on translucent MenuBarExtra is very expensive
        .onExitCommand {
            if store.activeTab == .settings {
                store.leaveSettings()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(store.provider.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(store.provider.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold))
                if !headerStatus.isEmpty {
                    Text(headerStatus)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if store.activeTab != .settings {
                EngineModelMenu(store: store)
            } else {
                // Show which engine this settings page configures (no picker, no gear)
                HStack(spacing: 5) {
                    Image(systemName: store.draftProvider.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(store.draftProvider.accentColor)
                    Text("配置 \(store.draftProvider.shortName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(store.draftProvider.accentColor.opacity(0.08))
                )
            }

            Button {
                // Close panel only — app stays in menu bar
                store.closePanels()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(GlassPalette.chipFill))
            }
            .buttonStyle(.plain)
            .help("关闭面板（应用继续在菜单栏运行）")
        }
    }

    private var headerTitle: String {
        "Sakura Translator"
    }

    private var headerStatus: String {
        switch store.activeTab {
        case .settings:
            return "设置 · \(store.draftProvider.displayName)"
        case .usage:
            return "用量 · 本机统计"
        case .history:
            return "最近 \(store.history.items.count) 条译文"
        case .translate:
            if store.isTranslating { return "翻译中…" }
            if let note = store.statusNote { return note }
            if !store.preferences.currentHasKey { return "未配置 Key · 页签进入设置" }
            if !store.preferences.currentIsReady {
                return store.provider.isCustom ? "自定义引擎未配置完整" : "模型未配置"
            }
            return store.surface == .hotkey ? "快捷唤出 · ⌥⌘T / ⌥⌘S" : "翻译"
        }
    }

    // MARK: Tabs — full capsule is clickable, not just the glyph/text center

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases, id: \.rawValue) { tab in
                let isActive = store.activeTab == tab

                Button {
                    store.selectTab(tab)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 12, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minWidth: 80, minHeight: 32)
                    // Hit-test the entire capsule/rect, not only text
                    .contentShape(Rectangle())
                    .background(
                        Capsule()
                            .fill(isActive ? Color.primary.opacity(0.10) : Color.clear)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isActive ? GlassPalette.cardStroke : Color.primary.opacity(0.04),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                // macOS plain buttons sometimes shrink hit area to content — keep full frame
                .simultaneousGesture(TapGesture().onEnded {
                    store.selectTab(tab)
                })
            }

            Spacer(minLength: 4)

            if store.activeTab == .translate {
                Text("双击 ⌘")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: Language

    private var languageBar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(LanguageTarget.usableCases) { target in
                    Button {
                        store.languageTarget = target
                    } label: {
                        if store.languageTarget == target {
                            Label(target.label, systemImage: "checkmark")
                        } else {
                            Text(target.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(store.languageTarget.label)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(GlassPalette.chipFill)
                        .overlay(
                            Capsule().strokeBorder(GlassPalette.cardStroke, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(store.languageTarget.label)

            // Tone preset
            Menu {
                ForEach(TranslationTone.allCases) { tone in
                    Button {
                        store.tone = tone
                    } label: {
                        if store.tone == tone {
                            Label(tone.label, systemImage: "checkmark")
                        } else {
                            Text(tone.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.tone.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                    Text(store.tone.shortLabel)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(GlassPalette.chipFill)
                        .overlay(
                            Capsule().strokeBorder(GlassPalette.cardStroke, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("语气：\(store.tone.label)")

            Button {
                store.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.languageTarget.swapped == nil ? Color.gray.opacity(0.45) : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(GlassPalette.chipFill))
            }
            .buttonStyle(.plain)
            .disabled(store.languageTarget.swapped == nil)
            .help("交换语言方向")

            Spacer(minLength: 0)
        }
    }

    // MARK: Source

    private var sourceCard: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    LanguagePill(title: "原文")
                    Spacer()
                    Button {
                        store.pasteFromClipboard()
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.clearAll()
                    } label: {
                        Label("清空", systemImage: "xmark.circle")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                TextEditor(text: Binding(
                    get: { store.sourceText },
                    set: { store.sourceText = $0 }
                ))
                .font(.system(size: 13.5))
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 6)
                .onKeyPress(.return) {
                    if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                        store.translate()
                        return .handled
                    }
                    return .ignored
                }

                HStack {
                    Text("\(store.sourceText.count) 字")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(store.autoTranslate ? "自动翻译 开" : "手动翻译")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    if let usage = store.lastUsage {
                        Text("· \(usage.totalTokens) tokens")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Result

    private var resultCard: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    LanguagePill(title: "译文")
                    if store.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    }
                    Spacer()
                    Button {
                        store.copyResult()
                    } label: {
                        Label(store.copiedFlash ? "已复制" : "复制",
                              systemImage: store.copiedFlash ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(store.copiedFlash ? GlassPalette.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.resultText.isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if let error = store.errorMessage {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                } else {
                    ResultBodyView(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Footer — model only in the top-right badge

    private var translateFooter: some View {
        HStack(spacing: 8) {
            Spacer()

            Button {
                store.translate()
            } label: {
                HStack(spacing: 5) {
                    if store.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: "character.bubble.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(store.isTranslating ? "翻译中" : "翻译")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(
                            store.canTranslate || store.isTranslating
                            ? store.provider.accentColor
                            : store.provider.accentColor.opacity(0.35)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!store.canTranslate)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
