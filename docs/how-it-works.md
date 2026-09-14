# How Sajadah works

Design notes and the reasoning behind the less obvious choices. Nothing here is needed to
install or use the app — that is all in the [README](../README.md). This is for anyone
reading or changing the code, and for the author six months from now.

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

## The moving parts

`AppCoordinator` owns the long-lived objects and wires them together, so the connections hold
whether or not any view is on screen:

- **`LocationManager`** publishes a `State` enum (`loading` / `home` / `needPermission` / `denied` / `error`) and hands fresh coordinates to the store through a callback.
- **`AladhanAPI`** fetches one calendar month per request from `/v1/calendar/{year}/{month}` with `iso8601=true`, so every timing arrives as a fully-offset instant and DST needs no special handling.
- **`PrayerTimesStore`** caches months to the App Group container, always keeps at least 8 days of timings ahead of today, and answers "what's next?" by searching a flat sorted list of events — which is what makes the countdown cross midnight correctly. The cache holds the API's own times; the per-prayer minute adjustments from Settings → Advanced are applied when the store derives the timings every reader uses, and the widget applies the same arithmetic to the same file. Changing an offset is therefore instant and offline, and turning the switch off restores the computed times without a fetch.
- **`Ticker`** advances the clock via an async loop rather than a run-loop timer, so it keeps ticking while the popover is open. The interval follows the audience: once a second while something with a seconds countdown is on screen, otherwise once a minute — the menubar reads "5h 9m" and cannot change faster than that, so waking sixty times to recompute it was fifty-nine times too many. That minute is measured to the *prayer*, not the wall clock: a prayer at 13:00:30 flips the display at :30 past each minute, so sleeping to :00 would leave the menubar up to a minute stale. Anything appearing on screen restarts the loop, so opening the popover never shows a frozen countdown.
- **`NotificationScheduler`** rebuilds the pending batch whenever timings, preferences or the prayer log change. Every candidate is built, sorted by fire date, and the nearest 60 kept, so the 64-request budget always goes to whatever happens soonest. Two details are load-bearing: rebuilds are serialised, because two overlapping ones used to delete each other's requests; and the batch is diffed rather than wiped, because `add` already replaces a request with the same identifier and removing one you are about to re-add is a race with nothing to gain. Authorization is re-read on every rebuild, so granting permission in System Settings takes effect without a relaunch.
- **`PrayerLogStore`** records what was prayed in its own file, deliberately separate from the timings cache: it is the user's own data and must survive a location change, a method change or a cache wipe.

## Iqamah

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

## The window

The main window is a `NavigationSplitView`: prayer times and the Quran share one window. The
location permission flow lives inside the prayer pane only, so a denied location never blocks
reading. The Today page lays itself out by width: two columns when there is room — the panel
and the day's rows on the left, the streak, the fasts ahead and the verse on the right, the
week table under both — and one column, top to bottom in that order, when there isn't.

## Quran

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

The font and its licence live in [`Shared/Fonts/`](../Shared/Fonts/).

## Check-ins

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

## Fasting

Off by default, in Settings → Fasting. Four rules, each its own switch: Mondays and Thursdays;
the white days — the 13th, 14th and 15th of each Hijri month; Ashura, with the 9th of Muḥarram
alongside the 10th; and the day of Arafah, 9 Dhū al-Ḥijjah. The days fasting is forbidden win
over any reason to: both Eids and the three days of Tashreeq after Eid al-Adha, which means
13 Dhū al-Ḥijjah is left out even though it is a white day. When a Monday falls on a white day
there is one label and one notification naming both, not two.

Ramadan has no switch — there is no choice to make about it — and is treated differently in
both directions. The label beside the date is the time of iftar rather than "fasting day",
since the date beside it already says which day of the month it is, and the only reminder is
the one the evening before the 1st: a month of nightly "fasting tomorrow" is the notification
nobody in Ramadan needs. The Today page's Fasting card carries the day of the month with suhoor
and iftar for it — tomorrow's once Maghrib has passed — and, outside Ramadan, the fasts in the
fortnight ahead; the week table marks them too.

The reminder lands the evening *before* the fast, because that is when a fast is decided on —
after Maghrib by default, which is also when the Islamic day begins, or at a clock time of your
choosing. It names the day and gives the time of Fajr, so suhoor can be planned. The reminders
are one-shots in the same diffed batch as everything else rather than repeating weekday
triggers: the white days move with the Hijri calendar, and a Monday in Ramadan must not fire
on its own. They are gated independently of the prayer-time notifications, for the same reason
the Iqamah reminder is.

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

## Design

Two colours carry the identity — a deep jade and a warm brass, both long-standing in Islamic
art — kept desaturated so they read as a wash over macOS's own materials rather than as chrome
painted on top. Each prayer also carries the light of its hour: low-chroma gradients that tell
dawn from dusk at a glance without fighting the text on them.

The ornament in [`Shared/Design/IslamicOrnaments.swift`](../Shared/Design/IslamicOrnaments.swift)
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

## Installing without a warning

