//
//  HijriWidget.swift
//  SajadahWidgets
//

import SwiftUI
import WidgetKit

/// The Islamic date as a calendar tile, with what it means for fasting: today's fast, the
/// next one coming, and in Ramadan the count to iftar — the one number that month asks for.
struct HijriWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HijriDate", provider: SajadahProvider()) { entry in
            HijriView(entry: entry)
                .widgetTimeZone(entry.snapshot)
                .containerBackground(for: .widget) { LatticeBackground() }
                .widgetURL(SajadahLink.today)
        }
        .configurationDisplayName("Hijri Date")
        .description("Today's Islamic date, fasting days, and the countdown to iftar in Ramadan.")
        .supportedFamilies([.systemSmall])
    }
}

struct HijriView: View {
    let entry: SajadahEntry

    var body: some View {
        if let hijri = entry.snapshot.displayedHijriDate(at: entry.date) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetKicker(title: hijri.monthName)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: "\(hijri.day)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    // `verbatim`: interpolating an Int into `Text` groups its digits, and
                    // "1,448 AH" is not a year anyone writes.
                    Text(verbatim: "\(hijri.year) AH")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Text(entry.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                fastingLine(hijri)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmptyView(message: "Open Sajadah to load the calendar.")
        }
    }

    /// Today's fast, the count to iftar, or the next fasting day — in brass, since a fast is
    /// the reason to look at this widget. Quiet when fasting days are switched off.
    @ViewBuilder
    private func fastingLine(_ hijri: HijriDate) -> some View {
        let snapshot = entry.snapshot
        if let indicator = snapshot.fastingIndicator(at: entry.date) {
            switch indicator {
            case .iftar(let maghrib):
                VStack(alignment: .leading, spacing: 1) {
                    Text("Iftar")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.brass)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Countdown(from: entry.date, to: maghrib, size: 20, ink: .onLattice)
                        Text(maghrib, style: .time)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            case .fastingToday(let reasons):
                accent("Fasting today", detail: reasons.joined)
            case .fastingTomorrow(let reasons):
                accent("Fasting tomorrow", detail: reasons.joined)
            case .ramadanTomorrow:
                accent("Ramadan begins tomorrow", detail: nil)
            }
        } else if snapshot.fasting.enabled, hijri.isRamadan,
                  let tomorrowKey = DayKey.next(snapshot.dayKey(for: entry.date)),
                  let tomorrow = snapshot.days[tomorrowKey] {
            // A Ramadan night: the date has already turned, and the next thing that matters
            // is when eating stops.
            VStack(alignment: .leading, spacing: 1) {
                accent("Suhoor ends", detail: nil)
                Text(tomorrow.fajr, style: .time)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else if let next = snapshot.nextFastingDay(after: entry.date),
                  let noon = DayKey.date(next.dayKey, in: snapshot.timeZone) {
            VStack(alignment: .leading, spacing: 1) {
                accent("Next fast", detail: nil)
                (Text(noon, format: .dateTime.weekday(.wide).day().month(.abbreviated)) + Text(" · \(next.reasons.joined)"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func accent(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                RubElHizb().fill(Theme.brass.opacity(0.7)).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.brass)
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
    }
}
