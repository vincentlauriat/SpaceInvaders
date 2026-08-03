import SpriteKit

/// Retro palette — white sprites with gel-overlay tints, like the 1978 cabinet.
enum Palette {
    static let white = NSColor(red: 0.95, green: 0.98, blue: 0.95, alpha: 1)
    static let green = NSColor(red: 0.24, green: 1.0, blue: 0.43, alpha: 1)
    static let red = NSColor(red: 1.0, green: 0.28, blue: 0.24, alpha: 1)
    static let amber = NSColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 1)
}

enum Pixel {
    /// Turn a '#'/'.' pattern into a crisp nearest-neighbor texture.
    static func texture(_ pattern: [String], color: NSColor) -> SKTexture {
        let h = pattern.count
        let w = pattern[0].count
        let c = color.usingColorSpace(.deviceRGB) ?? color
        let r = UInt8(c.redComponent * 255)
        let g = UInt8(c.greenComponent * 255)
        let b = UInt8(c.blueComponent * 255)

        var data = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in pattern.enumerated() {
            for (x, ch) in Array(row).enumerated() where ch == "#" {
                let i = (y * w + x) * 4
                data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = 255
            }
        }
        return textureFromRGBA(&data, width: w, height: h)
    }

    static func sprite(_ pattern: [String], color: NSColor) -> SKSpriteNode {
        let tex = texture(pattern, color: color)
        let node = SKSpriteNode(texture: tex)
        node.size = CGSize(width: pattern[0].count, height: pattern.count)
        return node
    }

    /// Full-scene scanline overlay: darken every other logical pixel row.
    static func scanlines(size: CGSize, alpha: UInt8 = 46) -> SKSpriteNode {
        let w = Int(size.width), h = Int(size.height)
        var data = [UInt8](repeating: 0, count: w * h * 4)
        for y in stride(from: 0, to: h, by: 2) {
            for x in 0..<w {
                let i = (y * w + x) * 4
                data[i + 3] = alpha  // premultiplied black
            }
        }
        let node = SKSpriteNode(texture: textureFromRGBA(&data, width: w, height: h))
        node.size = size
        node.anchorPoint = .zero
        node.zPosition = 1000
        return node
    }

    static func textureFromRGBA(_ data: inout [UInt8], width: Int, height: Int) -> SKTexture {
        let ctx = data.withUnsafeMutableBytes { ptr in
            CGContext(data: ptr.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let image = ctx?.makeImage() else { fatalError("texture creation failed") }
        let tex = SKTexture(cgImage: image)
        tex.filteringMode = .nearest
        return tex
    }
}
