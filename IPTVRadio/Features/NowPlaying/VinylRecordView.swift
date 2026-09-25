import SwiftUI
import QuartzCore

/// The disc is rasterized only when its size or label artwork changes. Core
/// Animation rotates the resulting layer at display refresh rate, independent
/// of SwiftUI updates and of the audio player's timing.
struct VinylRecordView: UIViewRepresentable {
    let artwork: UIImage?
    let isSpinning: Bool

    func makeUIView(context: Context) -> VinylDiscView {
        let view = VinylDiscView()
        view.artwork = artwork
        return view
    }

    func updateUIView(_ view: VinylDiscView, context: Context) {
        if view.artwork !== artwork {
            view.artwork = artwork
        }
        view.setSpinning(isSpinning)
    }
}

final class VinylDiscView: UIView {
    var artwork: UIImage? {
        didSet { setNeedsDisplay() }
    }

    private var animationInstalled = false
    private var spinning = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = "Vinyl record"
        accessibilityIdentifier = "nowplaying.vinyl"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSpinning(_ shouldSpin: Bool) {
        guard shouldSpin != spinning else { return }
        if !animationInstalled {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = 2 * Double.pi
            rotation.duration = 1.8 // 33⅓ RPM
            rotation.repeatCount = .infinity
            rotation.isRemovedOnCompletion = false
            layer.add(rotation, forKey: "vinylRotation")
            animationInstalled = true
            layer.speed = 0
            layer.timeOffset = 0
        }

        spinning = shouldSpin
        if shouldSpin {
            let pausedTime = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        } else {
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let side = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = side / 2 - 2
        let disc = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)

        context.saveGState()
        context.addEllipse(in: disc)
        context.clip()

        let colors = [
            UIColor(white: 0.035, alpha: 1).cgColor,
            UIColor(white: 0.17, alpha: 1).cgColor,
            UIColor(white: 0.065, alpha: 1).cgColor,
            UIColor(white: 0.22, alpha: 1).cgColor,
            UIColor(white: 0.025, alpha: 1).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 0.29, 0.55, 0.79, 1]) {
            context.drawRadialGradient(
                gradient, startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius, options: []
            )
        }

        // Reflections are subtle and asymmetrical, so the rotation is visible
        // without turning the record into a bright graphic.
        let reflectedLight = [
            UIColor.clear.cgColor,
            UIColor(white: 1, alpha: 0.075).cgColor,
            UIColor.clear.cgColor,
            UIColor(white: 1, alpha: 0.035).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        if let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: reflectedLight, locations: [0, 0.30, 0.45, 0.72, 1]) {
            context.drawLinearGradient(
                sheen,
                start: CGPoint(x: disc.minX, y: disc.maxY),
                end: CGPoint(x: disc.maxX, y: disc.minY),
                options: []
            )
        }

        // Fine concentric grooves catch just enough light to read as vinyl.
        context.setLineWidth(0.45)
        for index in 0..<108 {
            let ringRadius = radius * (0.45 + CGFloat(index) * 0.0049)
            let lightness: CGFloat = index.isMultiple(of: 8) ? 0.34 : 0.19
            context.setStrokeColor(UIColor(white: lightness, alpha: 0.48).cgColor)
            context.strokeEllipse(in: CGRect(
                x: center.x - ringRadius, y: center.y - ringRadius,
                width: ringRadius * 2, height: ringRadius * 2
            ))
        }

        // The wider runout area and the outer lead-in distinguish a record
        // from a stack of uniformly spaced decorative rings.
        context.setStrokeColor(UIColor(white: 0.36, alpha: 0.42).cgColor)
        for fraction in [CGFloat(0.32), 0.35, 0.38, 0.42, 0.96, 0.98] {
            let ringRadius = radius * fraction
            context.strokeEllipse(in: CGRect(
                x: center.x - ringRadius, y: center.y - ringRadius,
                width: ringRadius * 2, height: ringRadius * 2
            ))
        }
        context.setStrokeColor(UIColor(white: 0.86, alpha: 0.20).cgColor)
        context.setLineWidth(1.2)
        for fraction in [CGFloat(0.62), 0.74, 0.87] {
            context.addArc(center: center, radius: radius * fraction,
                           startAngle: -.pi * 0.72, endAngle: -.pi * 0.18,
                           clockwise: false)
            context.strokePath()
        }

        context.setStrokeColor(UIColor(white: 0.72, alpha: 0.35).cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: disc.insetBy(dx: 2, dy: 2))
        context.restoreGState()

        let labelRadius = radius * 0.235
        let label = CGRect(x: center.x - labelRadius, y: center.y - labelRadius,
                           width: labelRadius * 2, height: labelRadius * 2)
        context.setFillColor(UIColor(white: 0.025, alpha: 1).cgColor)
        context.fillEllipse(in: label.insetBy(dx: -7, dy: -7))

        context.saveGState()
        context.addEllipse(in: label)
        context.clip()
        if let artwork {
            let scale = max(label.width / max(artwork.size.width, 1),
                            label.height / max(artwork.size.height, 1))
            let imageSize = CGSize(width: artwork.size.width * scale,
                                   height: artwork.size.height * scale)
            artwork.draw(in: CGRect(
                x: center.x - imageSize.width / 2, y: center.y - imageSize.height / 2,
                width: imageSize.width, height: imageSize.height
            ))
        } else {
            context.setFillColor(UIColor(AetherTheme.topBlue).cgColor)
            context.fill(label)
        }
        context.restoreGState()

        context.setStrokeColor(UIColor(white: 0.92, alpha: 0.68).cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: label)
        context.setFillColor(UIColor(white: 0.83, alpha: 1).cgColor)
        let holeRadius = max(3, side * 0.013)
        context.fillEllipse(in: CGRect(x: center.x - holeRadius, y: center.y - holeRadius,
                                       width: holeRadius * 2, height: holeRadius * 2))
    }
}
