# Voicer UI 优化 + API 语音识别 设计方案

**日期:** 2026-04-27  
**状态:** 已批准，待实施  
**作者:** OpenCode (Brainstorming Session)

---

## 1. 背景与目标

Voicer 是一个 macOS 原生语音输入工具，用户按住 Fn 键录音，松开后文字自动注入当前输入框。当前版本存在以下问题：

1. **浮动面板简陋** — 位于屏幕底部中央，设计粗糙，文字清晰度不足，动画简陋
2. **多语言切换不便** — 需要在菜单栏手动选择语言，无法处理中英日韩混说场景
3. **Apple Speech 多语言混合识别差** — 固定 locale 模式下，跨语言识别准确度低

本次设计目标：
- 将浮动面板改造为 **Apple 原生灵动岛风格**，位于屏幕顶部中央
- 优化文字清晰度、动画质感、状态指示
- 引入 **第三方 API 语音识别**（Whisper 兼容 API）实现自动多语言混合识别
- 复用现有 LLM API 配置，最小化用户配置成本

---

## 2. 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│  User Input (Fn Key)                                        │
│     ↓                                                       │
│  FnKeyMonitor ──→ RecordingCoordinator                      │
│     ↓                                                       │
│  AudioEngine (录音) + FloatingPanelController (面板显示)      │
│     ↓                                                       │
│  SpeechEngine (本地 Apple Speech) ──→ 实时预览文字            │
│     ↓                                                       │
│  [用户松开 Fn]                                               │
│     ↓                                                       │
│  录音结束 → AudioEngine.stop()                               │
│     ↓                                                       │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Speech API 识别 (可选，异步)                        │    │
│  │  - 将录音文件 POST 到 Whisper API                   │    │
│  │  - 返回最终文字 (支持多语言自动检测)                 │    │
│  │  - 失败时 fallback 到本地 Speech 结果               │    │
│  └─────────────────────────────────────────────────────┘    │
│     ↓                                                       │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  LLM 润色 (可选，现有功能)                           │    │
│  └─────────────────────────────────────────────────────┘    │
│     ↓                                                       │
│  TextInjector (注入当前输入框)                               │
│     ↓                                                       │
│  FloatingPanelController.hide() (面板缩回消失)              │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 灵动岛风格浮动面板

### 3.1 位置与尺寸

- **位置:** 屏幕顶部中央，主屏幕水平居中，y 坐标约菜单栏下方 12px
- **初始尺寸（录音中）:** 高度 56px，宽度约 240-280px
- **展开尺寸（处理中）:** 高度不变，宽度动态扩展到 320-480px（根据文字长度）
- **圆角:** 28px（高度的一半），形成完美的胶囊形状

### 3.2 三种状态设计

#### 状态 1: 录音中 (Recording)

| 属性 | 值 |
|---|---|
| 形状 | 细长胶囊 |
| 背景 | `NSVisualEffectView(material: .hudWindow)` + 微妙阴影 |
| 左侧 | `WaveformView` — 5 段音波动画，带平滑过渡和光晕 |
| 中间 | 文字 "正在聆听…" |
| 右侧 | 绿色脉冲指示灯（`#34C759`），表示正在录音 |
| 文字样式 | `systemFont(ofSize: 16, weight: .semibold)`，白色，带 `NSShadow` |

#### 状态 2: 处理中 (Processing)

| 属性 | 值 |
|---|---|
| 形状 | 胶囊展开 |
| 背景 | 同上 |
| 内容 | 根据处理阶段显示不同文字： |
| | - "正在识别…"（Speech API 阶段）|
| | - "正在润色…"（LLM 阶段）|
| 指示器 | 旋转的 `NSProgressIndicator`（indeterminate）或自定义旋转动画 |

#### 状态 3: 完成/消失 (Complete)

- 面板不显示最终文字
- 使用 `NSAnimationContext` 平滑缩回（scale + alpha）后 `orderOut`
- 文字直接由 `TextInjector` 注入当前输入框

