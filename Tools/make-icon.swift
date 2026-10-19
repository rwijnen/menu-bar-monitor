// Draws the app icon as a full .iconset with Core Graphics only, so it builds on a
// machine that has the Command Line Tools but no Xcode.
//
// The mark: three sparklines on a dark tile, one per metric, in the same colours the
// app uses for them — CPU violet, memory green, network coral. Below 64 pixels the
// lines turn to mush, so small sizes draw three level bars instead.
//
// Usage: swift Tools/make-icon.swift <output.iconset directory>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let colorSpace = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

// MARK: - Palette

let tileTop = color(0x2B2565)
let tileBottom = color(0x0E0C1F)
let tileEdge = color(0xFFFFFF, 0.10)
let cpuColor = color(0x9D95F0)       // a step lighter than the app's 7F77DD, for the dark tile
let memoryColor = color(0x2BC79A)
let networkColor = color(0xF07A4E)

// Readings, 0 to 1, chosen to look like each metric: CPU busy and uneven, memory
// slow and steady, network quiet with bursts.
let cpuSeries: [CGFloat] = [0.35, 0.55, 0.40, 0.72, 0.50, 0.82, 0.58, 0.76, 0.46, 0.62]
let memorySeries: [CGFloat] = [0.42, 0.45, 0.47, 0.46, 0.52, 0.55, 0.57, 0.56, 0.60, 0.63]
let networkSeries: [CGFloat] = [0.15, 0.25, 0.18, 0.85, 0.35, 0.22, 0.95, 0.45, 0.28, 0.60]

// MARK: - Drawing

/// Apple's icon grid: the tile is 824 of 1024 points, with a 185-point corner.
func tileRect(_ size: CGFloat) -> CGRect {
    let inset = size * 100 / 1024
    return CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
}

func drawTile(_ context: CGContext, size: CGFloat) {
    let rect = tileRect(size)
    let radius = rect.width * 185 / 824
    let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                      transform: nil)

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [tileTop, tileBottom] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.maxY),
                               end: CGPoint(x: 0, y: rect.minY), options: [])
    context.restoreGState()

    context.addPath(tile)
    context.setStrokeColor(tileEdge)
    context.setLineWidth(max(1, size / 512))
    context.strokePath()
}

/// One metric's lane: the line, and a fill under it that fades towards the
/// lane's floor.
func drawSparkline(_ context: CGContext, series: [CGFloat], lane: CGRect, color: CGColor,
                   lineWidth: CGFloat) {
    let step = lane.width / CGFloat(series.count - 1)
    let points = series.enumerated().map { index, value in
        CGPoint(x: lane.minX + CGFloat(index) * step, y: lane.minY + value * lane.height)
    }

    let line = CGMutablePath()
    line.addLines(between: points)

    let area = line.mutableCopy()!
    area.addLine(to: CGPoint(x: lane.maxX, y: lane.minY))
    area.addLine(to: CGPoint(x: lane.minX, y: lane.minY))
    area.closeSubpath()

    context.saveGState()
    context.addPath(area)
    context.clip()
    let fill = CGGradient(colorsSpace: colorSpace,
                          colors: [color.copy(alpha: 0.45)!, color.copy(alpha: 0)!] as CFArray,
                          locations: [0, 1])!
    context.drawLinearGradient(fill, start: CGPoint(x: 0, y: lane.maxY),
                               end: CGPoint(x: 0, y: lane.minY), options: [])
    context.restoreGState()

    context.addPath(line)
    context.setStrokeColor(color)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

func drawDetailed(_ context: CGContext, size: CGFloat) {
    let tile = tileRect(size)
    let margin = tile.width * 0.14
    let content = tile.insetBy(dx: margin, dy: margin)
    let gap = content.height * 0.08
    let laneHeight = (content.height - gap * 2) / 3
    let lineWidth = tile.width * 0.032

    let lanes = [(cpuSeries, cpuColor), (memorySeries, memoryColor), (networkSeries, networkColor)]
    for (index, (series, color)) in lanes.enumerated() {
        // Core Graphics counts up from the bottom; the first lane goes at the top.
        let y = content.maxY - CGFloat(index + 1) * laneHeight - CGFloat(index) * gap
        let lane = CGRect(x: content.minX, y: y, width: content.width, height: laneHeight)
        drawSparkline(context, series: series, lane: lane, color: color, lineWidth: lineWidth)
    }
}

func drawSimple(_ context: CGContext, size: CGFloat) {
    let tile = tileRect(size)
    let barWidth = tile.width * 0.17
    let gap = tile.width * 0.09
    let floor = tile.minY + tile.height * 0.2
    let tallest = tile.height * 0.6
    let left = tile.midX - (barWidth * 3 + gap * 2) / 2

    for (index, (level, color)) in [(0.62, cpuColor), (0.85, memoryColor), (0.42, networkColor)]
        .enumerated() {
        let bar = CGRect(x: left + CGFloat(index) * (barWidth + gap), y: floor,
                         width: barWidth, height: tallest * level)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 3,
                               cornerHeight: barWidth / 3, transform: nil))
        context.setFillColor(color)
        context.fillPath()
    }
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let size = CGFloat(pixels)
    drawTile(context, size: size)
    if pixels >= 64 {
        drawDetailed(context, size: size)
    } else {
        drawSimple(context, size: size)
    }
    return context.makeImage()!
}

// MARK: - Output

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let url = outputDirectory.appendingPathComponent("\(variant.name).png")
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
    CGImageDestinationAddImage(destination, render(pixels: variant.pixels), nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
}
print("Wrote \(variants.count) images to \(outputDirectory.path)")
