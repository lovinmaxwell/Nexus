#!/bin/bash

# Nexus Browser Extension Installer
# Installs Native Messaging Host manifests for Chrome and Firefox

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXUS_HOST_PATH="/Applications/Nexus.app/Contents/MacOS/NexusHost"

echo "Installing Nexus Browser Extensions..."

# Chrome Native Messaging Host
CHROME_NM_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
if [ -d "$HOME/Library/Application Support/Google/Chrome" ]; then
    mkdir -p "$CHROME_NM_DIR"
    cat > "$CHROME_NM_DIR/com.nexus.host.json" << EOF
{
  "name": "com.nexus.host",
  "description": "Nexus Download Manager Native Messaging Host",
  "path": "$NEXUS_HOST_PATH",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://*/""
  ]
}
EOF
    echo "✓ Chrome Native Messaging Host installed"
fi

# Chromium Native Messaging Host
CHROMIUM_NM_DIR="$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
if [ -d "$HOME/Library/Application Support/Chromium" ]; then
    mkdir -p "$CHROMIUM_NM_DIR"
    cp "$CHROME_NM_DIR/com.nexus.host.json" "$CHROMIUM_NM_DIR/"
    echo "✓ Chromium Native Messaging Host installed"
fi

# Firefox Native Messaging Host
FIREFOX_NM_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
mkdir -p "$FIREFOX_NM_DIR"
cat > "$FIREFOX_NM_DIR/com.nexus.host.json" << EOF
{
  "name": "com.nexus.host",
  "description": "Nexus Download Manager Native Messaging Host",
  "path": "$NEXUS_HOST_PATH",
  "type": "stdio",
  "allowed_extensions": [
    "nexus@example.com"
  ]
}
EOF
echo "✓ Firefox Native Messaging Host installed"

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Load the Chrome extension from: $SCRIPT_DIR/Chrome"
echo "   - Go to chrome://extensions"
echo "   - Enable Developer mode"
echo "   - Click 'Load unpacked' and select the Chrome folder"
echo ""
echo "2. Load the Firefox extension from: $SCRIPT_DIR/Firefox"
echo "   - Go to about:debugging"
echo "   - Click 'This Firefox'"
echo "   - Click 'Load Temporary Add-on' and select manifest.json"
echo ""
