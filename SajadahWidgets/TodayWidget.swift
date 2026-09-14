//
//  TodayWidget.swift
//  SajadahWidgets
//

import SwiftUI
import WidgetKit

/// The day as a table: every prayer with its Adhan and, where a masjid is set, its Iqamah,
/// the next one raised and the ones already logged ticked. Medium is the five prayers;
/// large puts the hour's hero above them and adds sunrise, Jummah and the fasting line —
/// the whole of the app's Today page in one widget.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrayerTimes", provider: SajadahProvider()) { entry in
            FamilyReader { family in
                TodayView(entry: entry, family: family)
            }
            .widgetTimeZone(entry.snapshot)
            .containerBackground(for: .widget) { LatticeBackground() }
            .widgetURL(SajadahLink.today)
        }
        .configurationDisplayName("Today")
        .description("Every prayer today with its Adhan and Iqamah, the next one highlighted.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayView: View {
    let entry: SajadahEntry
    let family: WidgetFamily

    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        if let day = entry.snapshot.today(at: entry.date) {
            let snapshot = entry.snapshot
            let phase = snapshot.phase(at: entry.date)
            let focus = phase.prayer
            let iqamah = snapshot.iqamah

            VStack(alignment: .leading, spacing: 0) {
                if isLarge, let copy = PhaseCopy(phase: phase, at: entry.date), let prayer = focus {
                    HeroBand(copy: copy, prayer: prayer, from: entry.date)
                        .padding(.bottom, 10)
                }

                WidgetKicker(title: snapshot.placeName ?? "Today", trailing: dateLine)

                if iqamah != nil {
                    // Two columns of times need saying which is which — the old widget left
                    // "5:19 AM  6:15 AM" to be guessed at.
                    HStack(spacing: PrayerRow.columnGap) {
                        Spacer(minLength: 0)
                        Text("ADHAN").frame(width: PrayerRow.columnWidth, alignment: .trailing)
                        Text("IQAMAH").frame(width: PrayerRow.columnWidth, alignment: .trailing)
                    }
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Ink.onLattice.tertiary)
                    .padding(.top, isLarge ? 6 : 3)
                }

                let rows = isLarge ? Prayer.allCases : DayLog.tracked
                VStack(spacing: 0) {
                    ForEach(rows, id: \.self) { prayer in
                        let time = day.time(for: prayer)
                        PrayerRow(
                            prayer: prayer,
                            adhan: time,
                            iqamah: iqamah?.time(for: prayer),
                            showsIqamahColumn: iqamah != nil,
                            isFocus: prayer == focus,
                            hasPassed: time <= entry.date,
                            prayed: snapshot.state(for: prayer, at: entry.date) == .prayed,
                            height: isLarge ? 26 : (iqamah != nil ? 21.5 : 23.5),
                            fontSize: isLarge ? 12 : 11.5
                        )
                    }
                }
                .padding(.top, iqamah != nil ? 1 : 3)

                if isLarge, hasFooter {
                    Spacer(minLength: 4)
                    footer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmptyView(message: "Open Sajadah to load prayer times.")
        }
    }

    /// The Hijri date — with the fasting label ahead of it in the medium widget, which has
    /// nowhere else to put one. The large widget carries fasting in its footer, with the reason.
    private var dateLine: Text {
        let hijri = entry.snapshot.displayedHijriDate(at: entry.date)?.formatted
            ?? entry.snapshot.today(at: entry.date)?.hijri ?? ""
        if !isLarge, let fasting = entry.snapshot.fastingIndicator(at: entry.date) {
            return FastingIndicatorText.text(for: fasting).foregroundStyle(Theme.brass)
                + Text("  ·  \(hijri)")
        }
        return Text(hijri)
    }

    private var hasFooter: Bool {
        let times = entry.snapshot.iqamah
        return times?.jummah1 != nil || times?.jummah2 != nil
            || entry.snapshot.iqamahSourceHost != nil || fastingOutlook != nil
    }

    /// Jummah and the source under the table, and the fasting outlook beneath those.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            OrnamentDivider()
                .padding(.bottom, 2)

            HStack(spacing: 6) {
                if let times = entry.snapshot.iqamah, times.jummah1 != nil || times.jummah2 != nil {
                    Text("Jummah")
                        .foregroundStyle(.secondary)
                    Text([times.jummah1, times.jummah2].compactMap { $0 }.joined(separator: "  ·  "))
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                Spacer(minLength: 6)
                if let host = entry.snapshot.iqamahSourceHost {
                    Text(host)
                        .foregroundStyle(Ink.onLattice.tertiary)
                }
            }
            .font(.system(size: 10.5))
            .lineLimit(1)

            if let outlook = fastingOutlook {
                HStack(spacing: 5) {
                    RubElHizb().fill(Theme.brass.opacity(0.7)).frame(width: 6, height: 6)
                    outlook
                        .foregroundStyle(Theme.brass)
                }
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
            }
        }
    }

    /// What the fasting line under the table says: today's fast if there is one, otherwise the
    /// next one coming. Nil when fasting days are switched off.
    private var fastingOutlook: Text? {
        let snapshot = entry.snapshot
        guard snapshot.fasting.enabled else { return nil }
        if let today = snapshot.fastingIndicator(at: entry.date) {
            switch today {
            case .fastingToday(let reasons): return Text("Fasting today · \(reasons.joined)")
            case .fastingTomorrow(let reasons): return Text("Fasting tomorrow · \(reasons.joined)")
            case .iftar(let maghrib): return Text("Ramadan · Iftar ") + Text(maghrib, style: .time)
            case .ramadanTomorrow: return Text("Ramadan begins tomorrow")
            }
        }
        guard let next = snapshot.nextFastingDay(after: entry.date),
              let noon = DayKey.date(next.dayKey, in: snapshot.timeZone) else { return nil }
        return Text("Next fast · ") + Text(noon, format: .dateTime.weekday(.wide).day().month(.abbreviated))
            + Text(" · \(next.reasons.joined)")
    }
}

