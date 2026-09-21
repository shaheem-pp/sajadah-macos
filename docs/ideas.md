# Ideas on the table

Things being considered, as of 21 September 2026, and whether they belong. Nothing here is
committed — the README's Roadmap is the agreed list; this is the thinking behind the
harder calls, kept so it doesn't have to be redone. The [how-it-works](how-it-works.md) notes
cover what *is* built.

## The worry first: is this still a menubar app?

It is already more than "a countdown in the menubar" — a window, a Quran reader, six widgets,
six kinds of notification, seven settings panes. But every one of those is about the person
praying: when, where, whether they did, what to read. The app has never once talked about
*itself*.

Most of what's on the table below is exactly that: the app telling the user about updates,
about money, about announcements. That is the line, not the feature count. A test for anything
new:

1. Does it help someone pray on time or read the Quran?
2. Does it need a server, an account, or a paid membership? (Nothing shipped so far does.)
3. Does it send a notification nobody opted into?
4. Does it change [PRIVACY.md](../PRIVACY.md)?

| | Prays / reads | Server or paid | Uninvited notification | Privacy page |
|---|---|---|---|---|
| Push notifications (APNs) | no | both | yes | yes |
| "Update available" row | no, but harmless | no | no | already listed |
| Buy-me-a-coffee row | no | no | no | no |
| Donation notification in Ramadan | no | no | yes | no |
| Last-ten-nights times and markers | **yes** | no | no | no |
| ⌘Q keeps the menubar item | **yes** (it's a bug) | no | no | no |
| Fasting chip and hero height | **yes** (layout) | no | no | no |

Anything in the first column stays welcome. Anything with a *yes* in the third column is how
an app gets muted — the code already says so, twice, in
[AppSettings](../Sajadah/Stores/AppSettings.swift) — and should be the last resort, not the
first idea.

## What decides most of this: the paid developer account

Three of the five items turn on whether to pay Apple the yearly membership. Today every
release is ad-hoc signed, which is why the README has the `xattr` step, why Launch at Login
fails on downloaded builds, and why the widget cache is copied into the extension's own
container. The membership would unlock, in order of how much it matters:

- **Notarization.** The single biggest improvement available to the app: the install becomes
  "drag to Applications", no Terminal, no "Apple could not verify". Nothing else on this list
  helps as many people.
- **Launch at Login** works on downloaded builds (`SMAppService` needs a real signature).
- **App Groups** work the normal way, so the widget entitlement exception goes away.
- **Remote push** becomes *possible* (see below for why it still shouldn't be built).
- **The App Store** becomes possible.

The App Store is a further step with its own costs, and it is worth separating the two:

- The main app is **not sandboxed** today — only the widget extension is. The store requires
  App Sandbox on. Location, notifications, network, App Groups and opening URLs all work
  under it; the widget cache path and the masjid scraper need re-testing, not rewriting.
- **The update mechanism has to go** in a store build. The store updates the app itself, and a
  build that runs `killall` and `rm -rf` on `/Applications` will not pass review. A build
  flag (`APPSTORE` compilation condition on a second configuration) that turns
  `UpdateStore` into a no-op and hides the Updates section and the popover row is enough.
- **A link to Buy Me a Coffee is a review risk** under guideline 3.1.1. The conventional
  answer is a tip jar through in-app purchase, which is more code and gives Apple a cut. The
  rules on linking out have moved in the last year; check them at submission time rather
  than assuming either way.
- Two channels means two builds per release and two sets of behaviour to keep straight.

**Recommendation:** if the membership is bought, notarize the direct download first and
treat the App Store as a second, later decision. Notarization alone removes the worst part of
the install and changes nothing inside the app. The App Store adds reach at the cost of a
sandbox migration, a second build, and a question mark over the coffee link.

## 1. Push notifications

"Push" here means remote notifications from the author to every install — announcements,
Ramadan greetings, "1.8 is out". Local notifications the app schedules for itself are
already there in six kinds (Adhan, Iqamah, two check-ins, fasting eve, Al-Kahf and the
daily Quran nudge) and don't need anything below.

What remote push costs:

- The paid membership: the `aps-environment` entitlement needs a provisioning profile, which
  an ad-hoc build cannot carry. Not possible on the current distribution at all.
- **A server.** Every install would have to upload its device token somewhere the author
  runs, and something has to store those and talk to APNs. PRIVACY.md currently says
  *"Sajadah has no server of its own. Nothing is sent to the author."* That sentence would
  have to be deleted, and the table gains a row that is a per-device identifier.
- An uninvited notification, by definition — the whole point is that the author decides
  when it fires.

What the app already has that does the same job without any of that: the daily release
check. [`UpdateChecker`](../Sajadah/Services/UpdateChecker.swift) fetches the newest
release's tag, page and **notes** once a day, and the popover shows a row when it's newer.
That *is* a channel from the author to every install — it just requires the message to be a
release. If there's something to say, cut a release and say it in the notes. One channel,
already built, already on the privacy page, and it can never fire without a version bump
behind it.

**Recommendation:** don't build remote push. If the thing being reached for is "tell people
about Ramadan" or "ask for a coffee", both are handled below without it.

## 2. "Update available"

Already shipped, for the direct download:

- [`UpdateStore.checkIfDue`](../Sajadah/Stores/UpdateStore.swift) asks GitHub once a day
  (and on every tick, so a Mac left running for a month still notices).
- The popover shows a brass row — *Version 1.8 is available · Get · ×* — below the day's
  content. Dismissing hides that release only; the next one asks again.
- Settings → General → Updates shows the version, a Check Now button, Copy Update Command
  and Release Notes.

Two gaps, neither urgent:

- **It's only seen when the popover is opened.** Someone who reads the menubar text and never
  clicks won't know. The fix is one local notification per new release, fired once when the
  release is first seen, never repeated. It's a mild version of "uninvited", so if added it
  should default on but sit under Settings → General beside the existing update toggle. The
  cheapest form of "push" there is, and probably what item 1 was really asking for.
- **A store build must not have any of this.** See above: a build flag that empties the
  store and hides the UI, plus a footer that says updates come from the App Store.

## 3. Buy me a coffee

Decided in principle: a row at the bottom of the popover that can be closed once and never
returns, and a permanent button in Settings. The pieces:

**The row.** Same shape as the update row and the fasting invite in the window — one line,
an icon, a link, an ×. Sits between the update row and the footer divider, so it never
displaces the answer the popover exists to give. A single `Bool` in `AppSettings`
(`supportRowDismissed`) following the `fastingInviteDismissed` pattern; the × sets it and
that's the end of it.

**When it first appears.** Not on day one. An app that asks for money before it has been
useful is the drift the worry above is about. Store the first-launch date and show the row
after a fortnight, or after the log has some prayers in it. Two weeks is simplest.

**Settings.** A *Support* section at the bottom of General: one line — *Sajadah is free and
always will be* — and a **Buy Me a Coffee** button. Always there, whatever the row's state.

**One constant for the URL**, the way `UpdateChecker.repository` is the one line a fork
changes. The README's Support section and `.github/FUNDING.yml` both still carry
`YOUR-HANDLE` placeholders; fill all three at once.

**Privacy.** The app makes no request — the button opens the browser. Nothing changes in
PRIVACY.md.

**Wording**, to keep it in the app's register: *"Sajadah is free. If it helps, buy me a
coffee."* Not "support development", not "unlock", nothing that implies anything is held
back.

## 4. Ramadan and the last ten nights

What already exists: `HijriDate.isRamadan`, the day of the month, the Maghrib turnover with
its ±2 day adjustment, suhoor and iftar in the fasting card and the widgets, and "Ramadan
begins tomorrow" the evening before. Ramadan 1448 is expected to begin around **7 February
2027** — sighting will shift it a day — so the last ten nights fall around 26 February to
8 March. Anything for it has to ship by mid-January to be installed before it matters.

**What fits** — all of it is times and dates, the thing the app is for:

- *Night 27 of Ramadan* in the popover hero from the 21st, with the odd nights marked. The
  night of the 21st begins at Maghrib on the 20th, so compute this from the Maghrib-turning
  date regardless of whether the user displays the date changing at midnight — the same rule
  the fasting-eve reminder already follows.
- **The last third of the night.** Maghrib plus two-thirds of the way to the next Fajr —
  both are in the cache already. One more row under suhoor, only during the last ten nights,
  or all of Ramadan for anyone who wants it. This is the one genuinely new number a
  prayer-times app can offer for those nights.
- *Eid tomorrow* the evening the month ends, next to where "Ramadan begins tomorrow" is now.

**What doesn't fit: a donation notification.** During the last ten nights people give
*sadaqah* — charity — and the multiplied reward attached to those nights is for that. A
notification in that window asking for a tip to a developer borrows the moment for
something it isn't, and it is also an uninvited notification, which the test above rules out
on its own. The coffee row is already in the popover every time they open it; that is the
ask, and Ramadan doesn't need a louder one. If a Ramadan touch is wanted at all, the row's
text can change for the month — no notification.

**Recommendation:** build the times if anything — the last third of the night is worth it on
its own — and drop the donation notification.

## 5. ⌘Q should not quit

Decided; it's a bug rather than a feature. When the main window or Settings is open the app
is `.regular`, so it has an app menu, and that menu's standard Quit item terminates the
process — the menubar item goes with it. There is no `.commands` block or app delegate yet.

**Done (1.7.1).** A `CommandGroup(replacing: .appTermination)` in
[`SajadahApp`](../Sajadah/App/SajadahApp.swift): ⌘Q is now *Return to Menu Bar* and closes
the open windows — [`DockVisibility`](../Sajadah/App/DockVisibility.swift) then drops the
Dock icon on its own — with *Quit Sajadah* in the same group under ⌥⌘Q. The popover's Quit
button stays the ordinary way out. Quitting from the Dock, logout and shutdown don't go
through that menu item, so they keep working.

It is a deliberate step away from the platform convention that ⌘Q quits. That's normal for
menubar apps whose window is a visitor rather than the app; the menu item's own title says
what it does, so there is no "still running in the menu bar" notice.

## 6. The fasting line, and the hero's height

Two things the screenshots show, with one cause between them.

**In the popover** the hero's footer asks a single 10.5pt line to hold *place · Hijri date
with year · fasting reason* inside a 300-point panel. It can't, so both the date and the
fasting text truncate — "10 Rabīʿ al…" beside "Fasting da…" — and the two things the user
turned on are the two things they can't read.

Yes, move the fasting text to the top-right, on the kicker row. That row is already the
status row — *Offline* sits there — and in the compact panel the corner is empty lattice.
A brass chip there reads as a state of the day rather than a fourth item in a list, and in
Ramadan it becomes *Iftar 7:18 PM*, which is the number that month asks for, in the most
visible spot in the app. The footer keeps place and date, drops the year in the compact
panel (`HijriDate.dayAndMonth` already exists for that), and both remain the way to the
fasting settings. In the window there's room for the old line, but the chip should move
there too so the two panels don't drift apart.

**In the window** the hero is not designed to be that tall; it is being stretched. The
two-column `HStack` gives both columns the same height, and in the left column the only
flexible child is the hero's gradient background, so it absorbs whatever the streak, fasting
and ayah cards add up to on the right — some 700 points of sky under four lines of text.
The bento is fine; this one cell is sized by its neighbours instead of its content.

Two ways out, from smallest to best:

- **Pin the hero to its content** (`fixedSize` vertically) and move the week table into
  the left column under Today, so that column has enough to stand next to the right one. A
  ragged bottom edge is normal for a bento; an empty cell isn't. An hour's work.
- **Make the hero a banner across the top**, above both columns, at a fixed height —
  headline and countdown on the left, the place / date / fasting block on the right where
  the arch is now. The window bar or the five-prayer timeline the medium widget already
  draws runs through the middle, so the width carries information rather than gradient.
  Then two columns under it: Today and the week on the left, streak, fasting and ayah on
  the right. This fixes the crowded meta line and the stretched hero with one structure,
  and it matches the shape the widgets already have.

**What was done (1.7.1):** the chip, in both panels, and the hero pinned to its content —
but the smaller layout, not the banner. Measured, the banner loses: with the hero in the
left column that column comes to roughly 770 points against the right's 720–970, while as a
full-width banner the left column would sit some 400 points shorter than the right. So the
hero stayed put and the week moved under Today.

That alone left the two columns ending on different lines — a bento with a ragged edge is
not a bento — so each column now has one card that takes the slack: the week table, whose
rows spread to fill, and the verse card. The Day column of the week table also got its
natural width; it had been sharing the card seven ways with the times and "Wed 23 Sep" was
the first thing to truncate. The five-prayer timeline through the hero is still worth doing
later, as the widget already draws one, but it needs the widget's `DayStrip` lifted into
`Shared` first.

## Suggested order

1. ~~⌘Q~~ — done in 1.7.1.
2. ~~The fasting chip and the hero's height~~ — done in 1.7.1.
3. The coffee row and Settings button — small, decided, waiting on the handle.
4. The membership — decide it. If yes, notarize first; the App Store is a separate question.
5. Ramadan — the last-ten-nights times, by mid-January 2027, and nothing that notifies.
6. Push — no. Release notes are the channel.
