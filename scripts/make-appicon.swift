// Turns Assets/icon-source.png into Assets/AppIcon.png: a 1024×1024 image laid
// out on the macOS icon grid, with the corners actually transparent.
//
// The source art is a full-bleed square with opaque black corners, which would
// render as a black tile on a light background. Clipping to the rounded square
// fixes that and, at the same time, gives the icon the inset every other macOS
// app icon has.
//
// Run by hand when the artwork changes; the build does not depend on it:
//   swift scripts/make-appicon.swift Assets/icon-source.png Assets/AppIcon.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fail("usage: make-appicon.swift <source.png> <output.png>")
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fail("cannot read \(sourceURL.path)") }

// Apple's grid: on a 1024 canvas the rounded square is 824 wide, corner 185.4.
let canvas: CGFloat = 1024
let square: CGFloat = 824
let cornerRadius: CGFloat = 185.4

guard let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fail("cannot create bitmap context") }

context.interpolationQuality = .high
context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

let inset = (canvas - square) / 2
let frame = CGRect(x: inset, y: inset, width: square, height: square)
context.addPath(CGPath(
    roundedRect: frame,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
))
context.clip()
context.draw(artwork, in: frame)

guard let output = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else { fail("cannot create \(outputURL.path)") }

CGImageDestinationAddImage(destination, output, nil)
guard CGImageDestinationFinalize(destination) else { fail("could not write PNG") }

print("wrote \(outputURL.path) (\(Int(canvas))×\(Int(canvas)))")