// MARK: - Hero band

/// The hour's sky as a strip across the top of the large widget: the same answer the Next
/// Prayer widget gives, in one line, so the table beneath it is read in context.
struct HeroBand: View {
    let copy: PhaseCopy
    let prayer: Prayer
    let from: Date

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                WidgetKicker(title: copy.kicker, ink: .onSky)
                Text(copy.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 0) {
                if let target = copy.target {
                    Countdown(from: from, to: target, size: 24)
                    HStack(spacing: 3) {
                        if let prefix = copy.clockPrefix { Text(prefix) }
                        Text(target, style: .time)
                    }
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Ink.onSky.secondary)
                } else {
                    Text(copy.fallback)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ink.onSky.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.trailing, 46)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background {
            SkyBackground(prayer: prayer, archWidth: 42, archOffset: CGSize(width: 0, height: 10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(copy.isUrgent ? 0.55 : 0.10), lineWidth: copy.isUrgent ? 1.5 : 1)
        }
    }
}

// MARK: - Row

/// One prayer in the table. Past prayers recede so the next one reads at a glance; a prayed
/// one keeps its tick even once it has receded, so the day's record is still there.
struct PrayerRow: View {
    let prayer: Prayer
    /// Nil once the cache has run out of days; the row then shows Iqamah alone.
    let adhan: Date?
    /// The masjid's posted value — a string, not a `Date`, because "Sunset" is a valid one.
    var iqamah: String?
    var showsIqamahColumn: Bool = false
    var isFocus: Bool = false
    var hasPassed: Bool = false
    var prayed: Bool = false
    var height: CGFloat = 20
    var fontSize: CGFloat = 11.5

    static let columnWidth: CGFloat = 54
    static let columnGap: CGFloat = 10

    var body: some View {
        let ink: Color = isFocus ? .primary : (hasPassed ? Ink.onLattice.tertiary : .secondary)

        HStack(spacing: 7) {
            PrayerGlyph(prayer: prayer, size: 15, emphasised: isFocus, faded: hasPassed)

            Text(prayer.displayName)
                .fontWeight(isFocus ? .semibold : .regular)

            if prayed {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.jade)
            }

            Spacer(minLength: 4)

            HStack(spacing: Self.columnGap) {
                Group {
                    if let adhan { Text(adhan, style: .time) } else { Text("") }
                }
                .fontWeight(isFocus ? .semibold : .regular)
                .frame(width: showsIqamahColumn ? Self.columnWidth : nil, alignment: .trailing)

                if showsIqamahColumn {
                    Text(iqamah ?? "")
                        .fontWeight(isFocus ? .semibold : .regular)
                        .foregroundStyle(iqamah == nil ? .clear : ink)
                        .frame(width: Self.columnWidth, alignment: .trailing)
                }
            }
            .monospacedDigit()
        }
        .font(.system(size: fontSize))
        .foregroundStyle(ink)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 5)
        .frame(height: height)
        .background {
            if isFocus {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prayer.tint.opacity(0.13))
            }
        }
    }
}

// MARK: - Fasting label

/// The short form of the fasting label: a widget header has no room for which day it is.
/// The iftar clock goes through `Text(_:style:)` like every other time in the widgets, so it
/// follows the widget's timezone and the user's locale rather than a format string.
enum FastingIndicatorText {
    static func text(for indicator: FastingIndicator) -> Text {
        switch indicator {
        case .fastingToday: Text("Fasting today")
        case .fastingTomorrow: Text("Fasting tomorrow")
        case .iftar(let maghrib): Text("Iftar ") + Text(maghrib, style: .time)
        case .ramadanTomorrow: Text("Ramadan tomorrow")
        }
    }
}
