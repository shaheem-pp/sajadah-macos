//
//  BundledFonts.swift
//  Sajadah
//

import AppKit
import CoreText

/// Registers the Quran typeface the app ships with.
///
/// macOS's own Arabic faces — Geeza Pro, SF Arabic, Al Bayan — are UI fonts. They render plain
/// Arabic well but mishandle Uthmani orthography: waqf marks float away from the word, the
/// small high rounded zero degrades to a sukun, the small low meem is dropped, and the ayah
/// marker leaves its numeral outside the rosette instead of nested inside it. Amiri Quran is
/// built for typesetting the Quran and gets all of that right.
///
/// Registered into the process rather than installed system-wide, so nothing is added to the
/// user's Font Book.
nonisolated enum BundledFonts {
    /// The family name the font exposes — not the filename.
    static let amiriQuran = "Amiri Quran"

    static func registerAll() {
        guard let url = Bundle.main.url(forResource: "AmiriQuran", withExtension: "ttf") else {
            assertionFailure("AmiriQuran.ttf missing from the app bundle")
            return
        }
        var error: Unmanaged<CFError>?
        // A false return usually just means it is already registered; the font check below is
        // what actually decides whether it can be offered.
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }

    /// Whether a font name resolves. Used to keep the picker honest — an unavailable font
    /// would silently fall back to the system face and look like a bug.
    static func isAvailable(_ name: String) -> Bool {
        name.isEmpty || NSFont(name: name, size: 12) != nil
    }
}
