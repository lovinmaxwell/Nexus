# Safari Web Extension

Safari extension for intercepting downloads and sending them to Nexus.

## Structure

```
Safari/
├── Resources/          # Web extension resources
│   ├── manifest.json   # Extension manifest
│   ├── background.js   # Service worker
│   ├── popup.html      # Popup UI
│   ├── popup.js        # Popup logic
│   └── images/         # Extension icons
```

## Building the Extension

Safari Web Extensions must be built using Xcode:

1. Open Xcode and create a new Safari Web Extension project
2. Copy the `Resources/` folder contents into the extension's Resources
3. The `SafariWebExtensionHandler.swift` in the main app handles native messaging
4. Build and run from Xcode

### Using safari-web-extension-converter

Alternatively, use Apple's converter tool:

```bash
xcrun safari-web-extension-converter BrowserExtensions/Safari/Resources \
    --project-location ./SafariExtension \
    --app-name "Nexus for Safari"
```

## Native Messaging

Safari Web Extensions communicate with the containing app via `NSExtensionRequestHandling`:
- Extension sends messages via `browser.runtime.sendNativeMessage()`
- `SafariWebExtensionHandler` receives and processes messages
- Responses are sent back to JavaScript

## Enabling the Extension

1. Build the app in Xcode
2. Open Safari > Settings > Extensions
3. Enable "Nexus Download Manager"
4. Grant necessary permissions
