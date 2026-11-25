import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

protocol AppIconDiskCache: Sendable {
    func cacheKey(for launchURL: URL, pixelSize: Int) -> String
    func loadImage(forKey key: String) -> CGImage?
    func saveImage(_ image: CGImage, forKey key: String)
    func removeImage(forKey key: String)
    func prune(keeping validKeys: Set<String>)
}

struct FileAppIconDiskCache: AppIconDiskCache {
    let directory: URL

    init(directory: URL = FileAppIconDiskCache.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)

        return caches
            .appendingPathComponent("com.supremacysakura.launchpad", isDirectory: true)
            .appendingPathComponent("icons-v1", isDirectory: true)
    }

    func cacheKey(for launchURL: URL, pixelSize: Int) -> String {
        let standardizedURL = launchURL.standardizedFileURL
        let infoPlistURL = standardizedURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)

        let mtime = modificationTimestampMillis(for: infoPlistURL)
            ?? modificationTimestampMillis(for: standardizedURL)
            ?? 0

        let rawKey = "\(standardizedURL.path)|\(pixelSize)|\(mtime)"
        let digest = SHA256.hash(data: Data(rawKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func loadImage(forKey key: String) -> CGImage? {
        let url = fileURL(forKey: key)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, imageOptions as CFDictionary)
    }

    func saveImage(_ image: CGImage, forKey key: String) {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return
        }

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? (data as Data).write(to: fileURL(forKey: key), options: .atomic)
    }

    func removeImage(forKey key: String) {
        try? FileManager.default.removeItem(at: fileURL(forKey: key))
    }

    func prune(keeping validKeys: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents where url.pathExtension == "png" {
            let key = url.deletingPathExtension().lastPathComponent
            if !validKeys.contains(key) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).png", isDirectory: false)
    }

    private func modificationTimestampMillis(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate else {
            return nil
        }
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

enum AppIconRasterizer {
    static func rasterize(_ image: NSImage, pixelSize: Int) -> CGImage? {
        guard pixelSize > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high

        let canvasSize = CGFloat(pixelSize)
        var proposedRect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
            let drawRect = aspectFitRect(for: sourceSize, in: canvasSize)
            context.draw(cgImage, in: drawRect)
            return context.makeImage()
        }

        let drawRect = aspectFitRect(for: image.size, in: canvasSize)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }

    private static func aspectFitRect(for size: CGSize, in canvasSize: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        }

        let scale = min(canvasSize / size.width, canvasSize / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(
            x: (canvasSize - width) / 2,
            y: (canvasSize - height) / 2,
            width: width,
            height: height
        )
    }
}
