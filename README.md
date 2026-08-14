# Sajadah

A macOS menubar app that counts down to the next prayer, using the [Aladhan API](https://aladhan.com/prayer-times-api) for timings and CoreLocation for your position.

The menubar item shows the next prayer and the time remaining — `🌙 Asr 1h 23m`. Clicking it opens a popover with today's full timings; there's also a window with the week ahead, and local notifications at each prayer.

## Features

- Menubar countdown to the next prayer, updated every second (redrawn only when the text changes)
- Popover with today's six timings, the current place, and the Hijri date
- Full window with today plus the next 7 days
- Local notifications at prayer time, with per-prayer toggles and an optional "N minutes before" offset
- Two-stage check-ins that ask whether you prayed, with Yes/No buttons right on the notification
- Prayer log with daily streaks, a best-streak record, and a 30-day history grid
- 17 calculation methods and both Asr conventions, changeable in Settings
- Works offline: timings are cached a month at a time on disk and keep displaying with an "Offline" badge if a refresh fails
- Refreshes on wake, on day rollover, on clock changes, and when you move more than 5 km
- Optional launch at login

## Requirements

- Xcode 26 or later
- macOS 26.2 or later (the deployment target)

## Setup

```bash
git clone <your-repo-url>
cd sajadah-macos
open Sajadah.xcodeproj
```

Then just build and run (⌘R). On first launch the app asks for location and notification permission.

If `xcodebuild` is used from the command line and fails with a Command Line Tools error, either point `xcode-select` at Xcode or call it by absolute path:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Sajadah.xcodeproj -scheme Sajadah -configuration Debug build
```

### Required build settings

This project has no `.entitlements` file — Xcode 26 drives the sandbox and Info.plist from build settings. Three matter, all already set on the target:

| Setting | Value | Why |
|---|---|---|
| `ENABLE_APP_SANDBOX` | `YES` | |
| `ENABLE_RESOURCE_ACCESS_LOCATION` | `YES` | CoreLocation access |
| `ENABLE_OUTGOING_NETWORK_CONNECTIONS` | `YES` | Without it the sandbox silently blocks every Aladhan request |
| `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` | *(a sentence)* | Without it the location prompt never appears |

Location does not work reliably in SwiftUI Previews under the sandbox — run the app normally (⌘R).

## How it works

`AppCoordinator` owns the long-lived objects and wires them together, so the connections hold whether or not any view is on screen:

- **`LocationManager`** publishes a `State` enum (`loading` / `home` / `needPermission` / `denied` / `error`) and hands fresh coordinates to the store through a callback.
- **`AladhanAPI`** fetches one calendar month per request from `/v1/calendar/{year}/{month}` with `iso8601=true`, so every timing arrives as a fully-offset instant and DST needs no special handling.
- **`PrayerTimesStore`** caches months to `Application Support/Sajadah/prayer-cache.json`, always keeps at least 8 days of timings ahead of today, and answers "what's next?" by searching a flat sorted list of events — which is what makes the countdown cross midnight correctly.
- **`Ticker`** advances the clock once a second via an async loop rather than a run-loop timer, so it keeps ticking while the popover is open.
- **`NotificationScheduler`** rewrites the whole pending batch whenever timings, preferences or the prayer log change. Rather than rationing each kind of notification separately, it builds every candidate, sorts by fire date and keeps the nearest 60 — so the 64-request budget always goes to whatever happens soonest.
- **`PrayerLogStore`** records what was prayed in its own file, deliberately separate from the timings cache: it is the user's own data and must survive a location change, a method change or a cache wipe.

### Check-ins

Each prayer is asked about as its own window closes. A prayer's window runs until the next one begins; Isha has no following prayer, so it runs to a cutoff time you set (default 11pm).

| Prayer | Window closes at |
|---|---|
| Fajr | Sunrise |
| Dhuhr | Asr |
| Asr | Maghrib |
| Maghrib | Isha |
| Isha | Your evening cutoff |

The ask escalates in two stages. Ten minutes before the window closes you get a soft "Did you pray Asr?" — answering **Yes** logs it, **Not yet** records nothing. If it is still unlogged when the window actually closes, the question comes back as a final ask, and **No** there marks it missed. Answering at either stage retires the other, because the batch is rebuilt from scratch and skips anything already answered.

Anything you miss can still be logged by clicking the circle beside a prayer in the popover.

## Roadmap

- Qibla direction (bearing + compass)
- Manual city override for when location is unavailable
- Adhan audio at prayer time
