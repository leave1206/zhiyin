#!/bin/bash
# zhiyin 知音 — Offline Chinese Voice Input for macOS
# One-command installer
# Usage: curl -fsSL https://raw.githubusercontent.com/leave1206/zhiyin/main/install.sh | bash

set -euo pipefail

VERSION="0.1.0"
ZHIYIN_DIR="$HOME/.zhiyin"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2"
MODEL_DIR="$ZHIYIN_DIR/models/sensevoice"
REPO_URL="https://raw.githubusercontent.com/leave1206/zhiyin/main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[zhiyin]${NC} $1"; }
ok()    { echo -e "${GREEN}  ✓${NC} $1"; }
warn()  { echo -e "${YELLOW}  ⚠${NC} $1"; }
fail()  { echo -e "${RED}  ✗${NC} $1"; exit 1; }

# ─────────────────────────────────────
# Phase 0: Preflight
# ─────────────────────────────────────
echo ""
echo -e "${BOLD}zhiyin 知音${NC} v${VERSION} — Offline Chinese Voice Input"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS only. Detected: $(uname -s)"
[[ "$(uname -m)" == "arm64" ]] || fail "Apple Silicon only. Detected: $(uname -m)"
[[ "$(id -u)" != "0" ]] || fail "Do not run as root."

info "Preflight checks passed"

# ─────────────────────────────────────
# Phase 1: Dependencies
# ─────────────────────────────────────
info "Checking dependencies..."

# Homebrew
if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
ok "Homebrew"

# sox
if ! command -v rec &>/dev/null; then
    info "Installing sox..."
    brew install sox > /dev/null 2>&1
fi
ok "sox (audio recording)"

# Python — find or install arm64 python3
PYTHON=""
for p in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [ -x "$p" ]; then
        PYTHON="$p"
        break
    fi
done
if [ -z "$PYTHON" ]; then
    info "Installing Python..."
    brew install python@3.12 > /dev/null 2>&1
    PYTHON="/opt/homebrew/bin/python3"
fi
ok "Python ($PYTHON)"

# ─────────────────────────────────────
# Phase 2: Create venv (solves ALL arch issues)
# ─────────────────────────────────────
info "Setting up Python environment..."
mkdir -p "$ZHIYIN_DIR"

if [ ! -f "$ZHIYIN_DIR/venv/bin/python3" ]; then
    arch -arm64 "$PYTHON" -m venv "$ZHIYIN_DIR/venv"
fi
ok "Python venv (arm64)"

VENV_PIP="$ZHIYIN_DIR/venv/bin/pip"
VENV_PYTHON="$ZHIYIN_DIR/venv/bin/python3"

# Install Python packages
"$VENV_PIP" install -q sherpa-onnx numpy 2>/dev/null
ok "sherpa-onnx + numpy"

# ─────────────────────────────────────
# Phase 3: Download model
# ─────────────────────────────────────
if [ ! -f "$MODEL_DIR/model.int8.onnx" ]; then
    info "Downloading SenseVoice model (228MB)..."
    mkdir -p "$MODEL_DIR"
    TMPFILE=$(mktemp /tmp/zhiyin-model.XXXXXX.tar.bz2)
    curl -L --progress-bar -o "$TMPFILE" "$MODEL_URL"
    tar xjf "$TMPFILE" -C "$ZHIYIN_DIR/models/"
    # Rename extracted dir
    EXTRACTED=$(ls -d "$ZHIYIN_DIR/models/sherpa-onnx-sense-voice"* 2>/dev/null | head -1)
    if [ -n "$EXTRACTED" ] && [ "$EXTRACTED" != "$MODEL_DIR" ]; then
        rm -rf "$MODEL_DIR"
        mv "$EXTRACTED" "$MODEL_DIR"
    fi
    rm -f "$TMPFILE"
    ok "SenseVoice model downloaded"
else
    ok "SenseVoice model (already exists)"
fi

# ─────────────────────────────────────
# Phase 4: Install application files
# ─────────────────────────────────────
info "Installing application..."

# Download source files from repo (or copy if running from cloned repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "$SCRIPT_DIR/src/transcribe.py" ]; then
    # Running from cloned repo
    cp "$SCRIPT_DIR/src/transcribe.py" "$ZHIYIN_DIR/transcribe.py"
    SWIFT_SRC="$SCRIPT_DIR/src/ZhiyinApp.swift"
    PLIST_SRC="$SCRIPT_DIR/src/Info.plist"
