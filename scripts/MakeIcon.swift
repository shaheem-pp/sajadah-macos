//
//  MakeIcon.swift
//  Sajadah — brand asset generator
//
//  Renders the app icon from the same shapes the app draws with, so the icon can never drift
//  from the UI. Run it after changing anything in Shared/Design/:
//
//      ./scripts/make-icon.sh
//

import AppKit
import SwiftUI

// MARK: - Fixed palette

/// The icon does not use `Theme`'s adaptive colours. A Dock icon is one fixed image — it has
/// no appearance to resolve against — so the jade and brass are pinned to their light-mode
/// values, which are the ones that read against both a light and a dark desktop.
private extension Color {
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    static let iconJadeTop = Color(rgb: 0x12885F)
    static let iconJadeBottom = Color(rgb: 0x043227)
    static let iconBrass = Color(rgb: 0xDFB55F)
}

// MARK: - Artwork

/// How much detail one canvas size can carry.
///
/// These are not a smooth curve, because legibility isn't one. A stroke thinner than about two
/// device pixels stops being a line and becomes a grey smear, so the small tiers widen the arch
/// (leaving interior to see through), thicken the stroke, and drop rings until what's left is
/// unmistakably an arch. Calibrated by rendering each size at nearest-neighbour magnification —
/// proportional scaling alone produced a blob at 16px.
private struct DetailTier {
    let arches: Int
    /// Arch width as a fraction of the icon body.
    let width: CGFloat
    /// Stroke as a fraction of the body, before the absolute floor below.
    let stroke: CGFloat
    /// Spacing between concentric arches, as a fraction of the arch width.
    let gap: CGFloat
    let lattice: Bool
    /// At the smallest size an outline is hopeless — a 2px stroke leaves barely 3px of
    /// interior, and the arch closes up into a blob. A filled silhouette is what Apple's own
    /// 16px artwork falls back to, and it is the only version of this shape that survives.
    var filled: Bool = false

    /// No stroke may fall below this many device pixels, whatever the proportions say.
    static let minimumStroke: CGFloat = 2

    static func forPixels(_ pixels: CGFloat) -> DetailTier {
        switch pixels {
        case ..<32:
            DetailTier(arches: 1, width: 0.52, stroke: 0.075, gap: 0.20, lattice: false, filled: true)
        case ..<128:
            DetailTier(arches: 2, width: 0.56, stroke: 0.048, gap: 0.20, lattice: false)
        case ..<256:
            DetailTier(arches: 3, width: 0.52, stroke: 0.036, gap: 0.155, lattice: false)
        default:
            DetailTier(arches: 3, width: 0.50, stroke: 0.034, gap: 0.145, lattice: true)
        }
    }
}

/// The icon at one pixel size.
private struct IconArtwork: View {
    let pixels: CGFloat

    private var tier: DetailTier { .forPixels(pixels) }

    /// macOS's icon grid: the rounded body occupies 824 of the 1024 canvas, and the margin is
    /// where the system's own shadow and highlight are expected to fall.
    private var bodySide: CGFloat { (pixels * 824 / 1024).rounded() }

    var body: some View {
        let side = bodySide
        let radius = side * 0.2246

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.iconJadeTop, .iconJadeBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if tier.lattice {
                StarLattice(
                    spacing: side * 0.13,
                    color: .white.opacity(0.10),
                    lineWidth: max(0.5, side * 0.0022)
                )
            }

            arches(in: side)
                // A pointed shape carries its mass low, so geometric centring reads as sagging.
                .offset(y: -side * 0.025)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .frame(width: pixels, height: pixels)
    }

