# Privacy

Sajadah has no account, no analytics, no telemetry, no crash reporting and no advertising. It
makes four kinds of outbound request, none of which needs a key, a token or an account.

## What leaves your Mac

| Sent | To | Why | How often |
|---|---|---|---|
| Your latitude and longitude, calculation method, Asr school | `api.aladhan.com` | Prayer timings can't be computed without a position | Once per calendar month per location, plus when you move more than 5 km or change a calculation setting |
| Surah number, translation edition | `api.alquran.cloud` | Fetches Quranic text | Once per surah, then cached |
| Nothing but the request itself | your masjid's own website | Reads the Iqamah schedule it posts | Twice a day, and only while Settings → Masjid is set to read a page |
| Nothing but the request itself | `api.github.com` | Asks whether a newer release exists | Once a day, and only while update checks are on |

The last two send no data of yours. They are listed anyway because any HTTP request tells the
host your IP address, and that is worth stating plainly rather than filing under "nothing".
Neither carries a version-independent identifier, a cookie, or anything about your prayers,
location or reading. The update check is a plain unauthenticated `GET` of the newest release,
which is also why no token is shipped inside a public app; turning it off in Settings → General
stops it outright.

Reverse geocoding — turning your coordinates into "Toronto, ON" for the popover header — is
handled **on-device** by Apple's MapKit/CoreLocation. Those coordinates are not sent to a
third party for that purpose.

Sajadah has no server of its own. Nothing is sent to the author.

## What stays on your Mac

All of it, in an App Group container shared between the app and its widgets:

- Prayer timings cache (`prayer-cache.json`)
- Your prayer log, streaks and best-streak record
- Quran text cache, bookmarks and reading position
- The last update check's result (`update-check.json`) — a version number and a URL
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