else
    # Running via curl | bash — download files
    curl -fsSL "$REPO_URL/src/transcribe.py" -o "$ZHIYIN_DIR/transcribe.py"
    curl -fsSL "$REPO_URL/src/ZhiyinApp.swift" -o "$ZHIYIN_DIR/ZhiyinApp.swift"
    curl -fsSL "$REPO_URL/src/Info.plist" -o "$ZHIYIN_DIR/Info.plist"
    SWIFT_SRC="$ZHIYIN_DIR/ZhiyinApp.swift"
    PLIST_SRC="$ZHIYIN_DIR/Info.plist"
fi

# Fix shebang to use venv python
sed -i '' "1s|.*|#!$VENV_PYTHON|" "$ZHIYIN_DIR/transcribe.py"
chmod +x "$ZHIYIN_DIR/transcribe.py"

# Build .app bundle
APP_DIR="$ZHIYIN_DIR/Zhiyin.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Compile Swift menubar app
info "Compiling Zhiyin.app..."
swiftc -O -o "$APP_DIR/Contents/MacOS/zhiyin" \
    -framework Cocoa -framework Carbon \
    "$SWIFT_SRC" 2>/dev/null || {
    warn "Swift compilation failed. Falling back to shell-based hotkey."
    # Fallback: write a simple toggle script instead
    cat > "$APP_DIR/Contents/MacOS/zhiyin" << 'FALLBACK'
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export HOME="__HOME__"
cd /tmp
VOICE_DIR="$HOME/.zhiyin"
PID_FILE="$VOICE_DIR/rec.pid"
WAV_FILE="$VOICE_DIR/recording.wav"
LOG="$VOICE_DIR/voice.log"
MAX_SEC=60
# Clean stale
if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$PID_FILE"
    else
        started=$(stat -f %m "$PID_FILE" 2>/dev/null || echo 0)
        now=$(date +%s)
        [ $((now - started)) -ge $MAX_SEC ] && { kill "$pid" 2>/dev/null; sleep 0.3; rm -f "$PID_FILE" "$WAV_FILE"; }
    fi
fi
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    sleep 0.3
    rm -f "$PID_FILE"
    "$VOICE_DIR/venv/bin/python3" "$VOICE_DIR/transcribe.py" >> "$LOG" 2>&1
else
    rm -f "$WAV_FILE" "$PID_FILE"
    nohup rec -q "$WAV_FILE" >> "$LOG" 2>&1 &
    echo $! > "$PID_FILE"
    disown
fi
FALLBACK
    sed -i '' "s|__HOME__|$HOME|g" "$APP_DIR/Contents/MacOS/zhiyin"
    chmod +x "$APP_DIR/Contents/MacOS/zhiyin"
}

# Install Info.plist
sed "s|__VERSION__|$VERSION|g" "$PLIST_SRC" > "$APP_DIR/Contents/Info.plist"

ok "Zhiyin.app built"

# ─────────────────────────────────────
# Phase 5: Default config
# ─────────────────────────────────────
if [ ! -f "$ZHIYIN_DIR/zhiyin.conf" ]; then
    cat > "$ZHIYIN_DIR/zhiyin.conf" << 'CONF'
# zhiyin configuration
HOTKEY=right_cmd
LANGUAGE=zh
PASTE_METHOD=cmdv
MAX_DURATION=60
NUM_THREADS=4
CONF
fi
ok "Configuration"

# ─────────────────────────────────────
# Phase 6: skhd hotkey (fallback if Swift app not compiled)
# ─────────────────────────────────────
if [ -f "$APP_DIR/Contents/MacOS/zhiyin" ] && file "$APP_DIR/Contents/MacOS/zhiyin" | grep -q "Mach-O"; then
    # Native app compiled — register as login item
    info "Registering Zhiyin as login item..."
    PLIST_FILE="$HOME/Library/LaunchAgents/com.zhiyin.app.plist"
    cat > "$PLIST_FILE" << LAUNCHD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.zhiyin.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_DIR/Contents/MacOS/zhiyin</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
LAUNCHD
    launchctl load -w "$PLIST_FILE" 2>/dev/null || true
    ok "Login item registered (auto-start on boot)"

    # Start the app now
    nohup "$APP_DIR/Contents/MacOS/zhiyin" > /dev/null 2>&1 &
    ok "Zhiyin.app started"
