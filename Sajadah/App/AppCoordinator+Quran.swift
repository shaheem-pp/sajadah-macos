//
//  AppCoordinator+Quran.swift
//  Sajadah
//

import Foundation

extension AppCoordinator {
    /// The downloaded text follows the translation setting.
    func wireQuran() {
        settings.onTranslationChanged = { [quran] in
            quran.invalidateTexts()
        }
    }
}