### 3.3 文字清晰度优化

为了确保在各种屏幕（Retina / 非 Retina）上都绝对清晰：

```swift
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -1)
shadow.shadowBlurRadius = 0
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)

label.font = .systemFont(ofSize: 16, weight: .semibold)
label.textColor = .white
label.shadow = shadow
```

### 3.4 波形动画优化

- 保留 5 段式结构，但增加 `CALayer` 的 `shadow` 实现光晕效果
- `attack: 0.35`, `release: 0.12`（比当前更灵敏）
- 每段柱子的颜色带轻微渐变（中心亮，边缘暗）
- 使用 `CADisplayLink` 保持 60fps 刷新

---

## 4. 第三方 API 语音识别

### 4.1 双引擎策略

| 阶段 | 引擎 | 用途 | 准确性 |
|---|---|---|---|
| 录音中 | Apple SFSpeechRecognizer | 实时预览文字 | 中等 |
| 录音后 | Whisper API (HTTP) | 最终识别结果 | 高，支持多语言混合 |

**原因:** 录音过程中需要极低延迟的实时反馈，Apple Speech 本地运行最适合；录音结束后需要最终准确度，Whisper API 最适合。

### 4.2 API 调用流程

```
1. 用户松开 Fn → RecordingCoordinator.stopRecording()
2. AudioEngine.stop() → 保存录音为临时 .m4a / .wav 文件
3. 如果 AppSettings.speechAPIEnabled == true:
   a. FloatingPanelController 切换到 "正在识别…"
   b. SpeechAPIClient.transcribe(audioFile:) 异步调用
   c. 成功 → 用 API 结果替换本地文字
   d. 失败 → 使用本地 Speech 结果（fallback）
4. 继续现有 LLM 润色流程（如果开启）
```

### 4.3 API 请求格式

兼容 OpenAI Whisper API：

```http
POST {baseURL}/audio/transcriptions
Authorization: Bearer {apiKey}
Content-Type: multipart/form-data

form-data:
  file: <audio_file>
  model: {speechModel}  // e.g. "whisper-1"
  response_format: "json"
```

响应：
```json
{
  "text": "最终识别结果"
}
```

### 4.4 Fallback 策略

| 场景 | 行为 |
|---|---|
| API 返回错误 | 使用本地 Speech 结果，静默降级 |
| API 超时（>15s）| 使用本地 Speech 结果 |
| API 返回空文字 | 使用本地 Speech 结果 |
| 网络不可用 | 使用本地 Speech 结果 |
| 用户未开启 API 识别 | 保持现有纯本地行为 |

---

## 5. LLM Settings 配置变更

### 5.1 Provider 预设下拉选择（新增）

将原有的"API Base URL"文本输入框替换为 **Provider 下拉选择框**，用户只需：
1. 选择预设 Provider
2. 填入 API Key
3. （可选）修改 Model

**UI 布局更新：**

```
┌─────────────────────────────────────────┐
│  LLM Settings                             │
│                                           │
│  Provider:      [▼ OpenAI           ]     │
│  API Base URL:  [https://api.openai.com]  │  ← 预设时隐藏/只读，自定义时显示
│  API Key:       [________________]        │
│  Model:         [gpt-4o-mini      ]       │
│                                           │
│  ☑ Use API for Speech Recognition         │
│  Speech Model:  [whisper-1      ]         │
│                                           │
│  [Test]  [Save]                           │
└─────────────────────────────────────────┘
```

**预设 Provider 列表（18 个，全部兼容 OpenAI 格式）：**

