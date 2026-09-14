//
//  MasjidWidget.swift
//  SajadahWidgets
//

import SwiftUI
import WidgetKit

/// The masjid's own times. Small answers "when is the next jamaah"; medium is the posted
/// table — Adhan beside Iqamah for each prayer, and Jummah — with the next jamaah raised.
struct MasjidWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IqamahTimes", provider: SajadahProvider()) { entry in
            FamilyReader { family in
                MasjidView(entry: entry, family: family)
            }
            .widgetTimeZone(entry.snapshot)
            .containerBackground(for: .widget) { LatticeBackground() }
            .widgetURL(SajadahLink.today)
        }
        .configurationDisplayName("Masjid")
        .description("Your masjid's Iqamah and Jummah times, with the next jamaah highlighted.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MasjidView: View {
    let entry: SajadahEntry
    let family: WidgetFamily

    var body: some View {
        if let times = entry.snapshot.iqamah {
            let next = entry.snapshot.nextJamaah(after: entry.date)
            if family == .systemSmall {
                nextJamaah(next)
            } else {
                table(times, next: next?.event.prayer)
            }
        } else {
            WidgetEmptyView(message: "Set your masjid in Settings to see Iqamah times.")
        }
    }

    // MARK: Small

    private func nextJamaah(_ next: (event: PrayerEvent, iqamah: Date)?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetKicker(title: "Next jamaah")

            Spacer(minLength: 4)

            if let next {
                HStack(spacing: 6) {
                    PrayerGlyph(prayer: next.event.prayer, size: 18, emphasised: true)
                    Text(next.event.prayer.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }

                Text(next.iqamah, style: .time)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)

                HStack(spacing: 4) {
                    Text("in")
                    Countdown(from: entry.date, to: next.iqamah, size: 12, weight: .medium, ink: .onLattice)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else {
                Text("No jamaah ahead in the posted times.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let host = entry.snapshot.iqamahSourceHost {
                Text(host)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Ink.onLattice.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium

    private func table(_ times: IqamahTimes, next: Prayer?) -> some View {
        let day = entry.snapshot.today(at: entry.date)
        let jummah = [times.jummah1, times.jummah2].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 0) {
            WidgetKicker(title: "Masjid", trailing: entry.snapshot.iqamahSourceHost.map(Text.init))

            HStack(spacing: PrayerRow.columnGap) {
                Spacer(minLength: 0)
                Text("ADHAN").frame(width: PrayerRow.columnWidth, alignment: .trailing)
                Text("IQAMAH").frame(width: PrayerRow.columnWidth, alignment: .trailing)
            }
            .font(.system(size: 7.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Ink.onLattice.tertiary)
            .padding(.top, 3)

            VStack(spacing: 0) {
                ForEach(DayLog.tracked, id: \.self) { prayer in
                    if let value = times.time(for: prayer) {
                        let adhan = day?.time(for: prayer)
                        PrayerRow(
                            prayer: prayer,
                            adhan: adhan,
                            iqamah: value,
                            showsIqamahColumn: true,
                            isFocus: prayer == next,
                            hasPassed: adhan.map { $0 <= entry.date } ?? false,
                            prayed: false,
                            height: jummah.isEmpty ? 21.5 : 18.5,
                            fontSize: 11
                        )
                    }
                }

                if !jummah.isEmpty {
                    // No Adhan to pair with, so the times run across both columns.
                    HStack(spacing: 7) {
                        Image(systemName: "building.columns")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(Theme.jade)
                            .frame(width: 15, height: 15)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Theme.jade.opacity(0.10))
                            }
                        Text("Jummah")
                        Spacer(minLength: 4)
                        Text(jummah.joined(separator: "  ·  "))
                            .monospacedDigit()
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(height: 18.5)
                }
            }
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
