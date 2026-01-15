# Browser Extensions

Browser extensions for intercepting downloads and sending them to Nexus.

## Supported Browsers

| Browser | Status | Location |
|---------|--------|----------|
| Chrome | Ready | `Chrome/` |
| Firefox | Ready | `Firefox/` |
| Safari | Planned | `Safari/` |

## Installation

Run the installation script:
```bash
./install.sh
```

This installs Native Messaging Host manifests to:
- Chrome: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
- Firefox: `~/Library/Application Support/Mozilla/NativeMessagingHosts/`

## Loading Extensions

### Chrome
1. Go to `chrome://extensions`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select the `Chrome/` folder

### Firefox
1. Go to `about:debugging`
2. Click "This Firefox"
3. Click "Load Temporary Add-on"
4. Select `Firefox/manifest.json`

## Features

- **Context Menu**: Right-click any link → "Download with Nexus"
- **Auto-intercept**: Large files (>10MB) automatically sent to Nexus
- **Popup UI**: Manual URL entry and connection status
- **Cookies**: Passes browser cookies for authenticated downloads