| Provider | Base URL | Default Model |
|---|---|---|
| OpenAI | https://api.openai.com | gpt-4o-mini |
| DeepSeek | https://api.deepseek.com | deepseek-chat |
| Moonshot (Kimi) | https://api.moonshot.cn | moonshot-v1-8k |
| 智谱 AI (GLM) | https://open.bigmodel.cn/api/paas | glm-4-flash |
| ByteDance (豆包) | https://ark.cn-beijing.volces.com/api | doubao-lite-4k |
| Alibaba (通义千问) | https://dashscope.aliyuncs.com/compatible-mode | qwen-turbo |
| Baichuan (百川) | https://api.baichuan-ai.com | Baichuan4 |
| MiniMax | https://api.minimax.chat | abab6.5s-chat |
| 零一万物 (01.AI) | https://api.lingyiwanwu.com | yi-lightning |
| 阶跃星辰 (StepFun) | https://api.stepfun.com | step-1-8k |
| Groq | https://api.groq.com/openai | llama-3.1-8b |
| xAI (Grok) | https://api.x.ai | grok-2 |
| Mistral AI | https://api.mistral.ai | mistral-small |
| Cohere | https://api.cohere.ai | command-r |
| Perplexity | https://api.perplexity.ai | llama-3.1-sonar-small |
| Fireworks AI | https://api.fireworks.ai/inference | accounts/fireworks/models/llama-v3p1-8b |
| SiliconFlow | https://api.siliconflow.cn | Qwen/Qwen2.5-7B-Instruct |
| 自定义 (Custom) | — | — |

> 注：所有预设 Provider 均采用 OpenAI 兼容 API 格式（`/v1/chat/completions`），确保与现有 `LLMClient` 的请求逻辑一致。不兼容此格式的 Provider（如 Azure OpenAI、Anthropic、Google Gemini、百度文心等）暂不在预设列表中，用户可通过「自定义」模式自行配置。

**交互逻辑：**
- 选择预设 Provider：自动填充 Base URL（隐藏）和 Model；用户仅需填 Key
- 选择"自定义"：显示 Base URL 输入框，读/写 `AppSettings.llmBaseURL`
- 切换 Provider 时：自动覆盖 Model 为对应默认值（用户通常是切换整套配置）
- 窗口高度从 220px 略增至 240px 以容纳下拉框

**数据模型：**
- 新增 `llmProviderName: String`（默认 `"OpenAI"`），用于持久化用户选择的 Provider
- 保留 `llmBaseURL`，仅在"自定义"模式下读写

**向后兼容（升级迁移）：**
老用户没有 `llmProviderName` 字段。首次读取时，根据已有 `llmBaseURL` 反向匹配预设列表中的 `baseURL`，匹配成功则设为对应 Provider，否则设为"自定义"。

### 5.2 Speech API 开关（原有）

```
☑ Use API for Speech Recognition
Speech Model:  [whisper-1      ]
```

新增字段：
- `speechAPIEnabled: Bool`（默认 `false`）
- `speechModel: String`（默认 `"whisper-1"`）

Base URL 和 API Key 复用 LLM 的配置。

---

## 6. Menu Bar 变更

移除 `MenuBarManager` 中的 **Language** 子菜单。原因：
- 本地 Speech 不再需要手动选择语言（如果用户未开启 API，保持 `.autoupdatingCurrent`）
- API Speech 自动检测语言

菜单栏保留：
- LLM Refinement（开关 + Settings）
- Quit

---

## 7. 数据模型变更

### AppSettings 新增字段

```swift
final class AppSettings {
    // 现有字段...
    
    // LLM Provider 预设（新增）
    var llmProviderName: String  // 默认 "OpenAI"
    
    // Speech API（原有）
    @UserDefault("speechAPIEnabled", defaultValue: false)
    var speechAPIEnabled: Bool
    
    @UserDefault("speechModel", defaultValue: "whisper-1")
    var speechModel: String
}
```

### LLMProvider 数据模型（新增）

```swift
struct LLMProvider {
    let name: String           // 显示名称，如 "OpenAI"
    let baseURL: String        // 如 "https://api.openai.com"
    let defaultModel: String   // 如 "gpt-4o-mini"
    
    static let all: [LLMProvider] = [
        LLMProvider(name: "OpenAI", baseURL: "https://api.openai.com", defaultModel: "gpt-4o-mini"),
        LLMProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com", defaultModel: "deepseek-chat"),
        // ... 其余 22 个预设
        LLMProvider(name: "Custom", baseURL: "", defaultModel: ""),
    ]
}
```

