# Database Recovery Guide

## Issue: ModelContainer Initialization Failure

If you encounter the error:
```
fatalError("Could not create ModelContainer: \(error)")
```

This typically indicates:
1. **Schema Migration Issue**: The database schema has changed and needs migration
2. **Corrupted Database**: The SwiftData store file is corrupted
3. **Permission Issue**: The app doesn't have write access to the database location

## Automatic Recovery

The app now includes automatic recovery:
1. **First Attempt**: Try to create ModelContainer with the configured store
2. **Recovery**: If that fails, delete the corrupted store and try again
3. **Fallback**: If recovery fails, use an in-memory store (data will be lost on app quit)

## Manual Recovery

If automatic recovery doesn't work, you can manually reset the database:

### Option 1: Delete Database Files

1. Close the app completely
2. Navigate to: `~/Library/Application Support/Nexus/`
3. Delete the following files:
   - `default.store`
   - `default.store-wal` (if exists)
   - `default.store-shm` (if exists)
4. Restart the app

### Option 2: Reset via Terminal

```bash
# Close the app first, then run:
rm -rf ~/Library/Application\ Support/Nexus/default.store*
```

### Option 3: Use In-Memory Store (Development)

For development/testing, you can temporarily use an in-memory store by modifying `NexusApp.swift`:

```swift
let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
```

**Note**: This will lose all data when the app quits.

## Database Location

The SwiftData store is located at:
```
~/Library/Application Support/Nexus/default.store
```

## Prevention

To prevent database corruption:
- Always quit the app gracefully (don't force quit)
- Ensure sufficient disk space
- Don't manually modify database files
- Keep the app updated to handle schema migrations

## Schema Version

Current schema includes:
- `DownloadTask` (with relationships to FileSegment and DownloadQueue)
- `FileSegment` (with relationship to DownloadTask)
- `DownloadQueue` (with relationship to DownloadTask)

If you add new properties to these models, SwiftData should handle migration automatically, but if migration fails, use the recovery steps above.
