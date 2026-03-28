# zhiyin 知音

> Offline Chinese voice input for macOS. Press a key, speak, text appears. No internet required.

## Features

- **100% offline** — no data leaves your Mac
- **SenseVoice model** — best Chinese accuracy per compute dollar (Alibaba open-source)
- **~0.9s latency** — from stop recording to text appearing
- **Works everywhere** — any text field: editors, browsers, chat, terminal, Claude Code
- **Single key trigger** — Right Command by default, configurable
- **Apple Silicon & Intel** — supports both M-series and Intel Macs

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/leave1206/zhiyin/main/install.sh | bash
```

Or clone and install:

```bash
git clone https://github.com/leave1206/zhiyin.git
cd zhiyin && bash install.sh
```

The installer automatically handles all dependencies (Homebrew, sox, Python, SenseVoice model).

## Requirements

- macOS 12+ (Monterey or later)
- Apple Silicon (M1/M2/M3/M4) or Intel Mac
- ~500MB disk space
- Xcode Command Line Tools (for compiling the native menubar app)

## Usage

| Action | Result |
|--------|--------|
| Press **Right Command** | Start recording (menubar icon turns red) |
| Press **Right Command** again | Stop recording, transcribe, paste at cursor |

### First-time setup

macOS will ask for two permissions (one-time only):
1. **Accessibility** — allows simulating Cmd+V paste. Go to System Settings > Privacy & Security > Accessibility > enable "Zhiyin"
2. **Microphone** — auto-prompted on first recording, click "Allow"

### Terminal commands

```bash
zhiyin status     # Check if running
zhiyin start      # Start the menubar app
zhiyin stop       # Stop the menubar app
zhiyin config     # Edit configuration
zhiyin log        # View recent transcriptions
zhiyin uninstall  # Remove everything
```

## Configuration

Edit `~/.zhiyin/zhiyin.conf`:

```ini
HOTKEY=right_cmd       # right_cmd, fn, f5, f6
LANGUAGE=zh            # zh, en, ja, ko, yue
PASTE_METHOD=cmdv      # cmdv (auto-paste) or clipboard (copy only)
MAX_DURATION=60        # Max recording seconds (safety timeout)
NUM_THREADS=4          # CPU threads for inference
```

## How It Works

```
Right Cmd → Zhiyin menubar app → sox records audio → WAV file
Right Cmd → stop recording → sox converts to 16kHz
          → SenseVoice transcribes (~0.9s) → NSPasteboard
          → CGEvent simulates Cmd+V → text appears at cursor
```

All processing happens locally. The SenseVoice model (228MB, int8 quantized) runs via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx).

## Supported Languages

| Language | Code | Accuracy |
|----------|------|----------|
| Chinese (Mandarin) | `zh` | Excellent |
| English | `en` | Good |
| Japanese | `ja` | Good |
| Korean | `ko` | Good |
| Cantonese | `yue` | Good |

## Architecture

```
~/.zhiyin/
├── Zhiyin.app/          # Native Swift menubar app (hotkey + paste)
├── transcribe.py        # SenseVoice transcription script
├── venv/                # Isolated Python environment
├── models/sensevoice/   # SenseVoice int8 model (228MB)
├── zhiyin.conf          # Configuration
├── voice.log            # Transcription log
└── bin/zhiyin           # CLI entrypoint
```

## Troubleshooting

**Right Command not working?**
- Check `zhiyin status` — if not running, run `zhiyin start`
- Verify Accessibility permission is granted for "Zhiyin"

**Recording but no transcription?**
- Check `zhiyin log` for errors
- Verify Microphone permission is granted

**Text not pasting?**
- Accessibility permission is required for CGEvent paste
- System Settings > Privacy & Security > Accessibility > enable "Zhiyin"

## Uninstall

```bash
zhiyin uninstall
```

## Acknowledgments

- [SenseVoice](https://github.com/FunAudioLLM/SenseVoice) by Alibaba Tongyi Lab — speech recognition model
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) by k2-fsa — inference engine

## License

MIT
