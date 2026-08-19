//
//  IslamicOrnaments.swift
//  Sajadah
//

import SwiftUI

// MARK: - Rub el Hizb

/// The eight-pointed star (۞) that marks each eighth of the Quran.
///
/// Drawn as the union of two squares at 45° to each other, which is what the mark actually
/// is. The inner radius is not a free parameter: where the two squares cross sits at
/// `cos(45°) / cos(22.5°)` ≈ 0.765 of the outer radius, and any other value stops being a
/// khatim and starts being a generic star.
struct RubElHizb: Shape {
    /// 0 collapses to an octagon, 1 to a spike. The default is the true crossing point.
    var sharpness: CGFloat = 0.765

    nonisolated func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * sharpness

        var path = Path()
        for step in 0..<16 {
            let radius = step.isMultiple(of: 2) ? outer : inner
            // Start at -90° so a point sits at the top rather than the side.
            let angle = Angle(degrees: Double(step) * 22.5 - 90).radians
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Mihrab arch

/// The pointed arch of a mihrab — the niche marking the qibla.
///
/// Built the way the arch itself is: two circular arcs, each centred on the *opposite*
/// springing point, so they arrive at the apex at an angle to one another and leave a real
/// point there. Meeting them tangentially instead — the obvious quad-curve version — just
/// produces a rounded rectangle, which is the one thing this shape must not look like.
struct MihrabArch: Shape {
    /// How far the apex sits above the springing, as a fraction of the span. √3/2 is the
    /// equilateral arch, where each arc's radius equals the full span. Values below 0.5 have
    /// no pointed arch to describe — at 0.5 the two centres meet and it is a semicircle — so
    /// the shape needs a frame at least `0.866 × width` tall to draw itself properly.
    var rise: CGFloat = 0.866

    nonisolated func path(in rect: CGRect) -> Path {
        let span = rect.width
        let lift = min(span * rise, rect.height)
        let spring = rect.minY + lift
        let apex = CGPoint(x: rect.midX, y: rect.minY)
        // 4/3·tan(θ/4) for θ = 60°: the cubic that matches a sixth-circle to within a
        // fraction of a pixel at these sizes.
        let handle = 0.3573 * span

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: spring))
        path.addCurve(
            to: apex,
            control1: CGPoint(x: rect.minX, y: spring - handle),
            control2: CGPoint(x: rect.midX - handle * 0.866, y: rect.minY + handle * 0.5)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: spring),
            control1: CGPoint(x: rect.midX + handle * 0.866, y: rect.minY + handle * 0.5),
            control2: CGPoint(x: rect.maxX, y: spring - handle)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Lattice

/// A khatim tessellation: eight-pointed stars on a square grid with smaller squares turned
/// 45° in the gaps between them — the simplest of the girih patterns, and the one that tiles
/// cleanly at any size.
///
/// Kept to a hairline at very low opacity. It should be the thing you notice second.
struct StarLattice: View {
    var spacing: CGFloat = 46
    var color: Color = Theme.ornament
    var lineWidth: CGFloat = 0.9

    var body: some View {
        Canvas { context, size in
            let star = spacing * 0.34
            let square = spacing * 0.12

            var y = -spacing
            while y <= size.height + spacing {
                var x = -spacing
                while x <= size.width + spacing {
                    context.stroke(
                        RubElHizb().path(in: CGRect(
                            x: x - star, y: y - star,
                            width: star * 2, height: star * 2
                        )),
                        with: .color(color),
                        lineWidth: lineWidth
                    )

                    // The interstitial square, rotated to meet the four stars around it.
                    let gap = CGPoint(x: x + spacing / 2, y: y + spacing / 2)
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: gap.x, y: gap.y - square))
                    diamond.addLine(to: CGPoint(x: gap.x + square, y: gap.y))
                    diamond.addLine(to: CGPoint(x: gap.x, y: gap.y + square))
                    diamond.addLine(to: CGPoint(x: gap.x - square, y: gap.y))
                    diamond.closeSubpath()
                    context.stroke(diamond, with: .color(color), lineWidth: lineWidth)

                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Divider

/// A rule that thins out towards its ends and carries a star at the centre, in place of a
/// hard edge-to-edge line. Used where a plain `Divider` would feel abrupt — around the
/// basmala, under a surah title.
struct OrnamentDivider: View {
    var tint: Color = Theme.jade

    var body: some View {
        HStack(spacing: 8) {
            taperedRule(fading: .leading)

            RubElHizb()
                .fill(tint.opacity(0.55))
                .frame(width: 9, height: 9)

            taperedRule(fading: .trailing)
        }
        .frame(height: 9)
    }

    private func taperedRule(fading edge: HorizontalEdge) -> some View {
        let stops: [Color] = [tint.opacity(0), tint.opacity(0.35)]
        return LinearGradient(
            colors: edge == .leading ? stops : stops.reversed(),
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}

// MARK: - Ayah marker

/// The ayah number in its rosette, the way a printed mushaf sets it.
struct AyahRosette: View {
    let number: Int
    var size: CGFloat = 26
    var tint: Color = Theme.jade

    var body: some View {
        ZStack {
            RubElHizb()
                .fill(tint.opacity(0.10))
            RubElHizb()
                .stroke(tint.opacity(0.40), lineWidth: 0.9)
            Text("\(number)")
                .font(.system(size: size * 0.36, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Ayah \(number)")
    }
}

/// `Shape.inset(by:)` needs an `InsettableShape`. The arch is derived entirely from its
/// rect, so insetting it is just insetting that rect — which lets a second, tighter arch be
/// stroked inside the first without hand-computing the offset.
extension MihrabArch: InsettableShape {
    nonisolated func inset(by amount: CGFloat) -> some InsettableShape {
        InsetMihrabArch(base: self, inset: amount)
    }
}

private struct InsetMihrabArch: InsettableShape {
    let base: MihrabArch
    var inset: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        base.path(in: rect.insetBy(dx: inset, dy: inset))
    }

    nonisolated func inset(by amount: CGFloat) -> InsetMihrabArch {
        InsetMihrabArch(base: base, inset: inset + amount)
    }
}
