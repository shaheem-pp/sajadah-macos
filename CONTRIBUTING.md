# Contributing to Sajadah

Thanks for taking a look. Issues and pull requests are both welcome.

## Building

You need **Xcode 26 or later** (the project uses Swift 6.2 language features) to build, but the
app itself runs on **macOS 15 or later**.

```bash
git clone https://github.com/shaheem-pp/sajadah-macos.git
cd sajadah-macos
open Sajadah.xcodeproj
```

**One setting must change before it will build for you.** Both targets are code-signed against
the author's Apple Developer team:

1. Select the **Sajadah** target → **Signing & Capabilities** → set **Team** to your own.
2. Do the same for the **SajadahWidgets** target.

Nothing else needs editing. The App Group identifier is written as
`$(TeamIdentifierPrefix)dev.shaheem.Sajadah` in the entitlements and Info.plists, so it picks up
your team automatically. If you also change the bundle identifier, update it in both
entitlements files and both Info.plists to match.

Then build and run (⌘R). On first launch the app asks for location and notification permission.

Location does not work reliably in SwiftUI Previews under the sandbox — run the app normally.

## Layout

Both targets use Xcode's file-system-synchronized groups, which means **the folder structure on
disk _is_ the project structure**. Adding, moving or deleting a `.swift` file needs no
`.xcodeproj` change — just put it in the right folder.

```
Shared/            Compiled into BOTH the app and the widget extension
  Models/          Prayer, PrayerLog, Quran — plain value types
  Design/          Theme (colours, metrics) and IslamicOrnaments (shapes)
  Storage/         App Group file locations and the on-disk cache
  Fonts/           Amiri Quran + the code that registers it
Sajadah/
  App/             Entry point, AppCoordinator, navigation
  Services/        Network clients, CoreLocation, notifications, the ticker
  Stores/          Observable state: timings, prayer log, Quran, settings
  Features/        One folder per surface — MenuBar, Prayer, Quran, Settings
  UI/              Shared views and formatting used across features
SajadahWidgets/    WidgetKit extension
```

`AppCoordinator` owns every long-lived object and wires them together with callbacks, so the
connections hold whether or not any view is on screen. If you add a store, register it there and
add it to `sajadahEnvironment(_:)` in the same file — that one function feeds all three scenes.

## Brand assets

The app icon is generated from the app's own `MihrabArch` shape rather than drawn by hand, so it
can't drift from the UI. After changing anything in `Shared/Design/`:

```bash
./scripts/make-icon.sh
```

That rewrites `Sajadah/Assets.xcassets/AppIcon.appiconset/` and `docs/brand/`.

## Packaging a DMG

```bash
./scripts/release.sh 1.0.0
```

Needs no signing certificate — it builds and signs ad-hoc, which is also what lets the same
script run in CI with no secrets.

Install `create-dmg` if you are changing the disk image itself:

```bash
brew install create-dmg
```

Without it the script falls back to `hdiutil`, which works but produces a plain window with no
icon positioning — and the `Read Me First.txt` that tells people how to get past Gatekeeper is
easy to miss there. The volume name is deliberately fixed at `Sajadah` rather than versioned,
because the documented one-line installer copies from `/Volumes/Sajadah`.

## Style

Match the surrounding code. The one convention worth stating: **comments explain _why_, not
_what_.** Most comments in this codebase document a constraint that isn't obvious from the code
— an API quirk, a platform limitation, a decision that looks arbitrary until you know what it
prevents. If a comment restates the line below it, leave it out.

## Pull requests

- One concern per PR.
- Say what you tested. There is no test suite yet; describe what you exercised by hand.
- If you change anything user-facing, mention whether the README needs updating.
