# Sources

This directory contains all source code for the Nexus Download Manager.

## Structure

```
Sources/
├── NexusApp/          # Main application
│   ├── App/           # Application entry point and configuration
│   ├── Core/          # Application layer (business logic)
│   ├── Domain/        # Domain layer (entities, protocols)
│   ├── Presentation/  # UI layer (views, components)
│   └── Utilities/     # Helper classes and extensions
└── NexusHost/         # Native Messaging Host for browser integration
```

## Architecture

Nexus follows **Clean Architecture** principles:

1. **Domain Layer** - Business entities and protocols (innermost)
2. **Application Layer** - Use cases and business logic
3. **Presentation Layer** - UI components (outermost)

Dependencies flow inward: Presentation → Application → Domain
