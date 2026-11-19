#!/usr/bin/env swift

import AppKit

private struct TileStyle {
    let color: NSColor
}

private enum Palette {
    static let bodyTop = NSColor(hex: 0x4E6BC0)
    static let bodyBottom = NSColor(hex: 0x1C2342)
    static let tiles: [TileStyle] = [
        TileStyle(color: NSColor(hex: 0xFF7A6E)),
        TileStyle(color: NSColor(hex: 0xFFC154)),
        TileStyle(color: NSColor(hex: 0x5BD6A6)),
        TileStyle(color: NSColor(hex: 0x58B5FF)),
        TileStyle(color: NSColor(hex: 0xB596FF)),
        TileStyle(color: NSColor(hex: 0xFF8DC2)),
        TileStyle(color: NSColor(hex: 0x45CFC6)),
        TileStyle(color: NSColor(hex: 0xFF9E5E)),
        TileStyle(color: NSColor(hex: 0x7F8FFF)),
    ]
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    func lightened(_ amount: CGFloat) -> NSColor {
        blended(withFraction: amount, of: .white) ?? self
    }

    func darkened(_ amount: CGFloat) -> NSColor {
        blended(withFraction: amount, of: .black) ?? self
    }
}

private func drawIcon(in size: CGFloat) {
    let isSmall = size < 64
    let margin = size * 0.098
    let bodySide = size - margin * 2
    let bodyRect = NSRect(x: margin, y: margin, width: bodySide, height: bodySide)
    let bodyRadius = bodySide * 0.2245
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: bodyRadius, yRadius: bodyRadius)

    NSGradient(colors: [Palette.bodyTop, Palette.bodyBottom])?.draw(in: bodyPath, angle: -90)

    let strokeWidth = max(1, bodySide * 0.0022)
    let innerStroke = NSBezierPath(
        roundedRect: bodyRect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2),
        xRadius: bodyRadius - strokeWidth / 2,
        yRadius: bodyRadius - strokeWidth / 2
    )
    NSColor.white.withAlphaComponent(0.16).setStroke()
    innerStroke.lineWidth = strokeWidth
    innerStroke.stroke()

    let tileRatio: CGFloat = isSmall ? 0.29 : 0.214
    let gapRatio: CGFloat = isSmall ? 0.055 : 0.083
    let tileSide = bodySide * tileRatio
    let gap = bodySide * gapRatio
    let gridSide = tileSide * 3 + gap * 2
    let originX = bodyRect.midX - gridSide / 2
    let originY = bodyRect.midY - gridSide / 2
    let tileRadius = tileSide * 0.245
    let tileStroke = max(1, tileSide * 0.012)

    for row in 0..<3 {
        for column in 0..<3 {
            let index = row * 3 + column
            let isCenter = index == 4
            let rect = NSRect(
                x: originX + CGFloat(column) * (tileSide + gap),
                y: originY + CGFloat(2 - row) * (tileSide + gap),
                width: tileSide,
                height: tileSide
            )
            drawTile(
                in: rect,
                radius: tileRadius,
                color: Palette.tiles[index].color,
                strokeWidth: tileStroke,
                elevated: isCenter && !isSmall
            )
        }
    }
}

private func drawTile(
    in rect: NSRect,
    radius: CGFloat,
    color: NSColor,
    strokeWidth: CGFloat,
    elevated: Bool
) {
    NSGraphicsContext.saveGraphicsState()

    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let center = NSPoint(x: rect.midX, y: rect.midY)
    if elevated {
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: -3.5)
        transform.scale(by: 1.07)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
        shadow.shadowBlurRadius = rect.width * 0.16
        shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.07)
        shadow.set()
    }

    NSGradient(colors: [color.lightened(0.10), color.darkened(0.12)])?.draw(in: path, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let topSheen = NSRect(
        x: rect.minX,
        y: rect.maxY - rect.height * 0.46,
        width: rect.width,
        height: rect.height * 0.46
    )
    NSGradient(
        colors: [
            NSColor.white.withAlphaComponent(0.22),
            NSColor.white.withAlphaComponent(0.0),
        ]
    )?.draw(in: topSheen, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    path.lineWidth = strokeWidth
    path.stroke()

    NSGraphicsContext.restoreGraphicsState()
}

private func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.imageInterpolation = .high
    drawIcon(in: CGFloat(size))
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return rep
}

