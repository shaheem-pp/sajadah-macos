//
//  IqamahOffsetCalculator.swift
//  Sajadah
//
//  The other source of IqamahTimes, alongside IqamahScraper — for masjids with no posted
//  schedule of their own, whose convention instead is a fixed rule ("Iqamah is 15 minutes
//  after Athaan"). Pure arithmetic on Adhan times Sajadah already has; no network involved.
//

import Foundation

enum IqamahOffsetCalculator {
    /// `jummah1`/`jummah2` are left nil — Friday's Iqamah isn't "Dhuhr + N minutes" the way the
    /// other four are, so offset mode doesn't attempt it.
    static func times(
        for day: DayTimings,
        fajr: Int, dhuhr: Int, asr: Int, maghrib: Int, isha: Int,
        use24Hour: Bool
    ) -> IqamahTimes {
        func clock(_ date: Date, plus minutes: Int) -> String {
            TimeFormatting.clock(
                date.addingTimeInterval(TimeInterval(minutes * 60)),
                use24Hour: use24Hour,
                timeZone: day.timeZone
            )
        }

        return IqamahTimes(
            fajr: clock(day.fajr, plus: fajr),
            dhuhr: clock(day.dhuhr, plus: dhuhr),
            asr: clock(day.asr, plus: asr),
            maghrib: clock(day.maghrib, plus: maghrib),
            isha: clock(day.isha, plus: isha)
        )
    }
}
