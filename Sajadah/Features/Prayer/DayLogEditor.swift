//
//  DayLogEditor.swift
//  Sajadah
//

import SwiftUI

/// The popover behind a square in the streak grid: one day's five prayers, each with the same
/// circle the list uses, and a way to log the whole day at once.
///
/// This exists for the person who prays every day and doesn't log every prayer. Asking them to
/// tap five circles on each of the days they skipped is the reason they skipped; one click per
/// day is a chore they will actually do.
struct DayLogEditor: View {
    let dayKey: String
    /// "Tue 9 Sep" — the key itself is for sorting, not reading.
    let title: String
    /// Past days can log all five. Today can only log a prayer whose time has come, the same
    /// rule the list applies — a day can't be finished before it happens.
    let loggable: Set<Prayer>

    @Environment(PrayerLogStore.self) private var log

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            VStack(spacing: 6) {
                ForEach(DayLog.tracked) { prayer in
                    HStack(spacing: 9) {
                        Image(systemName: prayer.systemImage)
                            .font(.system(size: 11))
                            .foregroundStyle(prayer.tint)
                            .frame(width: 16)

                        Text(prayer.displayName)
                            .font(.system(size: 12))

                        Spacer(minLength: 16)

                        LogButton(
                            state: log.state(for: prayer, on: dayKey),
                            isEnabled: loggable.contains(prayer),
                            action: { log.cycle(prayer, on: dayKey) }
                        )
                    }
                }
            }

            Divider()

            Button("Mark all prayed") {
                log.set(.prayed, for: loggable, on: dayKey)
            }
            .controlSize(.small)
            .disabled(allPrayed)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .frame(width: 210)
    }

    private var allPrayed: Bool {
        loggable.allSatisfy { log.state(for: $0, on: dayKey) == .prayed }
    }
}
