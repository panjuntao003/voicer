# Voicer

A macOS native voice input tool with Dynamic Island-style UI. Press and hold **Fn** to record, release to inject text into any input field — with automatic multilingual speech recognition and optional LLM refinement.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
</p>

## Features

- **Press Fn to talk** — Hold Fn key to start recording, release to transcribe and inject text
- **Dynamic Island UI** — Floating panel at top of screen with waveform animation, status indicators, and smooth transitions
- **Automatic multilingual recognition** — Uses Apple Speech for real-time preview, optional Whisper API for high-accuracy final transcription (supports Chinese, English, Japanese, Korean, etc.)
- **LLM refinement** — Optional text polishing via LLM API (OpenAI, DeepSeek, Groq, etc.)
- **18 provider presets** — One-click configuration for OpenAI, DeepSeek, Groq, and 15 more OpenAI-compatible providers
- **Dual-engine strategy** — Local Apple Speech for instant feedback + API for accuracy, with automatic fallback
- **Native macOS** — Pure AppKit, no Electron, no SwiftUI. Lightweight and fast

## Requirements

- macOS 14+ (Sonoma)
- Xcode 15+ or Swift 5.9+
- Accessibility permission (for Fn key monitoring and text injection)

## Installation

```bash
git clone https://github.com/panjuntao/voicer.git
cd voicer
swift build -c release
```

## Usage

1. **Build and run** — `swift run` or open in Xcode and Cmd+R
2. **Grant permissions** — Accessibility permission will be requested on first launch
3. **Configure API** — Click the mic icon in menu bar → LLM Refinement → Settings
4. **Hold Fn** — Start speaking
5. **Release Fn** — Text is transcribed, optionally refined by LLM, and injected into the current input field

### Speech Recognition

- **Without API** — Uses Apple's built-in Speech framework with automatic language detection
- **With API** — Check "Use API for Speech Recognition" in Settings, audio is sent to Whisper API for higher accuracy, especially for mixed-language input

### Supported LLM Providers

OpenAI, DeepSeek, Moonshot (Kimi), 智谱 AI, ByteDance (豆包), Alibaba (通义千问), Baichuan (百川), MiniMax, 零一万物, 阶跃星辰, Groq, xAI, Mistral AI, Cohere, Perplexity, Fireworks AI, SiliconFlow, or any OpenAI-compatible endpoint via Custom.

## Architecture

```
User presses Fn
    ↓
AudioEngine records + saves temp file
SpeechEngine (Apple Speech) provides real-time preview
    ↓
User releases Fn
    ↓
If API Speech enabled → Whisper API transcription (fallback to local)
If LLM enabled → LLM refinement
    ↓
TextInjector pastes into active input field
FloatingPanel animates shut
```

## License

MIT License. See [LICENSE](LICENSE) for details.