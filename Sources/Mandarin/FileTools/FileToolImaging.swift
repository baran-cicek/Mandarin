import CoreGraphics

/// Pixel-level operations for the image File Tools, all plain CoreGraphics
/// (no ImageIO round trip needed until the final write).
public enum FileToolImaging {
    public static func resize(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0 else { throw ConversionError.toolFailed("Width and height must be positive.") }
        guard let context = makeContext(width: width, height: height, colorSpace: image.colorSpace) else {
            throw ConversionError.cannotWriteOutput
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw ConversionError.cannotWriteOutput }
        return result
    }

    public static func crop(_ image: CGImage, x: Int, y: Int, width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0 else { throw ConversionError.toolFailed("Width and height must be positive.") }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(x: x, y: y, width: width, height: height).intersection(bounds)
        guard !rect.isEmpty, let cropped = image.cropping(to: rect) else {
            throw ConversionError.toolFailed("Crop area is outside the image.")
        }
        return cropped
    }

    public static func rotate(_ image: CGImage, degrees: Double) throws -> CGImage {
        let radians = degrees * .pi / 180
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let rotatedBounds = CGRect(x: 0, y: 0, width: width, height: height)
            .applying(CGAffineTransform(rotationAngle: radians))
        let newWidth = max(1, Int(rotatedBounds.width.rounded()))
        let newHeight = max(1, Int(rotatedBounds.height.rounded()))

        guard let context = makeContext(width: newWidth, height: newHeight, colorSpace: image.colorSpace) else {
            throw ConversionError.cannotWriteOutput
        }
        context.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
        context.rotate(by: radians)
        context.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        guard let result = context.makeImage() else { throw ConversionError.cannotWriteOutput }
        return result
    }

    public static func flip(_ image: CGImage, horizontal: Bool) throws -> CGImage {
        guard let context = makeContext(width: image.width, height: image.height, colorSpace: image.colorSpace) else {
            throw ConversionError.cannotWriteOutput
        }
        if horizontal {
            context.translateBy(x: CGFloat(image.width), y: 0)
            context.scaleBy(x: -1, y: 1)
        } else {
            context.translateBy(x: 0, y: CGFloat(image.height))
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else { throw ConversionError.cannotWriteOutput }
        return result
    }

    public static func grayscale(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ConversionError.cannotWriteOutput
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else { throw ConversionError.cannotWriteOutput }
        return result
    }

    private static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace?) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
