import SwiftUI
import AppKit

// MARK: - Native glass backdrop

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = emphasized
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Skip redundant assignments — avoids WindowServer blur thrash on tab switches
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
        if nsView.isEmphasized != emphasized { nsView.isEmphasized = emphasized }
        if nsView.state != .active { nsView.state = .active }
    }
}

// MARK: - Palette — keep fills very light so material stays visible

enum GlassPalette {
    /// Nearly clear surface; relies on vibrancy, not paint.
    static let cardFill = Color.primary.opacity(0.028)
    static let cardStroke = Color.primary.opacity(0.055)
    static let chipFill = Color.primary.opacity(0.035)
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let windowStroke = Color.white.opacity(0.22)
}

extension Provider {
    var accentColor: Color {
        switch self {
        case .deepseek: return Color(red: 0.30, green: 0.42, blue: 1.0)
        case .mimo: return Color(red: 1.0, green: 0.42, blue: 0.0)
        case .glm: return Color(red: 0.22, green: 0.35, blue: 1.0)
        case .custom: return Color(red: 0.55, green: 0.35, blue: 0.95)
        }
    }

    var systemImage: String {
        switch self {
        case .deepseek: return "whale"
        case .mimo: return "sparkles"
        case .glm: return "hexagon"
        case .custom: return "puzzlepiece.extension"
        }
    }
}

// MARK: - Glass card (single flat surface — no nested blur sheets)

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GlassPalette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(GlassPalette.cardStroke, lineWidth: 1)
            )
    }
}

// MARK: - Language pill

struct LanguagePill: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(GlassPalette.chipFill))
    }
}

// MARK: - Engine model switcher (page badge)

