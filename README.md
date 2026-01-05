# Sajadah

SwiftUI app that uses CoreLocation to fetch the user’s current location and (optionally) reverse-geocode it into a human-readable place (city/region/country). Intended for features like prayer times and Qibla direction.

## Features
- Location permission flow (request / denied / error states)
- One-shot location fetch using `CLLocationManager.requestLocation()`
- Optional reverse geocoding via `CLGeocoder.reverseGeocodeLocation`
- Simple state-driven UI in SwiftUI (`loading`, `home`, `needPermission`, `denied`, `error`)

## Requirements
- Xcode (latest stable recommended)
- iOS and/or macOS target(s)
- Location usage description in `Info.plist`

## Setup
1. Clone the repo:
   ```bash
   git clone <your-repo-url>
   cd Sajadah
   ```
   
2.	Open in Xcode:
	•	Open Sajadah.xcodeproj (or Sajadah.xcworkspace if you use one).

3.	Add Info.plist keys (per target):
	•	NSLocationWhenInUseUsageDescription
Example: We use your location to show accurate prayer times and qibla direction.
Optional (only if you truly need background location):
	•	NSLocationAlwaysAndWhenInUseUsageDescription

macOS Notes (Sandbox)

If you’re building a macOS app target:
1. Target → Signing & Capabilities
2. Enable App Sandbox
3. Enable Location (Location Services)

If you test in SwiftUI Preview, location can fail due to sandbox restrictions. Run the app normally (⌘R) for reliable location behavior.

How it works
- AppView owns a @StateObject LocationManager
- LocationManager publishes a state enum
- UI switches on state to render:
- LoadingView
- LocationPermissionView
- LocationDeniedView
- LocationErrorView
- HomeView (coordinates + optional place)

Project Structure (suggested)
```text
.
├── README.md
├── Sajadah
│   ├── Assets.xcassets
│   │   ├── AccentColor.colorset
│   │   │   └── Contents.json
│   │   ├── AppIcon.appiconset
│   │   │   └── Contents.json
│   │   └── Contents.json
│   ├── Controller
│   │   └── LocationManager.swift
│   ├── Model
│   ├── ModelView
│   ├── SajadahApp.swift
│   └── View
│       ├── AppView.swift
│       ├── HomeView.swift
│       ├── LoadingView.swift
│       ├── LocationDeniedView.swift
│       ├── LocationErrorView.swift
│       └── LocationPermissionView.swift
└── Sajadah.xcodeproj

```
Roadmap (optional)
- Persist last known location
- Prayer time calculation API / local calc
- Qibla direction (bearing + compass)
- Offline geocoding fallback / caching

