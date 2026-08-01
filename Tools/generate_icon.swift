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

    drawPieIcon(in: context, size: CGFloat(width))

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

private func drawPieIcon(in context: CGContext, size: CGFloat) {
    let strokeColor = CGColor(gray: 0.08, alpha: 1)
    let lineWidth = max(2, size * 0.052)

    context.setStrokeColor(strokeColor)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    let center = CGPoint(x: size * 0.50, y: size * 0.50)
    let outerRadius = size * 0.36
    let innerRadius = size * 0.26
    let startGap = CGFloat.pi * 0.10
    let endGap = CGFloat.pi * 0.43
    let startPoint = CGPoint(
        x: center.x + cos(startGap) * outerRadius,
        y: center.y + sin(startGap) * outerRadius
    )
    let endPoint = CGPoint(
        x: center.x + cos(endGap) * outerRadius,
        y: center.y + sin(endGap) * outerRadius
    )

    context.addArc(center: center, radius: outerRadius, startAngle: endGap, endAngle: startGap + (.pi * 2), clockwise: false)
    context.strokePath()

    context.setLineWidth(lineWidth * 0.58)
    context.move(to: center)
    context.addLine(to: startPoint)
    context.move(to: center)
    context.addLine(to: endPoint)
    context.strokePath()

    context.addArc(center: center, radius: innerRadius, startAngle: endGap + 0.08, endAngle: startGap + (.pi * 2) - 0.08, clockwise: false)
    context.strokePath()

    if size >= 96 {
        let clipPath = CGMutablePath()
        clipPath.move(to: center)
        clipPath.addArc(center: center, radius: outerRadius - lineWidth, startAngle: endGap, endAngle: startGap + (.pi * 2), clockwise: false)
        clipPath.closeSubpath()

        context.saveGState()
        context.addPath(clipPath)
        context.clip()
        context.setLineWidth(lineWidth * 0.45)

        let latticeLines = [
            (CGPoint(x: size * 0.27, y: size * 0.42), CGPoint(x: size * 0.50, y: size * 0.66)),
            (CGPoint(x: size * 0.35, y: size * 0.31), CGPoint(x: size * 0.68, y: size * 0.64)),
            (CGPoint(x: size * 0.28, y: size * 0.58), CGPoint(x: size * 0.51, y: size * 0.35)),
            (CGPoint(x: size * 0.42, y: size * 0.67), CGPoint(x: size * 0.69, y: size * 0.40))
        ]

        for line in latticeLines {
            context.move(to: line.0)
            context.addLine(to: line.1)
            context.strokePath()
        }

        context.restoreGState()

        context.setLineWidth(lineWidth * 0.34)
        let crimpAngles: [CGFloat] = [1.95, 2.38, 2.82, 3.27, 3.72, 4.18, 4.66, 5.10]
        for angle in crimpAngles {
            context.move(to: CGPoint(
                x: center.x + cos(angle) * (outerRadius - lineWidth * 0.30),
                y: center.y + sin(angle) * (outerRadius - lineWidth * 0.30)
            ))
            context.addLine(to: CGPoint(
                x: center.x + cos(angle) * (outerRadius + lineWidth * 0.30),
                y: center.y + sin(angle) * (outerRadius + lineWidth * 0.30)
            ))
            context.strokePath()
        }
    }
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
