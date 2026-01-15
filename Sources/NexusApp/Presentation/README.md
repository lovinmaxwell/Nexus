# Presentation

UI layer containing SwiftUI views and components.

## Structure

| Folder | Purpose |
|--------|---------|
| `Views/` | Main application views |
| `Components/` | Reusable UI components |

## Views

Main application screens:
- `ContentView` - Main window with sidebar and download list
- `AddDownloadSheet` - Sheet for adding new downloads
- `SettingsView` - Application preferences

## Components

Reusable UI elements:
- `SegmentProgressView` - Visualizes segment download progress
- `DownloadRowView` - Individual download list item
- `SpeedLimitControl` - Speed limiting UI control

## Design Principles

- Views are declarative and stateless where possible
- Complex state managed via `@Observable` view models
- Reusable components in `Components/`
