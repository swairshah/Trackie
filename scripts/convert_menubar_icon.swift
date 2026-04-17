#!/usr/bin/env swift
// Converts a full-color menubar icon PNG into a black-and-white template
// suitable for NSImage.isTemplate = true. Preserves alpha; replaces color
// with solid black weighted by luminance so it reads well on both light and
// dark menubars.
//
// Usage: convert_menubar_icon.swift <input.png> <output.png> <size>
import Foundation
import AppKit

guard CommandLine.arguments.count >= 4 else {
    FileHandle.standardError.write("usage: convert_menubar_icon.swift <input> <output> <size>\n".data(using: .utf8)!)
    exit(1)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let size = Int(CommandLine.arguments[3]), size > 0 else {
    FileHandle.standardError.write("invalid size\n".data(using: .utf8)!)
    exit(1)
}

guard let src = NSImage(contentsOf: input),
      let tiff = src.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff)
else {
    FileHandle.standardError.write("could not read \(input.path)\n".data(using: .utf8)!)
    exit(1)
}

// Render source into a square bitmap at target size.
let target = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
)!
target.size = NSSize(width: size, height: size)

let ctx = NSGraphicsContext(bitmapImageRep: target)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high
src.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
         from: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh),
         operation: .copy,
         fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

// Inverted template: treat the BRIGHT card body as the ink, and the
// dark line-art as transparent holes.
//
// The source is line-art — black strokes on a white card fill over a
// transparent background. At menubar sizes the strokes collapse to a
// few pixels and become barely visible as ink. Using the lit interior
// instead gives a solid, legible silhouette with "cut-out" detail lines,
// which reads much better at 18-22pt. macOS's template rendering tints
// the ink white on dark menubars and dark on light menubars.
guard let data = target.bitmapData else { exit(1) }
let bytesPerRow = target.bytesPerRow
let threshold = 0.20  // drop anything too gray (thin strokes, JPEG noise, etc.)
for y in 0..<size {
    for x in 0..<size {
        let i = y * bytesPerRow + x * 4
        let r = Double(data[i]) / 255.0
        let g = Double(data[i + 1]) / 255.0
        let b = Double(data[i + 2]) / 255.0
        let a = Double(data[i + 3]) / 255.0
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        // Keep only the bright, opaque pixels (card body) — anti-aliased
        // by multiplying alpha so edges stay smooth.
        var mask = luma * a
        if mask < threshold { mask = 0 }
        data[i] = 0
        data[i + 1] = 0
        data[i + 2] = 0
        data[i + 3] = UInt8(max(0.0, min(1.0, mask)) * 255.0)
    }
}

guard let pngData = target.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("could not encode png\n".data(using: .utf8)!)
    exit(1)
}

try pngData.write(to: output)
print("wrote \(output.path) (\(size)x\(size))")
