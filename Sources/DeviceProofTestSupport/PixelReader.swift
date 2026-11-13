//
//  PixelReader.swift
//  DeviceProofTestSupport
//

#if DEBUG && os(iOS)
import DeviceProofKit
import UIKit

/// sRGB pixels of an image, for sampling and edge scans.
public struct PixelReader: Sendable {
    public let width: Int
    public let height: Int
    private let bytes: [UInt8]

    public init(_ image: UIImage) {
        let cg = image.cgImage!
        // Locals, not `self.width`: the closure below cannot capture `self`
        // before `bytes` is initialised.
        let w = cg.width, h = cg.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        width = w
        height = h
        bytes = buffer
    }

    /// The sRGB colour at (x, y), y down from the top.
    public func color(x: Int, y: Int) -> CalibrationPattern.RGB {
        let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
        let i = (cy * width + cx) * 4
        return CalibrationPattern.RGB(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    private func isBlack(x: Int, y: Int) -> Bool {
        let c = color(x: x, y: y)
        return c.r < 8 && c.g < 8 && c.b < 8
    }

    /// Edges whose outermost rows or columns are solid black for at least
    /// `minimum` pixels (sampled every 4 px), named with their depth.
    public func blackBands(minimum: Int = 4) -> [String] {
        func rowBlack(_ y: Int) -> Bool { stride(from: 0, to: width, by: 4).allSatisfy { isBlack(x: $0, y: y) } }
        func colBlack(_ x: Int) -> Bool { stride(from: 0, to: height, by: 4).allSatisfy { isBlack(x: x, y: $0) } }
        func depth(_ limit: Int, _ test: (Int) -> Bool) -> Int {
            var d = 0
            while d < limit, test(d) { d += 1 }
            return d
        }
        var out: [String] = []
        let top = depth(height) { rowBlack($0) }
        let bottom = depth(height) { rowBlack(height - 1 - $0) }
        let left = depth(width) { colBlack($0) }
        let right = depth(width) { colBlack(width - 1 - $0) }
        if top >= minimum { out.append("top \(top) px") }
        if bottom >= minimum { out.append("bottom \(bottom) px") }
        if left >= minimum { out.append("left \(left) px") }
        if right >= minimum { out.append("right \(right) px") }
        return out
    }
}
#endif
