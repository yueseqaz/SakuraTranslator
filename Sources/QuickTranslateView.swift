import SwiftUI
import AppKit

/// Compact dialog for hotkey / Services: paste or pick text → 翻译 → result popup.
struct QuickTranslateView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var prefs: Preferences

    var body: some View {
        ZStack {
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .withinWindow,
                emphasized: false
            )

            VStack(spacing: 10) {
                header

                GlassCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            LanguagePill(title: "原文")
                            Spacer()
                            Button("粘贴") {
                                store.quickPasteClipboard()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            Button("清空") {
                                store.quickSource = ""
                                store.quickResult = ""
                                store.quickError = nil
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        TextEditor(text: Binding(
                            get: { store.quickSource },
                            set: { store.quickSource = $0 }
                        ))
                        .font(.system(size: 13.5))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72, maxHeight: 96)
                        .padding(.horizontal, 6)
                        .onKeyPress(.return) {
                            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                                store.runQuickTranslate()
                                return .handled
                            }
                            return .ignored
                        }

                        HStack {
                            Text("\(store.quickSource.count) 字")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(prefs.autoCopyResult ? "自动复制译文" : "手动复制")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                    }
                }

                GlassCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            LanguagePill(title: "译文")
                            if store.quickBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.65)
                            }
                            Spacer()
                            Button(store.quickCopied ? "已复制" : "复制") {
                                store.copyQuickResult()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(store.quickCopied ? GlassPalette.accent : Color.secondary)
                            .disabled(store.quickResult.isEmpty)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        if let error = store.quickError {
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.red.opacity(0.9))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                        } else if store.quickResult.isEmpty {
                            Text("点击「翻译」后显示结果")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                        } else {
                            ScrollView {
                                Text(store.quickResult)
                                    .font(.system(size: 13.5))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 64, maxHeight: 100)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                        }
                    }
                }

                footer
            }
            .padding(12)
        }
        .frame(width: 360, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(GlassPalette.windowStroke, lineWidth: 0.5)
        )
        .onExitCommand {
            QuickPanelController.shared.hide()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(store.provider.accentColor)
            Text("快速翻译")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            EngineModelMenu(store: store)
            Button {
                QuickPanelController.shared.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(GlassPalette.chipFill))
            }
            .buttonStyle(.plain)
            .help("关闭（应用继续在菜单栏运行）")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(store.preferences.currentIsReady
                 ? "\(store.provider.shortName) · \(store.preferences.model(for: store.provider))"
                 : "请先在菜单栏设置中配置 API")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            Button("⌘↩ 翻译") {}
                .opacity(0)
                .frame(width: 0, height: 0)

            Button {
                store.runQuickTranslate()
            } label: {
                HStack(spacing: 5) {
                    if store.quickBusy {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: "character.bubble.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(store.quickBusy ? "翻译中" : "翻译")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(store.provider.accentColor.opacity(store.quickBusy ? 0.5 : 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(store.quickBusy || store.quickSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
