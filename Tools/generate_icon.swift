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
let previewDirectory = URL(fileURLWithPath: "Resources/Previews", isDirectory: true)
try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
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

    drawAppIconBackground(in: context, canvas: canvas)
    drawTrayPie(in: context, canvas: canvas.insetBy(dx: CGFloat(width) * 0.08, dy: CGFloat(width) * 0.14), state: .on, stroke: CGColor(gray: 0, alpha: 1), scale: CGFloat(width) / 32)

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

try writePreview(name: "tray-off-32.png", state: .off)
try writePreview(name: "tray-on-32.png", state: .on)

enum PieState {
    case off
    case on
}

private func drawTrayPie(in context: CGContext, canvas: CGRect, state: PieState, stroke: CGColor, scale: CGFloat) {
    context.setStrokeColor(stroke)
    let lineWidth = max(1.55 * scale, canvas.width * 0.048)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: canvas.minX + (x * canvas.width), y: canvas.minY + (y * canvas.height))
    }

    let top = CGMutablePath()
    top.move(to: p(0.18, 0.43))
    if state == .on {
        top.addCurve(to: p(0.63, 0.26), control1: p(0.26, 0.24), control2: p(0.50, 0.19))
        top.move(to: p(0.73, 0.30))
        top.addCurve(to: p(0.86, 0.45), control1: p(0.81, 0.34), control2: p(0.86, 0.39))
    } else {
        top.addCurve(to: p(0.86, 0.45), control1: p(0.30, 0.16), control2: p(0.76, 0.20))
    }
    top.addCurve(to: p(0.18, 0.43), control1: p(0.78, 0.68), control2: p(0.30, 0.70))
    context.addPath(top)
    context.strokePath()

    let body = CGMutablePath()
    body.move(to: p(0.18, 0.43))
    body.addCurve(to: p(0.30, 0.74), control1: p(0.19, 0.57), control2: p(0.23, 0.68))
    body.addCurve(to: p(0.72, 0.77), control1: p(0.41, 0.87), control2: p(0.61, 0.87))
    body.addCurve(to: p(0.86, 0.45), control1: p(0.81, 0.70), control2: p(0.86, 0.58))
    context.addPath(body)
    context.strokePath()

    if state == .on {
        let cut = CGMutablePath()
        cut.move(to: p(0.63, 0.26))
        cut.addLine(to: p(0.58, 0.53))
        cut.move(to: p(0.73, 0.30))
        cut.addLine(to: p(0.58, 0.53))
        context.addPath(cut)
        context.strokePath()
    }

    context.setLineWidth(lineWidth * 0.72)
    let rim = CGMutablePath()
    rim.move(to: p(0.28, 0.48))
    if state == .on {
        rim.addCurve(to: p(0.56, 0.54), control1: p(0.37, 0.58), control2: p(0.48, 0.60))
        rim.move(to: p(0.68, 0.52))
    }
    rim.addCurve(to: p(0.77, 0.48), control1: p(0.72, 0.54), control2: p(0.75, 0.52))
    context.addPath(rim)
    context.strokePath()

    context.setLineWidth(lineWidth * 0.56)
    let lattice = CGMutablePath()
    lattice.move(to: p(0.35, 0.38))
    lattice.addLine(to: p(0.45, 0.50))
    lattice.move(to: p(0.42, 0.55))
    lattice.addLine(to: p(0.53, 0.42))
    if state == .off {
        lattice.move(to: p(0.58, 0.39))
        lattice.addLine(to: p(0.68, 0.51))
    }
    context.addPath(lattice)
    context.strokePath()

    context.setLineWidth(lineWidth * 0.50)
    let crimp = CGMutablePath()
    crimp.move(to: p(0.29, 0.70))
    crimp.addQuadCurve(to: p(0.39, 0.70), control: p(0.34, 0.78))
    crimp.addQuadCurve(to: p(0.49, 0.70), control: p(0.44, 0.78))
    crimp.addQuadCurve(to: p(0.59, 0.70), control: p(0.54, 0.78))
    crimp.addQuadCurve(to: p(0.69, 0.70), control: p(0.64, 0.78))
    context.addPath(crimp)
    context.strokePath()
}

private func drawAppIconBackground(in context: CGContext, canvas: CGRect) {
    let tile = canvas.insetBy(dx: canvas.width * 0.08, dy: canvas.height * 0.08)
    let radius = canvas.width * 0.20
    let path = CGMutablePath()
    path.addRoundedRect(in: tile, cornerWidth: radius, cornerHeight: radius)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.addPath(path)
    context.fillPath()
}

private func writePreview(name: String, state: PieState) throws {
    let size = 128
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(canvas)
    drawTrayPie(in: context, canvas: canvas.insetBy(dx: 10, dy: 20), state: state, stroke: CGColor(gray: 0, alpha: 1), scale: 4)

    guard let image = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }

    let url = previewDirectory.appendingPathComponent(name) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
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
