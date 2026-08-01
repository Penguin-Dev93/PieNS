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
let trayOffURL = URL(fileURLWithPath: "Resources/TrayIconOff.png")
let trayOnURL = URL(fileURLWithPath: "Resources/TrayIconOn.png")
let trayOffImage = try loadCGImage(from: trayOffURL)
let trayOnImage = try loadCGImage(from: trayOnURL)

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
    drawImage(trayOnImage, in: context, canvas: canvas)

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

try writePreview(name: "tray-off-32.png", image: trayOffImage)
try writePreview(name: "tray-on-32.png", image: trayOnImage)

private func loadCGImage(from url: URL) throws -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw CocoaError(.fileReadCorruptFile)
    }

    return image
}

private func drawImage(_ image: CGImage, in context: CGContext, canvas: CGRect) {
    context.interpolationQuality = .high
    context.draw(image, in: canvas)
}

private func drawAppIconBackground(in context: CGContext, canvas: CGRect) {
    let tile = canvas.insetBy(dx: canvas.width * 0.08, dy: canvas.height * 0.08)
    let radius = canvas.width * 0.20
    let path = CGMutablePath()
    path.addRoundedRect(in: tile, cornerWidth: radius, cornerHeight: radius)
    context.setFillColor(CGColor(gray: 0.02, alpha: 1))
    context.addPath(path)
    context.fillPath()
}

private func writePreview(name: String, image: CGImage) throws {
    let size = 32
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
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(canvas)
    drawImage(image, in: context, canvas: canvas)

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
