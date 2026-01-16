# App Sandbox Setup Guide

This document outlines the steps required to fully implement App Sandbox compliance for Project Nexus.

## Current Status

✅ **Completed:**
- Security-Scoped Bookmarks for download directory
- NSOpenPanel for directory selection
- Persistent read/write access across launches
- Process API (NSTask) execution for yt-dlp

## Remaining Steps (Requires Xcode Project Configuration)

### 1. Enable App Sandbox Entitlement

In Xcode:
1. Select the project target
2. Go to "Signing & Capabilities"
3. Click "+ Capability"
4. Add "App Sandbox"

### 2. Configure Sandbox Permissions

Required entitlements in `entitlements` file:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>

<key>com.apple.security.network.client</key>
<true/>

<key>com.apple.security.files.user-selected.read-write</key>
<true/>

<key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
<array>
    <string>/Users/$(USER)/Downloads/</string>
</array>
```

### 3. Hardened Runtime

1. In "Signing & Capabilities", enable "Hardened Runtime"
2. Configure exceptions if needed:
   - Allow unsigned executable (for yt-dlp)
   - Allow JIT (if needed for Python runtime)

### 4. Code Signing

1. Select a valid Developer ID certificate
2. Enable "Automatically manage signing" or configure manually
3. Ensure all binaries (including yt-dlp) are signed

### 5. Notarization

After building:
1. Archive the app
2. Export for distribution
3. Submit to Apple for notarization:
   ```bash
   xcrun notarytool submit --apple-id <email> --team-id <team-id> --password <app-specific-password> <path-to-app>
   ```

## Notes

- The code implementation is complete; these are Xcode project configuration steps
- Security-Scoped Bookmarks are already implemented in code
- Process execution for yt-dlp is already implemented
- Remaining items require Xcode GUI configuration and Apple Developer account
