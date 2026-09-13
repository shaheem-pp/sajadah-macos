//
//  FastingCard.swift
//  Sajadah
//

import SwiftUI

/// The fasts in the fortnight ahead — or, in Ramadan, the day's suhoor and iftar. Sits in the
/// record column under the streak: what the month asks of you, beside what you have done.
///
/// Two weeks rather than a month: with Mondays and Thursdays on, a month is a dozen rows, and
/// a card that tall would push the week table off the bottom of the window to say things the
/// week table's own marks already say.
struct FastingCard: View {
    @Environment(PrayerTimesStore.self) private var store
    @Environment(AppSettings.self) private var settings

    private static let horizonDays = 14

    var body: some View {
        if let ramadan = ramadanDay {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(
                    title: "Fasting",
                    trailing: ramadan.isTomorrow ? "Tomorrow, day \(ramadan.hijri.day) of Ramaḍān" : "Day \(ramadan.hijri.day) of Ramaḍān"
                )

                VStack(spacing: 2) {
                    row(systemImage: "moon.stars", tint: Prayer.fajr.tint, label: "Suhoor ends", value: clock(ramadan.timings.fajr, in: ramadan.timings))
                    row(systemImage: "sunset", tint: Prayer.maghrib.tint, label: "Iftar", value: clock(ramadan.timings.maghrib, in: ramadan.timings))
                }
                .sajadahCard(padding: 8)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Fasting", trailing: "Next 2 weeks")

                VStack(spacing: 2) {
                    let fasts = upcoming
                    if fasts.isEmpty {
                        Text("No fasting days in the next two weeks.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(fasts) { fast in
                        row(
                            systemImage: "fork.knife",
                            tint: Theme.brass,
                            label: dayLabel(for: fast.dayKey),
                            value: Self.reasonText(for: fast),
                            isNear: fast.dayKey == store.todayKey || fast.dayKey == DayKey.next(store.todayKey)
                        )
                    }
                }
                .sajadahCard(padding: 8)
            }
        }
    }

    // MARK: Rows

    private func row(systemImage: String, tint: Color, label: String, value: String, isNear: Bool = false) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.09))
                }

            Text(label)
                .font(.system(size: 13, weight: isNear ? .semibold : .regular))

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Ramadan

    /// The Ramadan fast being shown, with the civil day whose Fajr ends its suhoor and whose
    /// Maghrib is its iftar. After Maghrib that is tomorrow's: the fast just broken has no
    /// numbers left worth having, and the next one's are what suhoor is planned by.
    private var ramadanDay: (hijri: HijriDate, timings: DayTimings, isTomorrow: Bool)? {
        guard let today = store.today else { return nil }
        let todayKey = store.todayKey

        let key: String
        let timings: DayTimings
        let isTomorrow: Bool
        if store.now < today.maghrib {
            (key, timings, isTomorrow) = (todayKey, today, false)
        } else {
            guard let tomorrowKey = DayKey.next(todayKey), let tomorrow = store.days[tomorrowKey] else { return nil }
            (key, timings, isTomorrow) = (tomorrowKey, tomorrow, true)
        }
        guard let hijri = store.hijriDate(for: key), hijri.isRamadan else { return nil }
        return (hijri, timings, isTomorrow)
    }

    private func clock(_ date: Date, in day: DayTimings) -> String {
        TimeFormatting.clock(date, use24Hour: settings.use24HourClock, timeZone: day.timeZone)
    }

    // MARK: Upcoming

    /// The fasts ahead, with Ramadan collapsed to the day it begins — every day of the month
    /// is a fast, and thirty rows saying so would be the list saying nothing.
    private var upcoming: [FastingDayStatus] {
        store.fastingDays(withinDays: Self.horizonDays).filter { fast in
            !fast.reasons.contains(.ramadan) || fast.hijri.day == 1
        }
    }

    /// "Today", "Tomorrow", then the date — the near ones are the ones being decided on.
    private func dayLabel(for dayKey: String) -> String {
        if dayKey == store.todayKey { return "Today" }
        if dayKey == DayKey.next(store.todayKey) { return "Tomorrow" }
        return DayKey.date(dayKey, in: store.displayTimeZone)
            .map { TimeFormatting.weekday($0, timeZone: store.displayTimeZone) } ?? dayKey
    }

    /// "Monday", "Ashura · 10 Muḥarram", "Monday & white days · 14 Rabīʿ al-thānī". The Hijri
    /// date rides along only for the reasons that come from it; a Monday is just a Monday.
    private static func reasonText(for fast: FastingDayStatus) -> String {
        if fast.reasons.contains(.ramadan) {
            return "Ramadan begins · \(fast.hijri.dayAndMonth)"
        }
        var text = fast.reasons.joined
        // `joined` is worded for mid-sentence; a row starts one.
        text = text.prefix(1).uppercased() + text.dropFirst()
        if fast.reasons.contains(where: { !$0.isWeekday }) {
            text += " · \(fast.hijri.dayAndMonth)"
        }
        return text
    }
}
