import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

struct IconSize {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String {
        scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png"
    }
}

let outputDirectory = URL(fileURLWithPath: "Resources/PieNS.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let icnsURL = URL(fileURLWithPath: "Resources/PieNS.icns")

let sizes = [
    IconSize(points: 16, scale: 1),
    IconSize(points: 16, scale: 2),
    IconSize(points: 32, scale: 1),
    IconSize(points: 32, scale: 2),
    IconSize(points: 128, scale: 1),
    IconSize(points: 128, scale: 2),
    IconSize(points: 256, scale: 1),
    IconSize(points: 256, scale: 2),
    IconSize(points: 512, scale: 1),
    IconSize(points: 512, scale: 2)
]

var pngsByPixelSize: [Int: Data] = [:]

for size in sizes {
    let width = size.pixels
    let height = size.pixels
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    context.clear(canvas)

    let inset = CGFloat(width) * 0.12
    let rect = canvas.insetBy(dx: inset, dy: inset)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -CGFloat(width) * 0.012),
        blur: CGFloat(width) * 0.025,
        color: CGColor(gray: 0, alpha: 0.16)
    )
    context.setFillColor(CGColor(gray: 0.08, alpha: 1))
    context.fillEllipse(in: rect)
    context.restoreGState()

    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = max(rect.width, rect.height) * 0.58
    context.saveGState()
    context.setBlendMode(.clear)
    context.move(to: center)
    context.addArc(
        center: center,
        radius: radius,
        startAngle: degreesToRadians(25),
        endAngle: degreesToRadians(78),
        clockwise: false
    )
    context.closePath()
    context.fillPath()
    context.restoreGState()

    guard let cgImage = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }

    let url = outputDirectory.appendingPathComponent(size.filename) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }

    pngsByPixelSize[size.pixels] = try Data(contentsOf: outputDirectory.appendingPathComponent(size.filename))
}

try writeICNS(pngsByPixelSize: pngsByPixelSize, to: icnsURL)

private func degreesToRadians(_ degrees: CGFloat) -> CGFloat {
    degrees * .pi / 180
}

private func writeICNS(pngsByPixelSize: [Int: Data], to url: URL) throws {
    let entries: [(type: String, data: Data)] = [
        ("icp4", pngsByPixelSize[16]),
        ("icp5", pngsByPixelSize[32]),
        ("icp6", pngsByPixelSize[64]),
        ("ic07", pngsByPixelSize[128]),
        ("ic08", pngsByPixelSize[256]),
        ("ic09", pngsByPixelSize[512]),
        ("ic10", pngsByPixelSize[1024])
    ].compactMap { type, data in
        guard let data else { return nil }
        return (type, data)
    }

    let totalLength = 8 + entries.reduce(0) { $0 + 8 + $1.data.count }
    var output = Data()
    output.append(ascii: "icns")
    output.appendUInt32BE(UInt32(totalLength))

    for entry in entries {
        output.append(ascii: entry.type)
        output.appendUInt32BE(UInt32(8 + entry.data.count))
        output.append(entry.data)
    }

    try output.write(to: url, options: .atomic)
}

private extension Data {
    mutating func append(ascii string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }
}
