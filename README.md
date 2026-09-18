# Sakura Translator

macOS 菜单栏翻译工具。点击菜单栏图标弹出玻璃面板，调用大模型 API 完成翻译；支持 Token 用量统计、人民币成本估算、全局快捷键与最近历史。

## 功能

| 模块 | 说明 |
|------|------|
| 翻译 | 流式输出；`⌘↩` 发送；语言方向可选（自动→中/英/日/韩、中英互译） |
| 引擎 | DeepSeek / 小米 MiMo / 智谱 GLM / 自定义 OpenAI 兼容接口 |
| 模型 | 翻译页徽章快速切换；设置里可手动填 ID 或从 `/models` 拉取列表 |
| 快捷键 | `⌥⌘T` 剪贴板唤出；`⌥⌘S` 划词翻译（需辅助功能权限） |
| 历史 | 最近 10 条，可复制原文/译文、再次翻译 |
| 用量 | Token 与预估成本（人民币）；自定义引擎不计费 |
| 自动化 | 输入防抖自动翻译、翻译后自动复制译文（均可在设置关闭） |

## 环境要求

- macOS 14+（开发验证：macOS 27 / Apple Silicon）
- [Xcode Command Line Tools](https://developer.apple.com/download/all/)（无需完整 Xcode）：

```bash
xcode-select --install
```

- 各引擎的 API Key（自备）

## 快速开始

```bash
git clone https://github.com/yueseqaz/SakuraTranslator.git
cd SakuraTranslator
./build.sh          # 编译 → dist/SakuraTranslator.app
./install.sh        # 安装到 /Applications/Sakura Translator.app 并启动
```

也可直接：

```bash
open dist/SakuraTranslator.app
```

## 使用

1. 点击菜单栏气泡图标，打开面板  
2. 页签切换：**翻译 / 历史 / 用量 / 设置**  
3. 在翻译页顶部徽章选择引擎（DeepSeek / MiMo / GLM / 自定义）  
4. **设置**页填写 API Key、Base URL、模型；点「获取模型」可拉取列表  
5. 「保存并返回」后即可翻译  

### 全局快捷键

| 快捷键 | 行为 |
|--------|------|
| `⌥⌘T` | 读取剪贴板 → 浮动面板填入（若开启自动翻译则直接译） |
| `⌥⌘S` | 读取选中文本 → 浮动面板并翻译 |

划词需在 **系统设置 → 隐私与安全性 → 辅助功能** 中允许 Sakura Translator。

### 引擎默认值

| 引擎 | 默认 Base URL | 默认模型 |
|------|----------------|----------|
| DeepSeek | `https://api.deepseek.com` | `deepseek-flash` |
| 小米 MiMo | `https://api.xiaomimimo.com/v1` | `mimo-v2.5` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-5.3-flash` |
| 自定义 | 任意 OpenAI 兼容地址 | 手动填写或拉取 |

密钥与历史、用量记录仅保存在本机 `UserDefaults`，不会上传。

## 成本估算说明

用量页按 **¥ / 100 万 tokens** 做本地估算（**不是账单**）：

| 引擎 | 模型 | 输入 | 输出 | 依据 |
|------|------|------|------|------|
| DeepSeek | flash | ≈¥1.09 | ≈¥4.35 | 官网 USD × 7.25（谷时·未命中缓存） |
| DeepSeek | v4-pro | ≈¥4.79 | ≈¥14.36 | 同上；峰时约 ×2 |
| MiMo | v2.5 | ≈¥1.02 | ≈¥2.03 | 参考价折算，以小米控制台为准 |
| MiMo | v2.5-pro | ≈¥3.15 | ≈¥6.31 | 同上 |
| 智谱 GLM | glm-5.3-flash | ¥0.8 | ¥2.8 | 官方 API 定价 |
| 智谱 GLM | glm-5.3 / 5.2 | ¥8 | ¥28 | 官方 API 定价 |
| 智谱 GLM | glm-4-flash 等 | 免费 | 免费 | 官方 |
| 自定义 | — | 不计 | 不计 | — |

DeepSeek 未拆分缓存命中 token；价格若调整请以各平台最新刊例为准。

## 项目结构

```
SakuraTranslator/
├── Sources/                 # Swift 源码（SwiftUI + AppKit）
├── Resources/
│   ├── Info.plist
│   └── AppIcon.icns         # 应用图标
├── build.sh                 # swiftc 命令行编译打包
├── install.sh               # 安装到 /Applications
└── dist/                    # 本地构建产物（不入库）
```

## 开发说明

- 使用 **Swift Package 无关的纯 `swiftc` 构建**，不依赖 Xcode IDE；菜单栏应用通过 `LSUIElement` 隐藏 Dock 图标。
- Command Line Tools 环境缺少 SwiftUI 宏插件，因此状态管理使用 `ObservableObject`，而不是 `@State` / `@StateObject`。
- 修改 `Sources/` 后重新执行：

```bash
./build.sh && ./install.sh
```

- 推送示例：

```bash
git add .
git commit -m "your message"
git push
```

## Privacy

- API Key、模型配置、翻译历史、Token 用量均仅存本机  
- 翻译请求会发送到你所配置的模型服务（DeepSeek / 小米 / 智谱 / 自定义端点）  
- 本应用不包含分析上报或第三方统计 SDK  

## License

暂未添加开源许可证。若需公开复用，请先联系作者或自行补充 License 文件。