The one-line install in the README avoids the "Apple could not verify" dialog for a reason
worth knowing, rather than being a magic incantation: the quarantine flag that triggers
macOS's block is attached by your **browser** when it saves the file, not by macOS on
everything you download. `curl` does not set it, so there is nothing to clear.

The dialog itself means Sajadah is **not notarized by Apple**, which requires a paid Apple
Developer Program membership this project does not have. macOS shows exactly the same warning
for an unnotarized app as for a genuinely malicious one, so it is fair to be cautious: the
source is public, the build is produced by a [GitHub Actions workflow](../.github/workflows/release.yml)
you can read, and every release publishes a SHA-256 you can check against your download.
Going through **System Settings → Privacy & Security → Open Anyway** also works. The old
right-click → *Open* trick does not, on macOS 15 and later.

The update command quits the app and deletes the old bundle before copying the new one in,
and both steps matter:

- **Quitting first.** The old copy is running from the bundle being replaced, and its widget
  extension is loaded by macOS.
- **`rm -rf` before the copy.** `cp -R` onto an existing app *merges* directories rather than
  replacing them, so files that existed in the old version but not the new one survive — and a
  bundle containing files its signature doesn't account for fails validation and refuses to
  open. The delete deliberately comes after the download and mount have both succeeded, so a
  dropped connection can't leave you with no app at all.

The app checks GitHub once a day and offers that command from Settings rather than updating
itself, because an ad-hoc signed bundle can't be safely replaced while it is the one doing the
replacing. **Launch at Login** may fail on a downloaded build for a related reason: macOS's
`SMAppService` requires a full developer signature. The toggle reports the error rather than
silently lying about its state; it works when you build from source with your own Apple ID.


## Widgets

Each widget answers one question, and each size is designed rather than stretched: small is
the answer, medium the answer with its context, large the whole day. The two backgrounds are
the app's own: the hour's sky, with the mihrab niche rising off the bottom edge, for anything
about *now*; the quiet lattice for reference material. Text on the sky is white at graded
opacities and text on the lattice is the system's own hierarchy, so both follow light and dark
mode without a second palette.

The Next Prayer widget is worded by the same `DayPhase` the hero and the menubar use, through
`DayPhase.resolve` in [`Shared/Models/DayPhase.swift`](../Shared/Models/DayPhase.swift), so
the desktop can't describe a moment differently from the popover. The one setting that rule
needs which wasn't already in the cache — the Isha cutoff — is now written into it alongside
the Hijri and fasting preferences. The rule also reads the log: a prayer already logged has
no jamaah left to catch and no window left to watch, so all three move on to the next Adhan
the moment it is ticked, rather than counting down to a jamaah for something already prayed.
Countdowns are `Text(timerInterval:)`, which ticks on its own; the timeline only carries an
entry at each instant the *wording* changes — every Adhan, every Iqamah and the quarter-hour
before it, each Isha cutoff, and midnight — a few dozen entries a day rather than one a minute.

The Prayer Log widget's buttons are `AppIntent`s, and the extension can't write the log
itself (see below), so a tap becomes one small JSON file in
[`Shared/Storage/WidgetLogInbox.swift`](../Shared/Storage/WidgetLogInbox.swift)'s directory —
the extension's own container, which the app already reaches to mirror the cache. The widget
lays pending taps over the log it reads, so a button shows as pressed immediately; the app
folds the files into the real log at launch, on activation, and the moment one appears, via a
kernel event on the directory. One file per tap means two processes never edit the same file.

Times in every widget are shown in the timezone the timings were calculated for, not the
Mac's — the same rule the app applies — so the two can't disagree on a trip.

The views take the widget family as a plain parameter rather than reading the environment, so
they can be rendered outside WidgetKit. The redesign was checked that way, with a small
`ImageRenderer` harness drawing every widget at every size in both appearances across a day's
phases; there is no other way to see a macOS widget short of adding it to the desktop.

## Widgets on unsigned builds

Widgets read the same on-disk cache the app writes, so they keep working offline and cost no
extra network requests. Tapping one deep-links into the app via a `sajadah://` URL.

That cache normally lives in an App Group container. On a downloaded release it can't: releases
are ad-hoc signed, macOS grants App Group containers by matching them against the signature's
team identifier, and an ad-hoc signature has none — so the kernel denies the widget every read.
Dropping the extension's sandbox isn't an option either, because PlugInKit refuses to load an
unsandboxed plug-in at all. The one place a sandboxed extension can always read is its own
container, so the app mirrors the four files widgets need into it. Signed builds keep using the
App Group and never touch the mirror. See [`Shared/Storage/AppFiles.swift`](../Shared/Storage/AppFiles.swift).

## Releasing

Pushing to `main` publishes nothing. Releases are cut by pushing a tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

That triggers [`.github/workflows/release.yml`](../.github/workflows/release.yml), which builds the
app, packages the DMG, and publishes a GitHub Release with install instructions, the SHA-256,
and an auto-generated changelog. It needs **no secrets** — the build is ad-hoc signed, so there
is no certificate to store.

To build a DMG locally without releasing anything:

```bash
./scripts/release.sh 1.0.0
```

Both paths run the same script and produce the same artifact.
