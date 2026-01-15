# Network

Network layer handling different protocols for downloads.

## Files

| File | Purpose |
|------|---------|
| `NetworkHandler.swift` | Protocol defining network operations |
| `URLSessionHandler.swift` | HTTP/HTTPS implementation using URLSession |
| `FTPHandler.swift` | FTP/FTPS implementation using curl |
| `NetworkHandlerFactory.swift` | Factory to select appropriate handler |

## Protocol Support

| Protocol | Handler | Features |
|----------|---------|----------|
| HTTP/HTTPS | URLSessionHandler | Range requests, cookies, headers |
| FTP/FTPS | FTPHandler | SIZE, MDTM, REST commands via curl |

## Usage

```swift
let handler = NetworkHandlerFactory.handler(for: url)
let (size, acceptsRanges, _, _) = try await handler.headRequest(url: url)
let stream = try await handler.downloadRange(url: url, start: 0, end: size)
```
