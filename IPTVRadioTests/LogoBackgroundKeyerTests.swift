import XCTest
import UIKit
@testable import IPTVRadio

final class LogoBackgroundKeyerTests: XCTestCase {
    func testRemovesUniformWhiteBackground() throws {
        let image = makeImage(size: 40) { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 12, y: 12, width: 16, height: 16))
        }

        let keyed = LogoBackgroundKeyer.keyed(image)
        let corner = try XCTUnwrap(pixel(of: keyed, x: 1, y: 1))
        XCTAssertLessThanOrEqual(corner.alpha, 4, "Uniform white background must become transparent")

        let center = try XCTUnwrap(pixel(of: keyed, x: 20, y: 20))
        XCTAssertGreaterThan(center.alpha, 200, "The logo content itself must stay opaque")
        XCTAssertGreaterThan(center.red, 180, "The logo color must be preserved")
    }

    func testRemovesUniformBlackBackground() throws {
        let image = makeImage(size: 32) { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 10, y: 10, width: 12, height: 12))
        }

        let keyed = LogoBackgroundKeyer.keyed(image)
        let corner = try XCTUnwrap(pixel(of: keyed, x: 1, y: 1))
        XCTAssertLessThanOrEqual(corner.alpha, 4)
    }

    func testKeepsImagesWithoutUniformBackground() throws {
        // Checkerboard border: no dominant background color.
        let image = makeImage(size: 40) { context in
            for x in stride(from: 0, to: 40, by: 4) {
                for y in stride(from: 0, to: 40, by: 4) {
                    if (x + y) % 8 == 0 {
                        UIColor.black.setFill()
                    } else {
                        UIColor.systemGreen.setFill()
                    }
                    context.fill(CGRect(x: x, y: y, width: 4, height: 4))
                }
            }
        }

        let keyed = LogoBackgroundKeyer.keyed(image)
        let corner = try XCTUnwrap(pixel(of: keyed, x: 1, y: 1))
        XCTAssertGreaterThan(corner.alpha, 200, "Non-uniform artwork must be preserved")
    }

    // MARK: Helpers

    private func makeImage(size: CGFloat, draw: (CGContext) -> Void) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            draw(context.cgContext)
        }
    }

    private func pixel(of image: UIImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        guard let cgImage = image.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        guard let context = CGContext(
            data: &data,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let offset = (y * cgImage.width + x) * 4
        guard offset + 3 < data.count else { return nil }
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }
}