    @ViewBuilder
    private func arches(in side: CGFloat) -> some View {
        // MihrabArch needs at least 0.866 x width of height to draw its point; 1.13 leaves a
        // straight springing below the curve rather than bending immediately off the base.
        let width = side * tier.width
        let stroke = max(DetailTier.minimumStroke, side * tier.stroke)
        let gap = width * tier.gap

        ZStack {
            if tier.filled {
                MihrabArch().fill(.white.opacity(0.97))
            } else {
                MihrabArch().strokeBorder(.white.opacity(0.97), lineWidth: stroke)
            }

            if tier.arches >= 2 {
                MihrabArch()
                    .inset(by: gap)
                    .strokeBorder(.white.opacity(0.62), lineWidth: stroke * 0.78)
            }

            if tier.arches >= 3 {
                MihrabArch()
                    .inset(by: gap * 2)
                    .strokeBorder(Color.iconBrass.opacity(0.85), lineWidth: stroke * 0.62)
            }
        }
        .frame(width: width, height: width * 1.13)
    }
}

/// The arch alone on transparency, for the README and anywhere the mark is needed off-icon.
private struct MarkArtwork: View {
    let pixels: CGFloat
    let tint: Color

    var body: some View {
        let width = pixels * 0.62
        ZStack {
            MihrabArch()
                .strokeBorder(tint, lineWidth: pixels * 0.045)
            MihrabArch()
                .inset(by: width * 0.145)
                .strokeBorder(tint.opacity(0.6), lineWidth: pixels * 0.035)
            MihrabArch()
                .inset(by: width * 0.29)
                .strokeBorder(tint.opacity(0.35), lineWidth: pixels * 0.028)
        }
        .frame(width: width, height: width * 1.13)
        .frame(width: pixels, height: pixels)
    }
}

// MARK: - Rendering

@MainActor
private func writePNG(_ view: some View, pixels: CGFloat, to url: URL) throws {
    let renderer = ImageRenderer(content: view.frame(width: pixels, height: pixels))
    renderer.scale = 1
    renderer.isOpaque = false

    guard let cgImage = renderer.cgImage else {
        throw Failure("ImageRenderer produced nothing at \(Int(pixels))px")
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: pixels, height: pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw Failure("PNG encoding failed at \(Int(pixels))px")
    }
    try data.write(to: url)
}

private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Asset catalog

/// One entry in `Contents.json`. macOS wants ten, spanning seven distinct pixel sizes —
/// 32, 128, 256 and 512 each appear twice, as the @2x of one slot and the @1x of the next.
private struct Slot {
    let point: Int
    let scale: Int
    var pixels: Int { point * scale }
    var filename: String { "icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png" }
}

private let slots: [Slot] = [16, 32, 128, 256, 512].flatMap { point in
    [Slot(point: point, scale: 1), Slot(point: point, scale: 2)]
}

@main
enum MakeIcon {
    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let iconSet = root.appending(path: "Sajadah/Assets.xcassets/AppIcon.appiconset")
        let brand = root.appending(path: "docs/brand")

        guard FileManager.default.fileExists(atPath: iconSet.path) else {
            throw Failure("No AppIcon.appiconset at \(iconSet.path) — run from the repo root.")
        }
        try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)

        for slot in slots {
            let px = CGFloat(slot.pixels)
            try writePNG(IconArtwork(pixels: px), pixels: px, to: iconSet.appending(path: slot.filename))
            print("  \(slot.filename)  \(slot.pixels)×\(slot.pixels)")
        }

        let contents: [String: Any] = [
            "images": slots.map { slot in
                [
                    "filename": slot.filename,
                    "idiom": "mac",
                    "scale": "\(slot.scale)x",
                    "size": "\(slot.point)x\(slot.point)",
                ]
            },
            "info": ["author": "xcode", "version": 1],
        ]
        let json = try JSONSerialization.data(
            withJSONObject: contents,
            options: [.prettyPrinted, .sortedKeys]
        )
        try json.write(to: iconSet.appending(path: "Contents.json"))
        print("  Contents.json")

        // README / docs assets.
        try writePNG(IconArtwork(pixels: 1024), pixels: 1024, to: brand.appending(path: "icon.png"))
        try writePNG(MarkArtwork(pixels: 512, tint: Color(rgb: 0x0B6E4F)), pixels: 512,
                     to: brand.appending(path: "mark-light.png"))
        try writePNG(MarkArtwork(pixels: 512, tint: .white), pixels: 512,
                     to: brand.appending(path: "mark-dark.png"))
        print("  docs/brand/{icon,mark-light,mark-dark}.png")
    }
}
