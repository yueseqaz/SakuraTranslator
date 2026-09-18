# Sakura Translator

macOS 菜单栏翻译应用。点击菜单栏图标弹出玻璃面板，用大模型 API 做翻译；支持 Token 用量与人民币成本估算。

## 功能

- 菜单栏常驻，高透明玻璃 UI
- 页签：**翻译 | 历史 | 用量 | 设置**
- 引擎：DeepSeek / 小米 MiMo / 智谱 GLM / 自定义 OpenAI 兼容
- 模型可在翻译页徽章切换；设置页配 Key / Base URL / 模型（可拉取 `/models`）
- 流式译文、`⌘↩` 翻译
- **全局快捷键**
  - `⌥⌘T`：剪贴板 → 浮动面板并填入（开自动翻译则直接译）
  - `⌥⌘S`：选中文本（辅助功能）→ 浮动面板并翻译
- **翻译历史**：最近 10 条，可复制原文/译文、再次翻译
- **自动复制译文**（设置可关）
- 自动翻译开关（关闭则只手动）
- Token 用量 + **人民币成本估算**（自定义不计）

## 环境

- macOS 13+（构建目标 14.0，本机验证 macOS 27）
- Xcode Command Line Tools：
  ```bash
  xcode-select --install
  ```

## 构建

```bash
cd /Users/sakura/Code/SakuraTranslator
./build.sh
```

产物：`dist/SakuraTranslator.app`

## 安装

```bash
./install.sh
# 或
open /Users/sakura/Code/SakuraTranslator/dist/SakuraTranslator.app
```

会安装到 `/Applications/Sakura Translator.app`，并清理旧的 Glass Translate 包。

## 配置

1. 菜单栏点开 → 页签「设置」
2. 配置**当前引擎**（在翻译页顶部徽章里切换 DeepSeek / MiMo / GLM / 自定义）
3. 填写 API Key；自定义还需 Base URL
4. 模型：点「获取模型」或手动填
5. 「保存并返回」

| 引擎 | Base URL 默认 | 默认模型 |
|------|----------------|----------|
| DeepSeek | `https://api.deepseek.com` | `deepseek-flash` |
| 小米 MiMo | `https://api.xiaomimimo.com/v1` | `mimo-v2.5` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-5.3-flash` |
| 自定义 | 自行填写 OpenAI 兼容地址 | 手动 / 拉取 |

## 成本估算（人民币）

统一按 **¥ / 100 万 tokens** 显示：

| 引擎 | 模型 | 输入 | 输出 | 依据 |
|------|------|------|------|------|
| DeepSeek | flash | ≈¥1.09 | ≈¥4.35 | 官网 USD × 7.25（谷时·未命中缓存） |
| DeepSeek | v4-pro | ≈¥4.79 | ≈¥14.36 | 同上；峰时约 ×2 |
| MiMo | v2.5 | ≈¥1.02 | ≈¥2.03 | 参考价折算 |
| MiMo | v2.5-pro | ≈¥3.15 | ≈¥6.31 | 参考价折算 |
| 智谱 | glm-5.3-flash | ¥0.8 | ¥2.8 | 官方 API 定价 |
| 智谱 | glm-5.3 / 5.2 | ¥8 | ¥28 | 官方 API 定价 |
| 智谱 | glm-4-flash 等 | 免费 | 免费 | 官方 |
| 自定义 | — | 不计 | 不计 | — |

说明：本地刊例估算，**不是账单**；DeepSeek 未拆缓存命中；MiMo 以开放平台控制账单为准。

## 项目结构

```
SakuraTranslator/
├── Sources/              # Swift 源码
├── Resources/Info.plist
├── build.sh              # 命令行编译打包
├── install.sh            # 安装到 /应用程序
└── dist/SakuraTranslator.app
```

## 清理旧构建

```bash
# 源码目录只保留最新 dist
./build.sh

# 应用目录只保留 Sakura Translator
rm -rf "/Applications/Glass Translate.app"
```

## 技术说明

- 无 Xcode IDE，纯 `swiftc` 编译菜单栏 App（`LSUIElement`）
- Command Line Tools 无 SwiftUI 宏插件，故状态用 `ObservableObject` 而非 `@State`
- 密钥与用量记录仅存本机 `UserDefaults`
