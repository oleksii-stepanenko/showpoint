import AppKit
import SwiftUI

/// Layer-backed view that draws the cursor halo and click ripples. Positioning
/// is done by moving a `CALayer` (cheap, per display-frame) rather than moving a
/// window — that's what makes it track the cursor tightly without lag or
/// clipping. `contentsScale` is set from the owning screen so crisp edges stay
/// sharp on Retina.
final class CursorHostView: NSView {
    /// Backing scale of the screen this view lives on. Drives layer crispness.
    var scale: CGFloat = 2

    private let haloLayer = CALayer()
    private var showHaloAllowed = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        haloLayer.masksToBounds = false
        haloLayer.isHidden = true
        haloLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(haloLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }   // bottom-left origin, matches NSEvent.mouseLocation

    // MARK: Appearance

    func configure(color: NSColor, size: CGFloat, opacity: CGFloat, shape: CursorShape, showHalo: Bool) {
        haloLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        haloLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        haloLayer.contentsScale = scale

        let content = Self.buildHalo(color: color, size: size, opacity: opacity, shape: shape, scale: scale)
        content.frame = haloLayer.bounds
        haloLayer.addSublayer(content)

        showHaloAllowed = showHalo
        if !showHalo { haloLayer.isHidden = true }
    }

    // MARK: Position (called every display-link frame)

    func showHalo(at point: CGPoint) {
        guard showHaloAllowed else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        haloLayer.isHidden = false
        haloLayer.position = point
        CATransaction.commit()
    }

    func hideHalo() {
        guard !haloLayer.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        haloLayer.isHidden = true
        CATransaction.commit()
    }

    // MARK: Click ripple

    func emitRipple(at point: CGPoint, color: NSColor, size: CGFloat) {
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = 3
        ring.position = point
        ring.contentsScale = scale
        ring.opacity = 0
        layer?.addSublayer(ring)

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.5
        grow.toValue = 2.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.85
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { ring.removeFromSuperlayer() }
    }

    // MARK: Halo construction — a soft radial glow plus a crisp ring for definition.

    private static func buildHalo(color: NSColor, size: CGFloat, opacity: CGFloat,
                                  shape: CursorShape, scale: CGFloat) -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        container.contentsScale = scale

        switch shape {
        case .disc:
            let glow = CAGradientLayer()
            glow.type = .radial
            glow.frame = container.bounds
            glow.colors = [
                color.withAlphaComponent(opacity).cgColor,
                color.withAlphaComponent(opacity * 0.5).cgColor,
                color.withAlphaComponent(0).cgColor,
            ]
            glow.locations = [0, 0.5, 1]
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            glow.contentsScale = scale
            container.addSublayer(glow)

            let ring = ringLayer(in: container.bounds.insetBy(dx: size * 0.18, dy: size * 0.18),
                                 color: color.withAlphaComponent(min(1, opacity + 0.5)),
                                 lineWidth: 2, scale: scale)
            container.addSublayer(ring)

        case .ring:
            let ring = ringLayer(in: container.bounds.insetBy(dx: size * 0.14, dy: size * 0.14),
                                 color: color.withAlphaComponent(min(1, opacity + 0.45)),
                                 lineWidth: max(3, size * 0.09), scale: scale)
            ring.shadowColor = color.cgColor
            ring.shadowRadius = size * 0.1
            ring.shadowOpacity = 0.75
            ring.shadowOffset = .zero
            container.addSublayer(ring)

        case .squircle, .rhombus:
            let s = CAShapeLayer()
            let inset = size * 0.08
            let rect = container.bounds.insetBy(dx: inset, dy: inset)
            s.path = shape == .squircle
                ? CGPath(roundedRect: rect, cornerWidth: size * 0.28, cornerHeight: size * 0.28, transform: nil)
                : rhombusPath(in: rect)
            s.fillColor = color.withAlphaComponent(opacity).cgColor
            s.strokeColor = color.withAlphaComponent(min(1, opacity + 0.35)).cgColor
            s.lineWidth = 2
            s.shadowColor = color.cgColor
            s.shadowRadius = size * 0.08
            s.shadowOpacity = 0.5
            s.shadowOffset = .zero
            s.contentsScale = scale
            container.addSublayer(s)
        }

        return container
    }

    private static func ringLayer(in rect: CGRect, color: NSColor, lineWidth: CGFloat, scale: CGFloat) -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: rect, transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = lineWidth
        ring.contentsScale = scale
        return ring
    }

    private static func rhombusPath(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
