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
        layer.masksToBounds = true
        layer.allowsEdgeAntialiasing = true
        isAccessibilityElement = true
        accessibilityLabel = "Vinyl record"
        accessibilityIdentifier = "nowplaying.vinyl"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // UIKit can resample a rotating bitmap just outside its transparent
        // edge. Clip the layer itself to a circle at both player sizes.
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    func setSpinning(_ shouldSpin: Bool) {
        guard shouldSpin != spinning else { return }
        if !animationInstalled {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = 2 * Double.pi
            rotation.duration = 5.4
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

        if let artwork {
            drawArtworkDisc(artwork, in: disc, center: center, radius: radius, context: context)
            context.restoreGState()
            drawCenterHub(at: center, radius: radius, context: context)
            return
        }

        let colors = [
            UIColor(white: 0.018, alpha: 1).cgColor,
            UIColor(white: 0.105, alpha: 1).cgColor,
            UIColor(white: 0.045, alpha: 1).cgColor,
            UIColor(white: 0.135, alpha: 1).cgColor,
            UIColor(white: 0.018, alpha: 1).cgColor
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
            UIColor(red: 0.67, green: 0.75, blue: 0.83, alpha: 0.11).cgColor,
            UIColor.clear.cgColor,
            UIColor(white: 1, alpha: 0.045).cgColor,
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

        // Fine grooves fade into the label and lead-in instead of ending in a
        // visible circular seam.
        context.setLineWidth(0.34)
        for index in 0..<150 {
            let ringRadius = radius * (0.54 + CGFloat(index) * 0.00275)
            let variation = CGFloat((index * 37) % 13) / 100
            let tone: CGFloat = index.isMultiple(of: 23) ? 0.30 : 0.16 + variation
            let opacity: CGFloat = index.isMultiple(of: 23) ? 0.37 : 0.25
            let edgeFade = min(1, min(CGFloat(index) / 14, CGFloat(149 - index) / 14))
            context.setStrokeColor(UIColor(white: tone, alpha: opacity * edgeFade).cgColor)
            context.strokeEllipse(in: CGRect(
                x: center.x - ringRadius, y: center.y - ringRadius,
                width: ringRadius * 2, height: ringRadius * 2
            ))
        }

        // A quieter runout and closely spaced lead-in frame the music grooves.
        context.setStrokeColor(UIColor(white: 0.32, alpha: 0.30).cgColor)
        context.setLineWidth(0.65)
        for fraction in [CGFloat(0.52), 0.53, 0.965, 0.98] {
            let ringRadius = radius * fraction
            context.strokeEllipse(in: CGRect(
                x: center.x - ringRadius, y: center.y - ringRadius,
                width: ringRadius * 2, height: ringRadius * 2
            ))
        }
        // A broad off-centre reflection has no angular endpoints, so it
        // blends naturally across every groove as the record turns.
        let softLight = [
            UIColor(red: 0.70, green: 0.76, blue: 0.84, alpha: 0.09).cgColor,
            UIColor(red: 0.70, green: 0.76, blue: 0.84, alpha: 0.025).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: softLight, locations: [0, 0.45, 1]) {
            let lightCenter = CGPoint(x: center.x - radius * 0.45,
                                      y: center.y - radius * 0.52)
            context.drawRadialGradient(
                glow, startCenter: lightCenter, startRadius: 0,
                endCenter: lightCenter, endRadius: radius * 1.65,
                options: []
            )
        }

        context.setStrokeColor(UIColor(white: 0.42, alpha: 0.28).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: disc.insetBy(dx: 1.5, dy: 1.5))
        context.setStrokeColor(UIColor(white: 0, alpha: 0.72).cgColor)
        context.setLineWidth(2.2)
        context.strokeEllipse(in: disc.insetBy(dx: 3.5, dy: 3.5))
        context.restoreGState()

        let labelRadius = radius * 0.48
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
        let labelShading = [
            UIColor(white: 1, alpha: 0.075).cgColor,
            UIColor.clear.cgColor,
            UIColor(white: 0, alpha: 0.19).cgColor
        ] as CFArray
        if let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: labelShading, locations: [0, 0.42, 1]) {
            context.drawLinearGradient(
                shade,
                start: CGPoint(x: label.midX, y: label.minY),
                end: CGPoint(x: label.midX, y: label.maxY),
                options: []
            )
        }
        context.restoreGState()

        context.setStrokeColor(UIColor(white: 0, alpha: 0.8).cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: label.insetBy(dx: -2, dy: -2))
        context.setStrokeColor(UIColor(white: 0.78, alpha: 0.42).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: label)

        let holeRadius = max(3, side * 0.010)
        let hole = CGRect(x: center.x - holeRadius, y: center.y - holeRadius,
                          width: holeRadius * 2, height: holeRadius * 2)
        context.setFillColor(UIColor(white: 0.015, alpha: 1).cgColor)
        context.fillEllipse(in: hole)
        context.setStrokeColor(UIColor(white: 0.88, alpha: 0.74).cgColor)
        context.setLineWidth(1.4)
        context.strokeEllipse(in: hole)
        context.setFillColor(UIColor(white: 1, alpha: 0.52).cgColor)
        context.fillEllipse(in: CGRect(x: hole.minX + 1.5, y: hole.minY + 1.5,
                                       width: 1.5, height: 1.5))
    }

    /// Covers the whole record with the cover image, then adds transparent
    /// grooves and edge shading so the artwork still reads as a vinyl disc.
    private func drawArtworkDisc(
        _ artwork: UIImage,
        in disc: CGRect,
        center: CGPoint,
        radius: CGFloat,
        context: CGContext
    ) {
        let scale = max(disc.width / max(artwork.size.width, 1),
                        disc.height / max(artwork.size.height, 1))
        let imageSize = CGSize(width: artwork.size.width * scale,
                               height: artwork.size.height * scale)
        artwork.draw(in: CGRect(
            x: center.x - imageSize.width / 2, y: center.y - imageSize.height / 2,
            width: imageSize.width, height: imageSize.height
        ))

        // A light tint preserves legibility of bright artwork without hiding
        // the cover's colors, text, or detail.
        context.setFillColor(UIColor(white: 0, alpha: 0.07).cgColor)
        context.fill(disc)

        context.setLineWidth(max(0.25, radius * 0.0011))
        for index in 0..<155 {
            let ringRadius = radius * (0.22 + CGFloat(index) * 0.005)
            let accent = index.isMultiple(of: 17)
            let opacity: CGFloat = accent ? 0.12 : 0.055
            context.setStrokeColor(UIColor(
                white: accent ? 1 : 0, alpha: opacity
            ).cgColor)
            context.strokeEllipse(in: CGRect(
                x: center.x - ringRadius, y: center.y - ringRadius,
                width: ringRadius * 2, height: ringRadius * 2
            ))
        }

        // A low-contrast specular band gives the rotating grooves a satin
        // finish while the original artwork remains readable underneath.
        let reflectionColors = [
            UIColor.clear.cgColor,
            UIColor(white: 1, alpha: 0.025).cgColor,
            UIColor(white: 1, alpha: 0.085).cgColor,
            UIColor(white: 1, alpha: 0.018).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        if let reflection = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: reflectionColors,
                                       locations: [0, 0.24, 0.40, 0.58, 1]) {
            context.drawLinearGradient(
                reflection,
                start: CGPoint(x: disc.minX, y: disc.maxY),
                end: CGPoint(x: disc.maxX, y: disc.minY),
                options: []
            )
        }

        let edgeColors = [
            UIColor.clear.cgColor,
            UIColor(white: 0, alpha: 0.02).cgColor,
            UIColor(white: 0, alpha: 0.25).cgColor
        ] as CFArray
        if let edgeShade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: edgeColors, locations: [0, 0.77, 1]) {
            context.drawRadialGradient(edgeShade, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius, options: [])
        }
        context.setStrokeColor(UIColor(white: 0.9, alpha: 0.32).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: disc.insetBy(dx: 1.5, dy: 1.5))
        context.setStrokeColor(UIColor(white: 0, alpha: 0.5).cgColor)
        context.strokeEllipse(in: disc.insetBy(dx: 3, dy: 3))
    }

    private func drawCenterHub(at center: CGPoint, radius: CGFloat, context: CGContext) {
        let hubRadius = radius * 0.10
        let hub = CGRect(x: center.x - hubRadius, y: center.y - hubRadius,
                         width: hubRadius * 2, height: hubRadius * 2)
        context.setFillColor(UIColor(white: 0.035, alpha: 1).cgColor)
        context.fillEllipse(in: hub)
        context.setStrokeColor(UIColor(white: 0.65, alpha: 0.78).cgColor)
        context.setLineWidth(max(0.3, radius * 0.0045))
        context.strokeEllipse(in: hub.insetBy(dx: radius * 0.011, dy: radius * 0.011))
        context.setStrokeColor(UIColor(white: 0.96, alpha: 0.72).cgColor)
        context.setLineWidth(max(0.2, radius * 0.002))
        context.strokeEllipse(in: hub.insetBy(dx: radius * 0.018, dy: radius * 0.018))

        let spindleRadius = max(0.5, radius * 0.014)
        context.setFillColor(UIColor(white: 0.72, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - spindleRadius, y: center.y - spindleRadius,
                                       width: spindleRadius * 2, height: spindleRadius * 2))
    }
}
