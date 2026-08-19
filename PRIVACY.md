# Privacy

Sajadah has no account, no analytics, no telemetry, no crash reporting and no advertising. It
makes exactly two kinds of outbound request, both to public APIs that require no key.

## What leaves your Mac

| Sent | To | Why | How often |
|---|---|---|---|
| Your latitude and longitude, calculation method, Asr school | `api.aladhan.com` | Prayer timings can't be computed without a position | Once per calendar month per location, plus when you move more than 5 km or change a calculation setting |
| Surah number, translation edition | `api.alquran.cloud` | Fetches Quranic text | Once per surah, then cached |

Reverse geocoding — turning your coordinates into "Toronto, ON" for the popover header — is
handled **on-device** by Apple's MapKit/CoreLocation. Those coordinates are not sent to a
third party for that purpose.

Sajadah has no server of its own. Nothing is sent to the author.

## What stays on your Mac

All of it, in an App Group container shared between the app and its widgets:

- Prayer timings cache (`prayer-cache.json`)
- Your prayer log, streaks and best-streak record
- Quran text cache, bookmarks and reading position
- Preferences, in `UserDefaults`

Deleting the app removes the container. None of this is synced, backed up to a service, or
readable by anything but Sajadah.

## Permissions

- **Location** — required to compute timings. Denying it leaves the Quran reader fully usable;
  only the prayer pane is blocked.
- **Notifications** — required for prayer reminders and check-ins. Denying it leaves the app
  working, silently.

## Questions

Open an issue at <https://github.com/shaheem-pp/sajadah-macos/issues>.