else
    # Fallback: use skhd
    if ! command -v skhd &>/dev/null; then
        brew install koekeishiya/formulae/skhd > /dev/null 2>&1
    fi

    # Add to skhdrc
    SKHD_LINE="f5 : open -a $APP_DIR"
    if [ -f "$HOME/.skhdrc" ]; then
        grep -q "zhiyin" "$HOME/.skhdrc" 2>/dev/null || echo -e "\n# zhiyin\n$SKHD_LINE" >> "$HOME/.skhdrc"
    else
        echo "# zhiyin" > "$HOME/.skhdrc"
        echo "$SKHD_LINE" >> "$HOME/.skhdrc"
    fi
    skhd --start-service 2>/dev/null || true
    pkill -USR1 skhd 2>/dev/null || true
    warn "Using skhd fallback (F5 hotkey). Native Fn key requires Xcode CLT."
fi

# ─────────────────────────────────────
# Phase 7: Shell integration
# ─────────────────────────────────────
mkdir -p "$ZHIYIN_DIR/bin"
cat > "$ZHIYIN_DIR/bin/zhiyin" << 'CLI'
#!/bin/bash
ZHIYIN_DIR="$HOME/.zhiyin"
case "${1:-help}" in
  toggle)     nohup "$ZHIYIN_DIR/Zhiyin.app/Contents/MacOS/zhiyin" > /dev/null 2>&1 & ;;
  doctor)     bash "$ZHIYIN_DIR/scripts/health-check.sh" 2>/dev/null || echo "Doctor script not found" ;;
  config)     ${EDITOR:-nano} "$ZHIYIN_DIR/zhiyin.conf" ;;
  log)        tail -20 "$ZHIYIN_DIR/voice.log" ;;
  uninstall)  bash "$ZHIYIN_DIR/uninstall.sh" ;;
  status)     pgrep -x zhiyin >/dev/null && echo "🎤 Running" || echo "💤 Not running" ;;
  start)      nohup "$ZHIYIN_DIR/Zhiyin.app/Contents/MacOS/zhiyin" > /dev/null 2>&1 &; echo "Started" ;;
  stop)       pkill -x zhiyin 2>/dev/null; echo "Stopped" ;;
  *)
    echo "zhiyin 知音 — Offline Chinese Voice Input"
    echo ""
    echo "Usage:"
    echo "  Press Fn key    Start/stop recording (auto-transcribe)"
    echo ""
    echo "Commands:"
    echo "  zhiyin status     Check if running"
    echo "  zhiyin start      Start the menubar app"
    echo "  zhiyin stop       Stop the menubar app"
    echo "  zhiyin config     Edit configuration"
    echo "  zhiyin log        View recent transcriptions"
    echo "  zhiyin doctor     Run diagnostics"
    echo "  zhiyin uninstall  Remove everything"
    ;;
esac
CLI
chmod +x "$ZHIYIN_DIR/bin/zhiyin"

# Add to PATH in .zshrc
if ! grep -q "zhiyin/bin" "$HOME/.zshrc" 2>/dev/null; then
    echo '' >> "$HOME/.zshrc"
    echo '# zhiyin — offline voice input' >> "$HOME/.zshrc"
    echo 'export PATH="$HOME/.zhiyin/bin:$PATH"' >> "$HOME/.zshrc"
fi
ok "Shell integration (zhiyin command)"

# ─────────────────────────────────────
# Phase 8: Verification
# ─────────────────────────────────────
info "Verifying installation..."

"$VENV_PYTHON" -c "import sherpa_onnx; print('  ✓ sherpa_onnx OK')" 2>/dev/null || warn "sherpa_onnx import failed"
[ -f "$MODEL_DIR/model.int8.onnx" ] && ok "Model file exists" || warn "Model file missing"
command -v rec &>/dev/null && ok "sox available" || warn "sox not found"

# ─────────────────────────────────────
# Done!
# ─────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ✓ zhiyin installed successfully!${NC}"
echo ""
echo "  Usage:"
echo "    Press Right Cmd  →  Start recording"
echo "    Press Right Cmd  →  Stop & paste transcription"
echo ""
echo "  First time: macOS will ask for permissions."
echo "    1. Accessibility → Allow 'Zhiyin'"
echo "    2. Microphone → Allow 'Zhiyin'"
echo "    Just click 'Allow' when prompted."
echo ""
echo "  Commands: zhiyin help"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Save version
echo "$VERSION" > "$ZHIYIN_DIR/version"
