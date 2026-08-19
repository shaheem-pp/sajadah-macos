# Third-party notices

Sajadah itself is MIT licensed (see [LICENSE](LICENSE)). It redistributes and depends on the
following third-party work.

## Bundled in the app

### Amiri Quran (font)

Copyright 2010–2022 The Amiri Project Authors — <https://github.com/aliftype/amiri>

Licensed under the **SIL Open Font License, Version 1.1**. The full licence text ships
alongside the font at [`Shared/Fonts/OFL.txt`](Shared/Fonts/OFL.txt).

The font is registered into the running process with `CTFontManagerRegisterFontsForURL(…,
.process, …)`, so it is never installed into the user's Font Book and no system font is
modified. The OFL permits this redistribution; the font is not sold on its own and the
Reserved Font Name is unchanged.

## Network services

Neither service requires an API key, and Sajadah sends no credentials to either.

### Aladhan Prayer Times API — <https://aladhan.com/prayer-times-api>

Used for prayer timings. **Receives the user's latitude and longitude**, plus the chosen
calculation method and Asr school. See [PRIVACY.md](PRIVACY.md).

### alquran.cloud API — <https://alquran.cloud/api>

Used for Quranic text and translations. Receives only the surah number and translation
edition — no location, no identifier.

## Platform frameworks

SwiftUI, WidgetKit, CoreLocation, MapKit, UserNotifications and ServiceManagement are Apple
frameworks used under the Apple SDK licence. No third-party Swift packages are vendored;
`Package.resolved` does not exist because the project has no external dependencies.