struct EngineModelMenu: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Menu {
            ForEach(Provider.allCases) { p in
                Section(p.displayName) {
                    let models = store.modelsForEngineMenu(p)
                    if models.isEmpty {
                        Button {
                            if p.isCustom {
                                store.openSettings(for: .custom)
                            } else {
                                store.selectEngine(provider: p, model: p.defaultModel)
                            }
                        } label: {
                            if p.isCustom {
                                Label("去设置配置…", systemImage: "gearshape")
                            } else {
                                Text(p.defaultModel)
                            }
                        }
                    } else {
                        ForEach(models, id: \.self) { model in
                            Button {
                                store.selectEngine(provider: p, model: model)
                            } label: {
                                let active = store.preferences.provider == p
                                    && store.preferences.model(for: p) == model
                                if active {
                                    Label(model, systemImage: "checkmark")
                                } else {
                                    Text(model)
                                }
                            }
                        }
                        if p.isCustom {
                            Button {
                                store.openSettings(for: .custom)
                            } label: {
                                Label("自定义设置…", systemImage: "gearshape")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.provider.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(store.provider.accentColor)
                Text(store.currentEngineLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(store.provider.accentColor.opacity(0.08))
                    .overlay(
                        Capsule().strokeBorder(store.provider.accentColor.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("切换服务商与模型")
    }
}

// MARK: - Result body

struct ResultBodyView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        if store.resultText.isEmpty && !store.isTranslating {
            Text(store.errorMessage == nil ? "译文会显示在这里" : " ")
                .font(.system(size: 13.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                (
                    Text(store.resultText)
                        .foregroundColor(.primary)
                    + Text(store.streamingCursor && store.isTranslating ? " ▍" : "")
                        .foregroundColor(GlassPalette.accent)
                )
                .font(.system(size: 14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Settings as a full in-panel page (not a modal)

struct SettingsPageView: View {
    @ObservedObject var store: AppStore

    private var modelOptions: [String] {
        var list: [String] = []
        let current = store.draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty { list.append(current) }
        for m in store.draftFetchedModels where !list.contains(m) { list.append(m) }
        for m in store.draftProvider.suggestedModels where !list.contains(m) { list.append(m) }
        return list
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 8) {
                    // Engine switch lives on the main page badge, not here
                    credentialCard
                    modelCard
                    triggerCard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
    }

    private var credentialCard: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: store.draftProvider.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(store.draftProvider.accentColor)
                    Text("接入 · \(store.draftProvider.displayName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Base URL")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(
                        store.draftProvider.baseURLPlaceholder,
                        text: Binding(
                            get: { store.draftBase },
                            set: { store.draftBase = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    if store.draftProvider.isCustom {
                        Text("OpenAI 兼容即可，例如 https://api.example.com/v1")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("API Key")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if store.draftProvider != .custom {
                            Button("申请页") {
                                store.preferences.setAPIKey(store.draftKey, for: store.draftProvider)
                                store.openKeyPortal(store.draftProvider)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(GlassPalette.accent)
                        }
                    }
                    SecureField("粘贴 API Key", text: Binding(
                        get: { store.draftKey },
                        set: { store.draftKey = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    Text(store.draftProvider.keyHint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var modelCard: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionTitle("模型")
                    Spacer()
                    Button {
                        store.fetchDraftModels()
                    } label: {
                        HStack(spacing: 4) {
                            if store.isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.clockwise.circle")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(store.isFetchingModels ? "获取中…" : "获取模型")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(GlassPalette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isFetchingModels)
                }

                TextField(
                    store.draftProvider.defaultModel.isEmpty
                        ? "从接口获取，或手动填写"
                        : store.draftProvider.defaultModel,
                    text: Binding(
                        get: { store.draftModel },
                        set: { store.draftModel = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))

                if let note = store.modelFetchNote {
                    Text(note)
                        .font(.system(size: 10.5))
                        .foregroundStyle(
                            note.contains("失败") || note.contains("请先")
                                || note.contains("无效") || note.contains("未找到")
                                || note.contains("无法")
                            ? Color.red.opacity(0.85)
                            : Color.secondary
                        )
                }

                if !modelOptions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(modelOptions.prefix(16), id: \.self) { m in
                                Button(m) {
                                    store.draftModel = m
                                }
                                .font(.system(size: 10.5, design: .monospaced))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(store.draftModel == m
                                              ? store.draftProvider.accentColor.opacity(0.15)
                                              : GlassPalette.chipFill)
                                )
                                .foregroundStyle(store.draftModel == m
                                                 ? store.draftProvider.accentColor
                                                 : Color.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var triggerCard: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { store.autoTranslate },
                    set: { store.autoTranslate = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自动翻译")
                            .font(.system(size: 13, weight: .semibold))
                        Text(store.autoTranslate
                             ? "开：停止输入约 1.2 秒后自动翻译"
                             : "关：需手动点「翻译」或 ⌘↩")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: Binding(
                    get: { store.autoCopyResult },
                    set: { store.autoCopyResult = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("翻译后自动复制译文")
                            .font(.system(size: 13, weight: .semibold))
                        Text(store.autoCopyResult
                             ? "开：译文完成即写入剪贴板"
                             : "关：需手动点「复制」")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 6) {
                    Text("默认语气")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("语气", selection: Binding(
                        get: { store.tone },
                        set: { store.tone = $0 }
                    )) {
                        ForEach(TranslationTone.allCases) { tone in
                            Text(tone.label).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(store.tone.promptDirective)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .opacity(0.35)

                Toggle(isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("开机自启动")
                            .font(.system(size: 13, weight: .semibold))
                        Text("当前：\(LaunchAtLogin.statusLabel)。开启后登录即自动运行菜单栏图标")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)

                Button("退出应用（完全退出）") {
                    store.quitApp()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.red.opacity(0.08)))

                Divider()
                    .opacity(0.35)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("快速翻译 / 划词")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("双击 ⌘ — 打开空白快速翻译框；再双击 ⌘ 关闭")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("任意处选中文字（≥2 字）— 光标旁出现「翻译」按钮，点击后用快速翻译框展示结果")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("划词需「辅助功能」权限。当前：\(SelectionWatcher.shared.isTrusted ? "已授权" : "未授权")")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(SelectionWatcher.shared.isTrusted ? "重新检查权限" : "打开辅助功能设置") {
                        if SelectionWatcher.shared.isTrusted {
                            SelectionWatcher.shared.refreshSelectionBubble()
                        } else {
                            SelectionWatcher.openAccessibilitySettings()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(GlassPalette.accent)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("恢复默认") {
                store.resetDraftEndpoints()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(GlassPalette.chipFill))

            Spacer()

            Button("取消") {
                store.leaveSettings()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Button("保存并返回") {
                store.saveSettings()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.plain)
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(store.draftProvider.accentColor))
            .foregroundStyle(.white)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

// MARK: - History page (last 10)

struct HistoryPageView: View {
    @ObservedObject var store: AppStore

    private var items: [TranslationHistoryItem] {
        store.history.items
    }

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("翻译历史")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("最多 \(HistoryStore.maxCount) 条")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Button("清空") {
                        store.history.clearAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                if items.isEmpty {
                    Text("还没有历史。翻译成功后会自动记入最近 10 条。")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(items) { item in
                                historyRow(item)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func historyRow(_ item: TranslationHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: item.provider.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(item.provider.accentColor)
                Text(item.provider.shortName)
                    .font(.system(size: 11, weight: .medium))
                Text(item.language.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(UsageStore.formatTime(item.timestamp))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Text(item.source)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(item.result)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button("复制译文") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.result, forType: .string)
                    store.statusNote = "已复制译文"
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(GlassPalette.accent)

                Button("复制原文") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.source, forType: .string)
                    store.statusNote = "已复制原文"
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

                Button("再次翻译") {
                    store.retranslateHistory(item)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(item.provider.accentColor)

                Spacer()

                Button {
                    store.history.remove(id: item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Token usage page (must fit inside panel — no overflow)

struct UsagePageView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var usage: UsageStore

    var body: some View {
        VStack(spacing: 8) {
            summaryCard
            providerCard
            recentCard
                .frame(maxHeight: .infinity)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var summaryCard: some View {
        let today = usage.totals(usage.todayRecords)
        let month = usage.totals(usage.last30DaysRecords)
        let todayCost = usage.cost(for: usage.todayRecords)
        let monthCost = usage.cost(for: usage.last30DaysRecords)

        return GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GlassPalette.accent)
                    Text("Token 用量")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("今日 \(today.count) 次")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UsageStore.formatTokens(today.total))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("今日 tokens")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(todayCost.combinedLabel)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(todayCost.isEmpty ? Color.secondary : GlassPalette.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("今日成本 ¥")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    compactStat("入", UsageStore.formatTokens(today.prompt))
                    compactStat("出", UsageStore.formatTokens(today.completion))
                    compactStat("30天 tokens", UsageStore.formatTokens(month.total))
                    compactStat("30天成本", monthCost.combinedLabel)
                }
            }
        }
    }

    private func compactStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GlassPalette.chipFill)
        )
    }

    private var providerCard: some View {
        let buckets = usage.providerBuckets
        let maxTotal = max(buckets.map(\.total).max() ?? 1, 1)

        return GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("按服务商 · 30 天")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if buckets.isEmpty {
                    Text("暂无记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(buckets) { bucket in
                        let ratio = min(1, max(0.02, CGFloat(bucket.total) / CGFloat(maxTotal)))
                        HStack(spacing: 8) {
                            Image(systemName: bucket.provider.systemImage)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(bucket.provider.accentColor)
                                .frame(width: 14)
                            Text(bucket.provider.shortName)
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 64, alignment: .leading)

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.06))
                                Capsule()
                                    .fill(bucket.provider.accentColor.opacity(0.7))
                                    .scaleEffect(x: ratio, y: 1, anchor: .leading)
                            }
                            .frame(height: 4)

                            Text(UsageStore.formatTokens(bucket.total))
                                .font(.system(size: 10.5, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)

                            Text(bucket.costLabel ?? "—")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(bucket.costLabel == nil ? Color.secondary : bucket.provider.accentColor)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var recentCard: some View {
        let list = usage.recentRecords

        return GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("最近请求")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(list.count) 条")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if list.isEmpty {
                    Text("翻译一次后这里会列出明细")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(list) { rec in
                                requestRow(rec)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Compact single-line row: provider · tokens · cost · time (no model name).
    private func requestRow(_ rec: UsageRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: rec.provider.systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(rec.provider.accentColor)
                .frame(width: 12)

            Text(rec.provider.shortName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)

            Text("\(rec.promptTokens)→\(rec.completionTokens)")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Text(usage.recordCost(rec) ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(usage.recordCost(rec) == nil ? Color.secondary : rec.provider.accentColor)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Text(UsageStore.formatTime(rec.timestamp).suffix(5))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var footer: some View {
        HStack {
            Text("人民币估算 · 非账单 · 自定义不计")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Button("清空") {
                usage.clearAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.red.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.red.opacity(0.08)))
        }
    }
}
