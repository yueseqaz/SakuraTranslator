import Foundation
import AppKit
import Combine

enum AppSurface {
    case menuBar
    case hotkey
}

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    let preferences = Preferences()
    let usage = UsageStore.shared
    let history = HistoryStore.shared

    @Published var sourceText: String = ""
    @Published var resultText: String = ""
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?
    @Published var statusNote: String?
    @Published var copiedFlash: Bool = false
    @Published var streamingCursor: Bool = false
    @Published var activeTab: MainTab = .translate
    @Published var returnTab: MainTab = .translate
    @Published var lastUsage: TokenUsage?
    @Published var surface: AppSurface = .menuBar
    @Published var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    // Quick translate dialog (hotkey / Services)
    @Published var quickSource: String = ""
    @Published var quickResult: String = ""
    @Published var quickError: String?
    @Published var quickBusy: Bool = false
    @Published var quickCopied: Bool = false
    private var quickTask: Task<Void, Never>?

    // Settings drafts — one published struct so tab switch is a single update
    struct SettingsDraft: Equatable {
        var provider: Provider = .deepseek
        var key: String = ""
        var model: String = ""
        var base: String = ""
        var fetchedModels: [String] = []
        var fetchNote: String?
    }

    @Published var draft = SettingsDraft()
    @Published var isFetchingModels: Bool = false
    @Published var fetchedModelsByProvider: [String: [String]] = [:]

    var draftProvider: Provider {
        get { draft.provider }
        set { draft.provider = newValue }
    }
    var draftKey: String {
        get { draft.key }
        set { draft.key = newValue }
    }
    var draftModel: String {
        get { draft.model }
        set { draft.model = newValue }
    }
    var draftBase: String {
        get { draft.base }
        set { draft.base = newValue }
    }
    var draftFetchedModels: [String] {
        get { draft.fetchedModels }
        set { draft.fetchedModels = newValue }
    }
    var modelFetchNote: String? {
        get { draft.fetchNote }
        set { draft.fetchNote = newValue }
    }

    private var translateTask: Task<Void, Never>?
    private var autoTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isSwitchingTab = false

    private init() {
        preferences.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isSwitchingTab else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        history.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        $sourceText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.scheduleAutoTranslate(for: text)
            }
            .store(in: &cancellables)
    }

    var provider: Provider {
        preferences.provider
    }

    var languageTarget: LanguageTarget {
        get { preferences.languageTarget }
        set {
            preferences.languageTarget = newValue
            objectWillChange.send()
        }
    }

    var autoTranslate: Bool {
        get { preferences.autoTranslate }
        set {
            preferences.autoTranslate = newValue
            objectWillChange.send()
        }
    }

    var autoCopyResult: Bool {
        get { preferences.autoCopyResult }
        set {
            preferences.autoCopyResult = newValue
            objectWillChange.send()
        }
    }

    var tone: TranslationTone {
        get { preferences.tone }
        set {
            preferences.tone = newValue
            objectWillChange.send()
        }
    }

    var canTranslate: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preferences.currentIsReady
            && !isTranslating
            && (activeTab == .translate || activeTab == .history)
    }

    var currentEngineLabel: String {
        let p = preferences.provider
        let model = preferences.model(for: p)
        if p.isCustom {
            let name = model.isEmpty ? "未配置模型" : model
            return "\(p.shortName) · \(name)"
        }
        return "\(p.shortName) · \(model)"
    }

    func modelsForEngineMenu(_ provider: Provider) -> [String] {
        var list: [String] = []
        let current = preferences.model(for: provider)
        if !current.isEmpty { list.append(current) }
        if let fetched = fetchedModelsByProvider[provider.rawValue] {
            for m in fetched where !list.contains(m) { list.append(m) }
        }
        for m in provider.suggestedModels where !list.contains(m) { list.append(m) }
        return list
    }

    func selectEngine(provider: Provider, model: String) {
        preferences.provider = provider
        preferences.setModel(model, for: provider)
        errorMessage = nil
        let note = "\(provider.shortName) · \(model.isEmpty ? "请配置" : model)"
        statusNote = note
        objectWillChange.send()
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if statusNote == note { statusNote = nil }
        }
    }

    func selectTab(_ tab: MainTab) {
        if tab == .settings {
            openSettings()
            return
        }
        guard activeTab != tab else { return }
        isSwitchingTab = true
        activeTab = tab
        isSwitchingTab = false
    }

    /// Blank quick dialog (double-tap ⌘).
    func openBlankQuickDialog() {
        surface = .hotkey
        quickSource = ""
        quickResult = ""
        quickError = nil
        quickBusy = false
        quickCopied = false
    }

    /// Selection bubble → fill quick dialog and translate immediately.
    func ingestSelectionForQuickTranslate(_ text: String) {
        surface = .hotkey
        quickSource = text
        quickResult = ""
        quickError = nil
        quickBusy = false
        quickCopied = false
        runQuickTranslate()
    }

    func quickPasteClipboard() {
        if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
            quickSource = str
            quickError = nil
        }
    }

    func copyQuickResult() {
        guard !quickResult.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(quickResult, forType: .string)
        quickCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if self.quickCopied { self.quickCopied = false }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let ok = LaunchAtLogin.setEnabled(enabled)
        launchAtLogin = LaunchAtLogin.isEnabled
        if !ok {
            statusNote = "设置开机自启动失败：\(LaunchAtLogin.statusLabel)"
        } else {
            statusNote = enabled ? "已开启开机自启动" : "已关闭开机自启动"
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if self.statusNote?.contains("自启动") == true { self.statusNote = nil }
        }
    }

    /// Close panel UI — keep app alive in menu bar (do not quit).
    func closePanels() {
        QuickPanelController.shared.hide()
        if surface == .hotkey {
            return
        }
        // Try to dismiss MenuBarExtra window without terminating
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("MenuBarExtra") || name.contains("StatusBar") {
                window.orderOut(nil)
            }
        }
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    /// Compact dialog translate (does not switch main tab).
    func runQuickTranslate() {
        let trimmed = quickSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            quickError = "请输入要翻译的内容"
            return
        }

        if LanguageDetector.isSameLanguage(trimmed, language: preferences.languageTarget) {
            quickError = "原文已是「\(preferences.languageTarget.targetLanguageName)」，无需翻译"
            quickResult = ""
            quickBusy = false
            return
        }

        let provider = preferences.provider
        let apiKey = preferences.apiKey(for: provider)
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            quickError = "未配置 \(provider.displayName) API Key，请打开菜单栏设置"
            return
        }

        let model = preferences.model(for: provider)
        let baseURL = preferences.baseURL(for: provider)
        if provider.isCustom {
            if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                quickError = "自定义引擎需配置 Base URL 与模型"
                return
            }
        }

        let language = preferences.languageTarget
        let source = trimmed

        quickTask?.cancel()
        quickBusy = true
        quickError = nil
        quickResult = ""

        quickTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await TranslationService.shared.translate(
                    text: source,
                    language: language,
                    tone: self.preferences.tone,
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    baseURL: baseURL,
                    onDelta: { [weak self] piece in
                        Task { @MainActor in
                            guard let self else { return }
                            self.quickResult += piece
                        }
                    }
                )
                self.quickResult = result.text
                if let usage = result.usage {
                    self.usage.record(provider: provider, model: model, usage: usage)
                }
                self.history.append(
                    source: source,
                    result: result.text,
                    provider: provider,
                    model: model,
                    language: language
                )
                if self.preferences.autoCopyResult {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    self.quickCopied = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        if self.quickCopied { self.quickCopied = false }
                    }
                }
                self.quickBusy = false
            } catch is CancellationError {
                self.quickBusy = false
            } catch {
                self.quickBusy = false
                self.quickError = error.localizedDescription
            }
        }
    }

    // MARK: - Settings page

    func openSettings(for provider: Provider? = nil) {
        let p = provider ?? preferences.provider
        if activeTab != .settings {
            returnTab = activeTab
        }
        draft = SettingsDraft(
            provider: p,
            key: preferences.apiKey(for: p),
            model: preferences.model(for: p),
            base: preferences.baseURL(for: p),
            fetchedModels: fetchedModelsByProvider[p.rawValue] ?? [],
            fetchNote: nil
        )
        activeTab = .settings
        errorMessage = nil
    }

    func leaveSettings() {
        let target = returnTab == .settings ? .translate : returnTab
        activeTab = target
    }

    func reloadDrafts(for provider: Provider) {
        preferences.setAPIKey(draft.key, for: draft.provider)
        preferences.setModel(draft.model, for: draft.provider)
        preferences.setBaseURL(draftBaseEffective, for: draft.provider)

        draft = SettingsDraft(
            provider: provider,
            key: preferences.apiKey(for: provider),
            model: preferences.model(for: provider),
            base: preferences.baseURL(for: provider),
            fetchedModels: fetchedModelsByProvider[provider.rawValue] ?? [],
            fetchNote: nil
        )
    }

    func resetDraftEndpoints() {
        draft.model = draft.provider.defaultModel
        draft.base = draft.provider.defaultBaseURL
        draft.fetchedModels = []
        draft.fetchNote = nil
    }

    var draftBaseEffective: String {
        let trimmed = draft.base.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.provider.isCustom { return trimmed }
        return trimmed.isEmpty ? draft.provider.defaultBaseURL : trimmed
    }

    func fetchDraftModels() {
        let provider = draft.provider
        let key = draft.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = draftBaseEffective

        guard !key.isEmpty else {
            draft.fetchNote = "请先填写 API Key"
            return
        }
        if base.isEmpty {
            draft.fetchNote = "请先填写 Base URL"
            return
        }

        isFetchingModels = true
        draft.fetchNote = "正在获取模型列表…"

        Task {
            do {
                let models = try await ModelCatalogService.shared.fetchModels(
                    baseURL: base,
                    apiKey: key
                )
                self.fetchedModelsByProvider[provider.rawValue] = models
                var d = self.draft
                d.fetchedModels = models
                d.fetchNote = "已获取 \(models.count) 个模型"
                if d.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let first = models.first {
                    d.model = first
                }
                self.draft = d
            } catch {
                var d = self.draft
                d.fetchedModels = self.fetchedModelsByProvider[provider.rawValue] ?? []
                d.fetchNote = error.localizedDescription
                self.draft = d
            }
            self.isFetchingModels = false
        }
    }

    func saveSettings() {
        preferences.setAPIKey(draft.key, for: draft.provider)
        preferences.setModel(draft.model, for: draft.provider)
        preferences.setBaseURL(draftBaseEffective, for: draft.provider)
        preferences.provider = draft.provider

        if draft.provider.isCustom && !preferences.currentIsReady {
            statusNote = "自定义引擎未配置完整"
        } else {
            statusNote = "已启用 \(draft.provider.shortName)"
        }
        let note = statusNote ?? ""
        let target = returnTab == .settings ? .translate : returnTab
        activeTab = target
        errorMessage = nil
        objectWillChange.send()
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if statusNote == note { statusNote = nil }
        }
    }

    func openKeyPortal(_ provider: Provider) {
        let urlString: String
        switch provider {
        case .deepseek:
            urlString = "https://platform.deepseek.com/api_keys"
        case .mimo:
            urlString = "https://platform.xiaomimimo.com"
        case .glm:
            urlString = "https://bigmodel.cn/usercenter/proj-mgmt/apikeys"
        case .custom:
            return
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Editing

    func swapLanguages() {
        if let swapped = preferences.languageTarget.swapped {
            preferences.languageTarget = swapped
            let oldSource = sourceText
            sourceText = resultText
            resultText = oldSource
        }
    }

    func clearAll() {
        translateTask?.cancel()
        translateTask = nil
        autoTask?.cancel()
        sourceText = ""
        resultText = ""
        errorMessage = nil
        statusNote = nil
        isTranslating = false
        streamingCursor = false
        lastUsage = nil
    }

    func pasteFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
            sourceText = str
            errorMessage = nil
        }
    }

    func copyResult() {
        guard !resultText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        copiedFlash = true
        statusNote = "已复制译文"
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if self.copiedFlash { self.copiedFlash = false }
            if self.statusNote == "已复制译文" { self.statusNote = nil }
        }
    }

    // MARK: - History

    func retranslateHistory(_ item: TranslationHistoryItem) {
        sourceText = item.source
        resultText = ""
        preferences.provider = item.provider
        preferences.languageTarget = item.language
        activeTab = .translate
        surface = .menuBar
        objectWillChange.send()
        translate()
    }

    // MARK: - Translate

    func translate() {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请输入要翻译的内容"
            return
        }

        // Same language → target: skip API to save tokens
        if LanguageDetector.isSameLanguage(trimmed, language: preferences.languageTarget) {
            errorMessage = "原文已是「\(preferences.languageTarget.targetLanguageName)」，无需翻译"
            statusNote = nil
            isTranslating = false
            streamingCursor = false
            return
        }

        let provider = preferences.provider
        let apiKey = preferences.apiKey(for: provider)
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            openSettings(for: provider)
            errorMessage = "请先在设置中配置 \(provider.displayName) 的 API Key"
            return
        }

        let model = preferences.model(for: provider)
        let baseURL = preferences.baseURL(for: provider)

        if provider.isCustom {
            if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                openSettings(for: provider)
                errorMessage = "请先填写自定义 Base URL"
                return
            }
            if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                openSettings(for: provider)
                errorMessage = "请填写模型 ID，或点击「获取模型」"
                return
            }
        }

        translateTask?.cancel()

        let language = preferences.languageTarget
        let source = trimmed

        isTranslating = true
        errorMessage = nil
        statusNote = "正在翻译…"
        streamingCursor = true
        resultText = ""
        lastUsage = nil
        if activeTab == .settings || activeTab == .history || activeTab == .usage {
            activeTab = .translate
        }

        translateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await TranslationService.shared.translate(
                    text: source,
                    language: language,
                    tone: self.preferences.tone,
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    baseURL: baseURL,
                    onDelta: { [weak self] piece in
                        Task { @MainActor in
                            guard let self else { return }
                            self.resultText += piece
                        }
                    }
                )
                self.resultText = result.text
                self.lastUsage = result.usage
                if let usage = result.usage {
                    self.usage.record(provider: provider, model: model, usage: usage)
                    let total = UsageStore.formatTokens(usage.totalTokens)
                    self.statusNote = "\(provider.shortName) · \(total) tokens"
                } else {
                    self.statusNote = "\(provider.shortName) · \(model)"
                }

                self.history.append(
                    source: source,
                    result: result.text,
                    provider: provider,
                    model: model,
                    language: language
                )

                if self.preferences.autoCopyResult {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    self.copiedFlash = true
                    if var note = self.statusNote {
                        note += " · 已复制"
                        self.statusNote = note
                    } else {
                        self.statusNote = "已复制译文"
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        if self.copiedFlash { self.copiedFlash = false }
                    }
                }

                self.isTranslating = false
                self.streamingCursor = false
            } catch is CancellationError {
                self.isTranslating = false
                self.streamingCursor = false
                self.statusNote = nil
            } catch {
                self.isTranslating = false
                self.streamingCursor = false
                self.errorMessage = error.localizedDescription
                self.statusNote = nil
            }
        }
    }

    private func scheduleAutoTranslate(for text: String) {
        autoTask?.cancel()
        guard preferences.autoTranslate else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, preferences.currentIsReady else { return }

        autoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let self else { return }
            let current = self.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == trimmed, !current.isEmpty else { return }
            if !self.isTranslating {
                self.translate()
            }
        }
    }
}
