#!/bin/bash
# zhiyin uninstaller

echo "Uninstalling zhiyin..."

# Stop app
pkill -x zhiyin 2>/dev/null

# Kill any recording
if [ -f "$HOME/.zhiyin/rec.pid" ]; then
    kill "$(cat "$HOME/.zhiyin/rec.pid")" 2>/dev/null
fi

# Remove LaunchAgent
launchctl unload "$HOME/Library/LaunchAgents/com.zhiyin.app.plist" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.zhiyin.app.plist"

# Remove skhd config
if [ -f "$HOME/.skhdrc" ]; then
    sed -i '' '/# zhiyin/d;/zhiyin/d' "$HOME/.skhdrc"
    pkill -USR1 skhd 2>/dev/null
fi

# Remove shell integration
sed -i '' '/zhiyin/d' "$HOME/.zshrc" 2>/dev/null

# Remove all files
rm -rf "$HOME/.zhiyin"

echo "✓ zhiyin has been uninstalled."
echo ""
echo "Optional cleanup:"
echo "  brew uninstall sox    # if you don't need sox"
echo "  Remove 'Zhiyin' from System Settings → Privacy → Accessibility"
