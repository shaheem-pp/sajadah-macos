//
//  MenuBarLabelRenderer.swift
//  Sajadah
//

import AppKit
import SwiftUI

/// Renders the menubar item to an image.
///
/// `MenuBarExtra` only draws a bare `Text` or `Image` from its label closure — hand it a
/// `Label`, an `HStack`, or any custom view and the text is silently dropped, leaving a lone
/// icon. Rasterising the real layout and passing a single `Image` is the way around that.
///
/// The result is a *template* image, so AppKit paints it with the menubar's own colour: it
/// follows light and dark automatically and inverts correctly when the item is clicked.
@MainActor
enum MenuBarLabelRenderer {

    static func image(for content: MenuBarContent) -> NSImage {
        let renderer = ImageRenderer(content: layout(for: content))
        // Match the screen so the text is crisp rather than upscaled.
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let cgImage = renderer.cgImage else {
            return fallback(for: content)
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: CGFloat(cgImage.width) / renderer.scale,
                height: CGFloat(cgImage.height) / renderer.scale
            )
        )
        image.isTemplate = true
        image.accessibilityDescription = content.combined
        return image
    }

    private static func layout(for content: MenuBarContent) -> some View {
        HStack(spacing: 5) {
            Image(systemName: content.icon)
                .font(.system(size: 12, weight: .medium))

            Text(content.prayer)
                .font(.system(size: 12.5, weight: .medium))

            if !content.countdown.isEmpty {
                Text(content.countdown)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background {
                        Capsule().stroke(lineWidth: 1).opacity(0.55)
                    }
            }
        }
        // Without this the renderer truncates to an ellipsis ("1h 5…") instead of growing.
        .lineLimit(1)
        .fixedSize()
        // Only the alpha channel survives into a template image, so this just needs to be
        // fully opaque — the actual colour is irrelevant.
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
        .padding(.horizontal, 1)
        .padding(.vertical, 1)
    }

    private static func fallback(for content: MenuBarContent) -> NSImage {
        NSImage(systemSymbolName: content.icon, accessibilityDescription: content.combined)
            ?? NSImage(systemSymbolName: "moon.stars", accessibilityDescription: content.combined)
            ?? NSImage()
    }
}