private func writePNG(size: Int, to url: URL) throws {
    let rep = render(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGenerator", code: 1)
    }
    try data.write(to: url)
}

private func writeContentsJSON(to directory: URL) throws {
    let entries: [(String, String, String)] = [
        ("icon_16x16.png", "16x16", "1x"),
        ("icon_16x16@2x.png", "16x16", "2x"),
        ("icon_32x32.png", "32x32", "1x"),
        ("icon_32x32@2x.png", "32x32", "2x"),
        ("icon_128x128.png", "128x128", "1x"),
        ("icon_128x128@2x.png", "128x128", "2x"),
        ("icon_256x256.png", "256x256", "1x"),
        ("icon_256x256@2x.png", "256x256", "2x"),
        ("icon_512x512.png", "512x512", "1x"),
        ("icon_512x512@2x.png", "512x512", "2x"),
    ]

    let images = entries.map { filename, size, scale in
        """
            {
              "filename" : "\(filename)",
              "idiom" : "mac",
              "scale" : "\(scale)",
              "size" : "\(size)"
            }
        """
    }.joined(separator: ",\n")

    let json = """
    {
      "images" : [
    \(images)
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """

    try json.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

private func writeICNS(pngDirectory: URL, to url: URL) throws {
    let entries: [(String, String)] = [
        ("icp4", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
        ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic14", "icon_256x256@2x.png"),
    ]

    var body = Data()
    for (type, filename) in entries {
        let png = try Data(contentsOf: pngDirectory.appendingPathComponent(filename))
        body.append(type.data(using: .ascii)!)
        var length = UInt32(png.count + 8).bigEndian
        body.append(Data(bytes: &length, count: 4))
        body.append(png)
    }

    var icns = Data("icns".utf8)
    var totalLength = UInt32(body.count + 8).bigEndian
    icns.append(Data(bytes: &totalLength, count: 4))
    icns.append(body)

    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try icns.write(to: url)
}

private func writePreview(to url: URL) throws {
    let width: CGFloat = 1280
    let height: CGFloat = 640
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width),
        pixelsHigh: Int(height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .none

    NSColor(hex: 0xEDEDF0).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSColor(hex: 0x1B1B1F).setFill()
    NSRect(x: 0, y: 0, width: width / 2, height: height).fill()

    let sizes: [Int] = [512, 256, 128, 64, 32, 16]
    var x: CGFloat = 16
    for size in sizes {
        let artwork = render(size: size)
        let display = CGFloat(size)
        let y = (height - display) / 2
        if let cgImage = artwork.cgImage {
            NSGraphicsContext.current?.cgContext.draw(
                cgImage,
                in: NSRect(x: x, y: y, width: display, height: display)
            )
        }
        x += display + 40
    }

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGenerator", code: 2)
    }
    try data.write(to: url)
}

do {
    let arguments = CommandLine.arguments
    let outputDirectory: URL
    if let index = arguments.firstIndex(of: "--out"), index + 1 < arguments.count {
        outputDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    } else {
        outputDirectory = URL(
            fileURLWithPath: "Launchpad/Assets.xcassets/AppIcon.appiconset",
            isDirectory: true
        )
    }

    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let iconSizes: [(String, Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for (filename, size) in iconSizes {
        try writePNG(size: size, to: outputDirectory.appendingPathComponent(filename))
    }
    try writeContentsJSON(to: outputDirectory)

    let icnsURL: URL
    if let index = arguments.firstIndex(of: "--icns"), index + 1 < arguments.count {
        icnsURL = URL(fileURLWithPath: arguments[index + 1])
    } else {
        icnsURL = URL(fileURLWithPath: "Launchpad/Resources/AppIcon.icns")
    }
    try writeICNS(pngDirectory: outputDirectory, to: icnsURL)

    if let index = arguments.firstIndex(of: "--preview"), index + 1 < arguments.count {
        try writePreview(to: URL(fileURLWithPath: arguments[index + 1]))
    }

    print("Wrote app icon set to \(outputDirectory.path) and ICNS to \(icnsURL.path)")
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(1)
}
