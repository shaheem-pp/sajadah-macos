//
//  ArabicFont.swift
//  Sajadah
//

import SwiftUI

extension Font {
    /// Resolves a stored font choice. An empty name means the system Arabic face, which
    /// SwiftUI picks automatically for Arabic text.
    static func arabic(_ name: String, size: Double) -> Font {
        name.isEmpty ? .system(size: size) : .custom(name, size: size)
    }
}
