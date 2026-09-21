//
//  AppCoordinator+PrayerTimes.swift
//  Sajadah
//

import Foundation

extension AppCoordinator {
    /// How the timings follow what decides them: where the Mac is, how they are calculated,
    /// and the by-hand offsets on top.
    func wirePrayerTimes() {
        location.onCoordinate = { [store] coordinate in
            store.updateCoordinate(coordinate)
        }
        settings.onCalculationChanged = { [store] in
            store.invalidateAndRefresh()
        }
        settings.onAdhanAdjustmentsChanged = { [store, iqamah, settings] in
            store.adhanAdjustmentsChanged()
            // Iqamah computed as minutes after Adhan has to follow the Adhan; a masjid's own
            // posted times don't, so the scrape is left alone.
            if settings.iqamahSourceMode == .offset { iqamah.refresh() }
        }
        settings.onIqamahSourceChanged = { [iqamah] in
            iqamah.refresh()
        }
    }
}
