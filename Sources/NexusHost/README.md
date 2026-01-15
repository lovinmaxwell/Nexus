# NexusHost

Native Messaging Host binary for browser extension communication.

## Purpose

This executable handles communication between browser extensions and the main Nexus app using the Native Messaging Protocol.

## Protocol

1. Browser sends JSON message with 32-bit length header
2. NexusHost reads and parses the message
3. Writes download request to shared location
4. Notifies main app via DistributedNotificationCenter
5. Returns confirmation to browser

## Message Format

### Request (from browser)
```json
{
  "url": "https://example.com/file.zip",
  "cookies": "session=abc123",
  "referrer": "https://example.com/",
  "userAgent": "Mozilla/5.0...",
  "filename": "file.zip"
}
```

### Response (to browser)
```json
{
  "success": true,
  "message": "Download added",
  "taskId": "uuid-string"
}
```

## Installation

The host manifest must be installed at:
- Chrome: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
- Firefox: `~/Library/Application Support/Mozilla/NativeMessagingHosts/`
