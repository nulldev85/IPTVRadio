import UIKit
import CoreGraphics

/// Removes a uniform background (typically white) from provider channel logos
/// so they render cleanly on a dark/OLED theme.
///
/// The algorithm samples the image border, finds the dominant border color,
/// and — only when the border is convincingly uniform — makes pixels of that
/// color transparent with a soft edge. Images without a uniform background
/// (photos, already-transparent logos) are returned unchanged.
enum LogoBackgroundKeyer {
    static func keyed(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        // Cap processing size: logos are small and this runs once per logo.
        let maxDimension: CGFloat = 512
        let scale = min(1, maxDimension / max(CGFloat(cgImage.width), CGFloat(cgImage.height)))
        let width = max(1, Int(CGFloat(cgImage.width) * scale))
        let height = max(1, Int(CGFloat(cgImage.height) * scale))

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return image }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sample border pixels (two rows, two columns, stepped).
        var samples: [(Int, Int, Int)] = []
        var redSum = 0, greenSum = 0, blueSum = 0

        func sample(_ x: Int, _ y: Int) {
            let offset = (y * width + x) * 4
            let alpha = Int(pixels[offset + 3])
            guard alpha > 40 else { return }
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            samples.append((red, green, blue))
            redSum += red
            greenSum += green
            blueSum += blue
        }

        let stepX = max(1, width / 64)
        let stepY = max(1, height / 64)
        for x in stride(from: 0, to: width, by: stepX) {
            sample(x, 0)
            sample(x, height - 1)
        }
        for y in stride(from: 0, to: height, by: stepY) {
            sample(0, y)
            sample(width - 1, y)
        }
        guard samples.count >= 16 else { return image }

        let count = samples.count
        let redAverage = redSum / count
        let greenAverage = greenSum / count
        let blueAverage = blueSum / count

        func distance(_ red: Int, _ green: Int, _ blue: Int) -> Int {
            abs(red - redAverage) + abs(green - greenAverage) + abs(blue - blueAverage)
        }

        // Only key when the background is convincingly uniform.
        let nearCount = samples.filter { distance($0.0, $0.1, $0.2) <= 60 }.count
        guard Double(nearCount) / Double(count) >= 0.7 else { return image }

        let hardLimit = 45
        let softLimit = 110
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let delta = abs(red - redAverage) + abs(green - greenAverage) + abs(blue - blueAverage)
            if delta <= hardLimit {
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 0
            } else if delta <= softLimit {
                let alpha = UInt8(min(255, 255 * (delta - hardLimit) / (softLimit - hardLimit)))
                if alpha < pixels[index + 3] {
                    // Premultiplied alpha: scale color channels with the new alpha.
                    pixels[index] = UInt8(Int(pixels[index]) * Int(alpha) / 255)
                    pixels[index + 1] = UInt8(Int(pixels[index + 1]) * Int(alpha) / 255)
                    pixels[index + 2] = UInt8(Int(pixels[index + 2]) * Int(alpha) / 255)
                    pixels[index + 3] = alpha
                }
            }
        }

        guard let modified = context.makeImage() else { return image }
        return UIImage(cgImage: modified, scale: image.scale, orientation: image.imageOrientation)
    }
}