---

## 8. 文件变更清单

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `FloatingPanelController.swift` | 重写 | 灵动岛风格，三种状态管理，位置改为顶部中央 |
| `WaveformView.swift` | 修改 | 增加光晕效果，优化动画参数 |
| `RecordingCoordinator.swift` | 修改 | 集成 API 识别流程，双引擎协调 |
| `SpeechAPIClient.swift` | 新增 | 负责音频文件上传和 Whisper API 调用 |
| `LLMSettingsWindowController.swift` | 修改 | 改为 Provider 下拉框；新增 Speech API 开关和模型输入框 |
| `MenuBarManager.swift` | 修改 | 移除 Language 菜单 |
| `LLMProvider.swift` | 新增 | 18 个兼容 OpenAI 格式的预设 Provider 数据模型 |
| `AppSettings.swift` | 修改 | 新增 `speechAPIEnabled`、`speechModel` |
| `AppDelegate.swift` | 修改 | 调整流程：本地预览 → API 识别 → LLM 润色 |

---

## 9. 错误处理

| 错误场景 | 处理策略 |
|---|---|
| Speech API 网络错误 | Fallback 到本地结果，不弹窗打扰用户 |
| Speech API 返回非 200 | Fallback 到本地结果 |
| 录音文件保存失败 | 使用本地结果，打印日志 |
| 音频格式不兼容 API | 转码为 WAV 后上传 |
| LLM 润色失败 | 保持 API/本地识别结果，不注入 |

---

## 10. 性能考量

- **录音文件大小:** 10 秒语音约 160KB (AAC) → 上传时间 < 2s（正常网络）
- **API 响应时间:** Whisper API 通常在 1-5s 内返回
- **内存:** 录音文件使用临时目录，识别完成后立即删除
- **并发:** 用户连续按 Fn 时，需要取消前一次的 API 请求（使用 `Task` + `cancel`）

---

## 11. 未来扩展（非本次范围）

- **纯本地 Whisper:** 引入 whisper.cpp，零网络依赖，但增加包体积
- **自定义提示词:** 允许用户在 Speech API 请求中附加 `prompt`，提高专业术语识别率
- **实时 API 流式识别:** 使用 OpenAI Realtime API 实现真正的流式多语言识别
- **历史记录面板:** 新增主窗口，查看和管理历史语音输入记录

---

## 12. 设计决策记录

| 决策 | 选择 | 理由 |
|---|---|---|
| UI 框架 | 继续使用 AppKit | 已有成熟代码，灵动岛效果用 AppKit 完全可以实现 |
| API 识别开关默认 | 关闭 | 保护现有用户行为，不强制要求 API Key |
| Base URL/API Key 复用 | 是 | 减少用户配置成本，大多数提供商（OpenAI、Groq）同时支持 LLM 和 Speech |
| 本地 Speech 实时预览保留 | 是 | 提供即时反馈，让用户知道麦克风在工作 |
| 移除 Language 菜单 | 是 | API 自动检测 + 本地 fallback，不再需要手动选择 |
| 完成时不显示文字 | 是 | 文字直接注入输入框，减少视觉干扰 |
| Provider 下拉替代手动 URL | 是 | 减少用户配置成本，避免填错 URL；自定义选项保留灵活性 |
| 切换 Provider 覆盖 Model | 是 | 用户切换 Provider 通常意味着换整套配置，自动同步更自然 |
| 预设 Provider 隐藏 Base URL | 是 | 大多数用户不需要看到/修改 URL，界面更简洁 |
| 自定义模式保留 Base URL 输入 | 是 | 兼容私有部署、代理、自托管等场景 |

---

*本设计文档经用户审查确认后，进入 writing-plans 阶段制定具体实施计划。*
