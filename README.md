# Sajadah

A macOS menubar app for prayer times and Quran reading, using the [Aladhan API](https://aladhan.com/prayer-times-api) for timings, [alquran.cloud](https://alquran.cloud/api) for the Quran, and CoreLocation for your position.

The menubar item shows the next prayer and the time remaining — `🌙 Asr 1h 23m`. Clicking it opens a popover with today's full timings and the verse of the day; the main window holds the week ahead, your prayer streak, and a Quran reader.

## Features

- Menubar countdown to the next prayer, updated every second (redrawn only when the text changes)
- Popover with today's six timings, the current place, and the Hijri date
- Full window with today plus the next 7 days
- Local notifications at prayer time, with per-prayer toggles and an optional "N minutes before" offset
- Two-stage check-ins that ask whether you prayed, with Yes/No buttons right on the notification
- Prayer log with daily streaks, a best-streak record, and a 30-day history grid
- Quran reader with all 114 surahs, Arabic interleaved with your choice of 17 English translations
- Full-text translation search, bookmarks, resume-where-you-left-off, and a verse of the day
- Friday reminder to read Surah Al-Kahf
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

### Quran

The main window is a `NavigationSplitView`: prayer times and the Quran share one window. The location permission flow lives inside the prayer pane only, so a denied location never blocks reading.

**`QuranAPI`** fetches Arabic and translation in a single request per surah (`/v1/surah/{n}/editions/quran-uthmani,{translation}`) and normalises the text before anything else sees it. Two quirks in that feed make the normalisation load-bearing:

- The Uthmani edition **prepends the Basmala** to ayah 1 of every surah except 1 and 9, while translations do not. Left alone, the Arabic and the translation drift apart from the first verse. It is stripped and re-rendered as a header. Surah 1 keeps it, because there it genuinely *is* ayah 1; surah 9 never had one. Surah 1 also arrives with a stray U+FEFF.
- `sajda` is `false` on ordinary verses but an **object** on prostration verses, so decoding it as a `Bool` throws partway through Surah As-Sajda.

Surahs are cached to `Application Support/Sajadah/quran/` as they are read — 72 KB for Al-Kahf, 240 KB for the longest surah — and the cache is keyed by translation edition, so switching translation invalidates it. Bookmarks and reading position live in their own file, separate from that cache.

**The Arabic font is bundled.** macOS's own Arabic faces are UI fonts, and asking them to typeset Uthmani script goes visibly wrong: waqf marks float away from the word, the small high rounded zero degrades to a sukun, the small low meem is dropped, and the ayah marker leaves its numeral outside the rosette instead of nested inside it. Mishafi, despite the name, is optically tiny and collides its diacritics; Waseem mangles the shaping outright.

So the app ships **Amiri Quran** — purpose-built for Quranic typesetting, 137 KB, under the SIL Open Font License 1.1, which permits redistribution. It is registered into the process at launch via `CTFontManagerRegisterFontsForURL`, so nothing is installed into the user's Font Book. The system faces stay in the picker as a matter of taste, filtered to whatever actually resolves so the picker can never offer a font that would silently fall back. Settings shows a live preview, because the faces differ enormously at identical point sizes.

The font and its licence live in `Sajadah/Resources/Fonts/`.

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
