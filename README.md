<div align="center">

<img src="docs/brand/icon.png" width="128" alt="Sajadah">

# Sajadah

**Prayer times and Quran, in your macOS menubar.**

[![License: MIT](https://img.shields.io/badge/license-MIT-1F8A63.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-0B6E4F.svg)](#requirements)
[![Latest release](https://img.shields.io/github/v/release/shaheem-pp/sajadah-macos?color=A0742A&label=download)](https://github.com/shaheem-pp/sajadah-macos/releases/latest)

</div>

The menubar item shows the next prayer and the time remaining — `🌙 Asr 1h 23m`. Clicking it
opens a popover with today's full timings and the verse of the day; the main window holds the
week ahead, your prayer streak, and a Quran reader.

Timings come from the [Aladhan API](https://aladhan.com/prayer-times-api), the Quran from
[alquran.cloud](https://alquran.cloud/api), and your position from CoreLocation.

<div align="center">

<img src="docs/screenshots/home.png" width="900" alt="The main window: today's timings with Adhan beside the masjid's Jamaah time, a streak grid, and the next seven days">

<em>Today's six timings — Adhan beside your masjid's Jamaah time — your streak, and the week ahead.</em>

</div>

<table>
<tr>
<td width="34%" valign="top" align="center">
<img src="docs/screenshots/menubar.png" width="280" alt="The menubar popover: next prayer countdown, today's timings, streak and the ayah of the day">
</td>
<td width="66%" valign="top" align="center">
<img src="docs/screenshots/quran.png" width="640" alt="The Quran reader showing Surah Ar-Rahman: Uthmani Arabic in Amiri Quran with an English translation under each ayah">
</td>
</tr>
<tr>
<td align="center"><em>The popover — countdown, Iqamah, today's timings, and the ayah of the day.</em></td>
<td align="center"><em>The reader — Uthmani Arabic set in Amiri Quran, translation under each ayah.</em></td>
</tr>
</table>

## Download

### Install in one line — no security warning

```bash
curl -fsSL https://github.com/shaheem-pp/sajadah-macos/releases/latest/download/Sajadah.dmg -o /tmp/Sajadah.dmg &&
hdiutil attach -quiet /tmp/Sajadah.dmg &&
cp -R /Volumes/Sajadah/Sajadah.app /Applications/ &&
hdiutil detach -quiet /Volumes/Sajadah &&
rm /tmp/Sajadah.dmg &&
open /Applications/Sajadah.app
```

That downloads, installs to Applications, and opens the app.

It is worth knowing *why* this avoids the warning described below, rather than treating it as a
magic incantation: the quarantine flag that triggers macOS's block is attached by your **browser**
when it saves the file, not by macOS on everything you download. `curl` does not set it, so there
is nothing to clear.

### Already have an older version?

Same idea, with two extra steps. Copy the whole block:

```bash
killall Sajadah 2>/dev/null;
curl -fsSL https://github.com/shaheem-pp/sajadah-macos/releases/latest/download/Sajadah.dmg -o /tmp/Sajadah.dmg &&
hdiutil attach -quiet /tmp/Sajadah.dmg &&
rm -rf /Applications/Sajadah.app &&
cp -R /Volumes/Sajadah/Sajadah.app /Applications/ &&
hdiutil detach -quiet /Volumes/Sajadah &&
rm /tmp/Sajadah.dmg &&
open /Applications/Sajadah.app
```

The two additions matter:

- **Quitting first.** The old copy is running from the bundle being replaced, and its widget
  extension is loaded by macOS.
- **`rm -rf` before the copy.** `cp -R` onto an existing app *merges* directories rather than
  replacing them, so files that existed in the old version but not the new one survive — and a
  bundle containing files its signature doesn't account for fails validation and refuses to
  open. The delete deliberately comes after the download and mount have both succeeded, so a
  dropped connection can't leave you with no app at all.

Your prayer log, streak, bookmarks and settings are untouched: they live in a container outside
the app bundle, not inside it.

From 1.4 onwards you shouldn't have to come looking for this: Sajadah checks GitHub once a day,
says so in the popover when a release exists, and Settings → General has a **Copy Update
Command** button that puts these same steps on your clipboard as a single line. It stops there
rather than updating itself, because an ad-hoc signed bundle can't be safely replaced while it
is the one doing the replacing — which is the whole reason the block above quits first.

If you are coming from **1.2 or earlier, widgets were blank** — that's fixed. They fill in once
the updated app has run. If one still looks empty a minute later, remove it from Notification
Centre and add it again.

### Or download the DMG

**[⬇ Latest release](https://github.com/shaheem-pp/sajadah-macos/releases/latest)**

1. Open the `.dmg` and **drag Sajadah onto the Applications folder**. Opening the app directly
   from the mounted disk image is *not* the same as installing it — it looks like it should work,
   and then fails.
2. Eject the disk image.
3. Run this once in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Sajadah.app
   ```

The disk image carries these same instructions in a `Read Me First.txt`.

### Troubleshooting

> **"Sajadah" Not Opened**
> Apple could not verify "Sajadah" is free of malware that may harm your Mac or compromise your
> privacy.

Click **Done**. Do **not** click *Move to Trash* — it is the highlighted button, but it deletes
the app. Then run the `xattr` command above and open Sajadah normally. You only ever do this once.

That message means Sajadah is **not notarized by Apple**, which requires a paid Apple Developer
Program membership this project does not have. macOS shows exactly the same warning for an
unnotarized app as for a genuinely malicious one, so it is fair to be cautious: the source is
public, the build is produced by a [GitHub Actions workflow](.github/workflows/release.yml) you
can read, and every release publishes a SHA-256 you can check against your download.

Going through **System Settings → Privacy & Security → Open Anyway** also works. The old
right-click → *Open* trick does not, on macOS 15 and later.

### One known limitation of unsigned builds

- **Launch at Login** may fail. macOS's `SMAppService` requires a full developer signature. The
  toggle in Settings reports the error rather than silently lying about its state. It works
  correctly when you build from source with your own Apple ID — about two minutes.

Widgets used to be listed here too. They now work on unsigned builds; see
[Widgets](#widgets).

## Requirements

- **macOS 15** (Sequoia) or later to run
- **Xcode 26** or later to build

## Features

- Menubar countdown to the next prayer, redrawn only when the text actually changes — and only woken once a minute unless a seconds countdown is on screen
- Popover with today's six timings, the current place, and the Hijri date — which turns over at Maghrib, when the Islamic day begins, or at midnight if you'd rather match a printed calendar
- Full window with today plus the next 7 days
- Local notifications at prayer time, with per-prayer toggles and an optional "N minutes before" offset
- Iqamah reminders a configurable number of minutes before your masjid's congregation time
- Two-stage check-ins that ask whether you prayed — shortly after the Adhan, and once more as the window closes — with Yes/No buttons right on the notification
- Prayer log with daily streaks, a best-streak record, and a five-week calendar — click any day to log or correct it
- Quran reader with all 114 surahs, Arabic interleaved with your choice of 17 English translations
- Full-text translation search, bookmarks, resume-where-you-left-off, and a verse of the day
- Friday reminder to read Surah Al-Kahf, plus an optional daily reading reminder
- Sunnah fasting days — Mondays, Thursdays and the white days — marked beside the Hijri date, with a reminder the evening before. Off by default; never in Ramadan or on a day fasting is forbidden
- Hijri dates from Aladhan's Umm al-Qura calendar as adjusted to Saudi Arabia's sighting announcements, with a ±2-day adjustment for communities that saw the moon on a different night
- 17 calculation methods and both Asr conventions, changeable in Settings — a sidebar window in the shape System Settings uses
- Works offline: timings are cached a month at a time on disk and keep displaying with an "Offline" badge if a refresh fails
- Refreshes on wake, on day rollover, on clock changes, and when you move more than 5 km
- Optional launch at login
- Notices when a new release exists and hands you the command to install it — checked once a day, switchable off in Settings
- Lives in the menubar: no Dock icon unless a window is open, and one window rather than a new one per click
- Masjid Iqamah times — scraped from your masjid's own page, or computed as minutes after Adhan for masjids with no site of their own — shown in the menubar, popover, main window and a widget

## Widgets

Sajadah ships a WidgetKit extension. Add widgets from Notification Centre → Edit Widgets.

| Widget | Sizes | Shows |
|---|---|---|
| Next prayer | Small, Medium | The next prayer, its time, and the countdown, over that hour's sky gradient |
| Today | Medium, Large | All six timings with the next one marked, plus your streak |
| Masjid Iqamah | Medium, Large | Adhan → Iqamah for each daily prayer, plus Jummah, from your configured masjid (Settings → Masjid) |
| Verse of the day | Medium, Large | The day's ayah in Arabic with its translation |

Widgets read the same on-disk cache the app writes, so they keep working offline and cost no
extra network requests. Tapping one deep-links into the app via a `sajadah://` URL.

That cache normally lives in an App Group container. On a downloaded release it can't: releases
are ad-hoc signed, macOS grants App Group containers by matching them against the signature's
team identifier, and an ad-hoc signature has none — so the kernel denies the widget every read.
Dropping the extension's sandbox isn't an option either, because PlugInKit refuses to load an
unsandboxed plug-in at all. The one place a sandboxed extension can always read is its own
container, so the app mirrors the four files widgets need into it. Signed builds keep using the
App Group and never touch the mirror. See `Shared/Storage/AppFiles.swift`.

## Building from source

```bash
git clone https://github.com/shaheem-pp/sajadah-macos.git
cd sajadah-macos
open Sajadah.xcodeproj
```

**Set your own signing team before building** — both targets are configured against the
author's. Select the **Sajadah** target → **Signing & Capabilities** → **Team**, then do the
same for **SajadahWidgets**. Nothing else needs editing; the App Group is written as
`$(TeamIdentifierPrefix)dev.shaheem.Sajadah` and picks up your team automatically.

Then ⌘R. On first launch the app asks for location and notification permission.

If `xcodebuild` fails with a Command Line Tools error, point `DEVELOPER_DIR` at Xcode:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Sajadah build
```

Location does not work reliably in SwiftUI Previews under the sandbox — run the app normally.

### Releasing

Pushing to `main` publishes nothing. Releases are cut by pushing a tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

That triggers [`.github/workflows/release.yml`](.github/workflows/release.yml), which builds the
app, packages the DMG, and publishes a GitHub Release with install instructions, the SHA-256,
and an auto-generated changelog. It needs **no secrets** — the build is ad-hoc signed, so there
is no certificate to store.

To build a DMG locally without releasing anything:

```bash
./scripts/release.sh 1.0.0
```

Both paths run the same script and produce the same artifact.

## Architecture

Both targets use Xcode's file-system-synchronized groups: **the folder structure on disk _is_
the project structure**, so adding or moving a Swift file needs no `.xcodeproj` change.

```
Shared/            Compiled into BOTH the app and the widget extension
  Models/          Prayer, PrayerLog, Quran, Iqamah — plain value types
  Design/          Theme (colours, metrics) and IslamicOrnaments (shapes)
  Storage/         App Group file locations and the on-disk cache
  Fonts/           Amiri Quran + the code that registers it
Sajadah/
  App/             Entry point, AppCoordinator, navigation
  Services/        Network clients, CoreLocation, notifications, the ticker, IqamahScraper, IqamahOffsetCalculator, UpdateChecker
  Stores/          Observable state: timings, prayer log, Quran, settings, Iqamah, updates
  Features/        One folder per surface — MenuBar, Prayer, Quran, Settings
  UI/              Shared views and formatting used across features
SajadahWidgets/    WidgetKit extension
```

## How it works

`AppCoordinator` owns the long-lived objects and wires them together, so the connections hold
whether or not any view is on screen:

- **`LocationManager`** publishes a `State` enum (`loading` / `home` / `needPermission` / `denied` / `error`) and hands fresh coordinates to the store through a callback.
- **`AladhanAPI`** fetches one calendar month per request from `/v1/calendar/{year}/{month}` with `iso8601=true`, so every timing arrives as a fully-offset instant and DST needs no special handling.
- **`PrayerTimesStore`** caches months to the App Group container, always keeps at least 8 days of timings ahead of today, and answers "what's next?" by searching a flat sorted list of events — which is what makes the countdown cross midnight correctly.
- **`Ticker`** advances the clock via an async loop rather than a run-loop timer, so it keeps ticking while the popover is open. The interval follows the audience: once a second while something with a seconds countdown is on screen, otherwise once a minute — the menubar reads "5h 9m" and cannot change faster than that, so waking sixty times to recompute it was fifty-nine times too many. That minute is measured to the *prayer*, not the wall clock: a prayer at 13:00:30 flips the display at :30 past each minute, so sleeping to :00 would leave the menubar up to a minute stale. Anything appearing on screen restarts the loop, so opening the popover never shows a frozen countdown.
- **`NotificationScheduler`** rebuilds the pending batch whenever timings, preferences or the prayer log change. Every candidate is built, sorted by fire date, and the nearest 60 kept, so the 64-request budget always goes to whatever happens soonest. Two details are load-bearing: rebuilds are serialised, because two overlapping ones used to delete each other's requests; and the batch is diffed rather than wiped, because `add` already replaces a request with the same identifier and removing one you are about to re-add is a race with nothing to gain. Authorization is re-read on every rebuild, so granting permission in System Settings takes effect without a relaunch.
- **`PrayerLogStore`** records what was prayed in its own file, deliberately separate from the timings cache: it is the user's own data and must survive a location change, a method change or a cache wipe.

### Iqamah

Adhan (the call to prayer) is calculated; Iqamah (when the congregation actually starts) is set
by each masjid and published nowhere but its own website — so Sajadah reads it two ways,
configurable in Settings → Masjid:

- **From a masjid's page.** `IqamahScraper` fetches the page and looks for recognisable prayer
  labels ("Fajr", "Dhuhr", …) next to a time-like token, rather than at any CSS selector or DOM
  path. That's deliberate: a real WordPress/Elementor page inspected while building this has
  every element's class auto-generated (`elementor-element-0006389`) and regenerated on every
  redesign, while the label text is exactly what a human visitor reads to find the times — the
  one thing unlikely to disappear. A page missing one prayer still reports the other six rather
  than failing outright, with a live preview in Settings of exactly what was found before it's
  ever relied on. Pages that render their schedule with JavaScript (Next.js, React, Nuxt,
  Angular) are fingerprinted from markers already in the plain HTTP response and named
  specifically in the error, since a page fetch never executes that script and the text
  genuinely never arrives — no matter how the label search is tuned.
- **Minutes after Adhan.** For masjids with no posted schedule, or a site the scraper can't read,
  a fixed per-prayer offset — Maghrib defaults shorter than the rest, matching how most masjids
  actually run it — computed straight from the Adhan times already on hand. No network involved.

A scraped page is re-read twice a day, both driven off the calendar rather than a timer, so
they cost nothing while the app isn't running: at midnight, because a posted schedule belongs to
a day and today's has just become yesterday's; and once in the afternoon, because masjids
sometimes correct a same-day posting and catching that before Asr is the difference between
right and wrong for three prayers. A Mac asleep at midnight syncs on the first tick after waking.

Either source produces the same `IqamahTimes` value, so the menubar badge, popover row, widget
and window card don't know or care which one produced it. The menubar shows one clock, never
both: normally it counts down to the next Adhan, but the moment some prayer's Adhan passes with
its Iqamah still ahead, the display retargets to that Iqamah instead of silently jumping to the
*following* prayer's Adhan and dropping the one still coming up.

### Quran

The main window is a `NavigationSplitView`: prayer times and the Quran share one window. The
location permission flow lives inside the prayer pane only, so a denied location never blocks
reading.

**`QuranAPI`** fetches Arabic and translation in a single request per surah
(`/v1/surah/{n}/editions/quran-uthmani,{translation}`) and normalises the text before anything
else sees it. Two quirks in that feed make the normalisation load-bearing:

- The Uthmani edition **prepends the Basmala** to ayah 1 of every surah except 1 and 9, while translations do not. Left alone, the Arabic and the translation drift apart from the first verse. It is stripped and re-rendered as a header. Surah 1 keeps it, because there it genuinely *is* ayah 1; surah 9 never had one. Surah 1 also arrives with a stray U+FEFF.
- `sajda` is `false` on ordinary verses but an **object** on prostration verses, so decoding it as a `Bool` throws partway through Surah As-Sajda.

Surahs are cached as they are read — 72 KB for Al-Kahf, 240 KB for the longest surah — and the
cache is keyed by translation edition, so switching translation invalidates it. Bookmarks and
reading position live in their own file, separate from that cache.

**The Arabic font is bundled.** macOS's own Arabic faces are UI fonts, and asking them to
typeset Uthmani script goes visibly wrong: waqf marks float away from the word, the small high
rounded zero degrades to a sukun, the small low meem is dropped, and the ayah marker leaves its
numeral outside the rosette instead of nested inside it. Mishafi, despite the name, is
optically tiny and collides its diacritics; Waseem mangles the shaping outright.

So the app ships **Amiri Quran** — purpose-built for Quranic typesetting, 137 KB, under the SIL
Open Font License 1.1, which permits redistribution. It is registered into the process at launch
via `CTFontManagerRegisterFontsForURL`, so nothing is installed into the user's Font Book. The
system faces stay in the picker as a matter of taste, filtered to whatever actually resolves so
the picker can never offer a font that would silently fall back. Settings shows a live preview,
because the faces differ enormously at identical point sizes.

The font and its licence live in [`Shared/Fonts/`](Shared/Fonts/).

### Check-ins

Each prayer is asked about as its own window closes. A prayer's window runs until the next one
begins; Isha has no following prayer, so it runs to a cutoff time you set (default 11pm).

| Prayer | Window closes at |
|---|---|
| Fajr | Sunrise |
| Dhuhr | Asr |
| Asr | Maghrib |
| Maghrib | Isha |
| Isha | Your evening cutoff |

The ask escalates in two stages. Ten minutes before the window closes you get a soft "Did you
pray Asr?" — answering **Yes** logs it, **Not yet** records nothing. If it is still unlogged
when the window actually closes, the question comes back as a final ask, and **No** there marks
it missed. Answering at either stage retires the other, because the batch is rebuilt from
scratch and skips anything already answered.

Anything you miss can still be logged by clicking the circle beside a prayer in the popover,
and any past day by clicking it in the window's five-week calendar — which is the whole answer
for someone who prays every day and logs none of them: one click per skipped day, not five.

### Fasting

Off by default, in Settings → Fasting. Two rules, each its own switch: Mondays and Thursdays,
and the white days — the 13th, 14th and 15th of each Hijri month. Ramadan is skipped because
everyone is already fasting, and the days fasting is forbidden win over any reason to: both
Eids and the three days of Tashreeq after Eid al-Adha, which means 13 Dhū al-Ḥijjah is left out
even though it is a white day. When a Monday falls on a white day there is one label and one
notification naming both, not two.

The reminder lands the evening *before* the fast, because that is when a fast is decided on —
after Maghrib by default, which is also when the Islamic day begins, or at a clock time of your
choosing. It names the day and gives the time of Fajr, so suhoor can be planned. The reminders
are one-shots in the same diffed batch as everything else rather than repeating weekday
triggers: the white days move with the Hijri calendar, and a Monday in Ramadan must not fire.
They are gated independently of the prayer-time notifications, for the same reason the Iqamah
reminder is.

The Hijri date all of this hangs off comes from Aladhan's `HJCoSA` calendar — Umm al-Qura,
adjusted to Saudi Arabia's official sighting announcements — pinned explicitly rather than
inherited as the API's default, because the offline fallback (Foundation's own Umm al-Qura
calendar, used only for a day the cache doesn't hold) is chosen to agree with it. A community
that sighted the moon a night earlier or later is a day off from that, and nothing on the Mac
can tell which, so Settings → Fasting has a ±2-day adjustment: set +1 if your masjid began the
month a day earlier. The adjusted date for a day is simply the unadjusted date of the
neighbouring one, which keeps month lengths right without any Hijri arithmetic of our own, and
the popover, the window, the widget and the fasting days all follow it. By default the displayed
date turns over at Maghrib, when the Islamic day begins; a switch makes it change at midnight
instead for anyone checking against a printed calendar at 9pm. The date in the popover is
clickable and leads to these settings, since the date is the thing you'd want to adjust.

### Design

Two colours carry the identity — a deep jade and a warm brass, both long-standing in Islamic
art — kept desaturated so they read as a wash over macOS's own materials rather than as chrome
painted on top. Each prayer also carries the light of its hour: low-chroma gradients that tell
dawn from dusk at a glance without fighting the text on them.

The ornament in [`Shared/Design/IslamicOrnaments.swift`](Shared/Design/IslamicOrnaments.swift)
is drawn from geometry rather than traced. The **Rub el Hizb** — the eight-pointed star that
marks each eighth of the Quran — is the union of two squares at 45°, so its inner radius is not
a free parameter: the crossing point sits at `cos(45°) / cos(22.5°)` ≈ 0.765 of the outer
radius, and any other value stops being a khatim. The **mihrab arch** is built the way a real
one is, from two circular arcs each centred on the *opposite* springing point, so they meet at
an angle and leave a genuine point at the apex; joining them tangentially instead just produces
a rounded rectangle.

The app icon is generated from that same `MihrabArch` shape rather than drawn by hand, so it
can't drift from the UI:

```bash
./scripts/make-icon.sh
```

## Privacy

No account, no analytics, no telemetry. Your coordinates go to `api.aladhan.com` to compute
timings — that is the only personal data that leaves your Mac, and it goes to no one else.
Everything you generate (prayer log, streaks, bookmarks, reading position) stays local.

Three other requests carry nothing of yours: surah text from `api.alquran.cloud`, your masjid's
own page for its Iqamah schedule, and a daily `GET` to `api.github.com` asking whether a newer
release exists. That last one can be turned off in Settings → General.

Full detail in [PRIVACY.md](PRIVACY.md).

## Roadmap

- Qibla direction (bearing + compass)
- Manual city override for when location is unavailable
- Adhan audio at prayer time
- Render JavaScript-heavy masjid pages (via a headless `WKWebView`) so the Iqamah scraper can
  read sites it currently can't — deferred so far because it's heavier and slower per check than
  a plain fetch, and "Minutes after Adhan" already covers the same masjids in the meantime

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the build
setup and a tour of the layout.

## Licence

Sajadah is [MIT licensed](LICENSE).

The bundled **Amiri Quran** font is © 2010–2022 The Amiri Project Authors and is used under the
SIL Open Font License 1.1. Full attributions in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Support

Sajadah is free and always will be. If it's useful to you, a coffee is very welcome.

<!-- TODO: claim a handle at buymeacoffee.com, then replace YOUR-HANDLE below and
     uncomment the matching line in .github/FUNDING.yml -->
<!--
<a href="https://www.buymeacoffee.com/YOUR-HANDLE">
  <img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-A0742A?style=for-the-badge&logo=buymeacoffee&logoColor=white" alt="Buy me a coffee">
</a>
-->
