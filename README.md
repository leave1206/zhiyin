# zhiyin 知音

> Offline Chinese voice input for macOS. Press Fn, speak, text appears. No internet required.

## Features

- **100% offline** — no data leaves your Mac
- **SenseVoice model** — best Chinese accuracy per compute dollar (Alibaba open-source)
- **~0.9s latency** — from stop recording to text appearing
- **Works everywhere** — any text field: editors, browsers, chat, terminal, Claude Code
- **Fn key** — single key, no modifier combos, no system settings changes
- **Apple Silicon native** — optimized for M1/M2/M3/M4

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/leave1206/zhiyin/main/install.sh | bash
```

## Requirements

- macOS 12+ (Monterey or later)
- Apple Silicon (M1/M2/M3/M4)
- ~500MB disk space

## Usage

| Action | Result |
|--------|--------|
| Press **Fn** | Start recording |
| Press **Fn** again | Stop recording, transcribe, paste at cursor |

## Configuration

Edit `~/.zhiyin/zhiyin.conf`:

```ini
HOTKEY=fn              # fn, f5, f6
LANGUAGE=zh            # zh, en, ja, ko, yue
PASTE_METHOD=cmdv      # cmdv (auto-paste) or clipboard (copy only)
MAX_DURATION=60        # Max recording seconds
NUM_THREADS=4          # CPU threads for inference
```

## How It Works

```
Fn key → Zhiyin menubar app → sox records audio
Fn key → stops recording → SenseVoice transcribes (0.9s) → paste at cursor
```

## Supported Languages

Chinese (zh), English (en), Japanese (ja), Korean (ko), Cantonese (yue)

## Uninstall

```bash
zhiyin uninstall
```

## Acknowledgments

- [SenseVoice](https://github.com/FunAudioLLM/SenseVoice) by Alibaba Tongyi Lab
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) by k2-fsa

## License

MIT
