//
//  SajadahWidgets.swift
//  SajadahWidgets
//
//  On macOS 14+ desktop widgets and Notification Center widgets are the same WidgetKit
//  widget — the system decides placement — so one bundle serves both.
//
//  Six widgets, each answering one question: how long until the next prayer (Next Prayer),
//  what today looks like (Today), what has been prayed (Prayer Log), when the masjid prays
//  (Masjid), what the date is and whether it is a fast (Hijri Date), and a verse (Ayah).
//

import SwiftUI
import WidgetKit

@main
struct SajadahWidgetBundle: WidgetBundle {
    init() {
        // The ayah widget renders Uthmani text, and the extension has its own bundle, so it
        // must register the font itself rather than relying on the app having done it.
        BundledFonts.registerAll()
    }

    var body: some Widget {
        NextPrayerWidget()
        TodayWidget()
        PrayerLogWidget()
        MasjidWidget()
        HijriWidget()
        AyahWidget()
    }
}

extension View {
    /// Times are shown in the zone the timings were calculated for, not the Mac's — the rule
    /// the app already applies — so a widget and the popover can't disagree on a trip.
    func widgetTimeZone(_ snapshot: SajadahSnapshot) -> some View {
        environment(\.timeZone, snapshot.timeZone)
    }
}
