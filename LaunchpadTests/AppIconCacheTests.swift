import AppKit
import XCTest

final class AppIconCacheTests: XCTestCase {
    private var fixtureDirectory: URL!

    override func setUpWithError() throws {
        fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    func testDiskCacheRoundTripsCGImage() throws {
        let cacheDirectory = fixtureDirectory.appendingPathComponent("icons", isDirectory: true)
        let cache = FileAppIconDiskCache(directory: cacheDirectory)
        let image = try makeTestCGImage(width: 192, height: 192)
        let key = "test-roundtrip-key"

        cache.saveImage(image, forKey: key)
        let loaded = cache.loadImage(forKey: key)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.width, 192)
        XCTAssertEqual(loaded?.height, 192)
    }

    func testCacheKeyChangesWhenBundleModificationDateChanges() throws {
        let appURL = fixtureDirectory.appendingPathComponent("Sample.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        try Data("<plist/>".utf8).write(to: infoPlistURL)

        let cache = FileAppIconDiskCache(directory: fixtureDirectory)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: infoPlistURL.path
        )
        let initialKey = cache.cacheKey(for: appURL, pixelSize: 192)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_010)],
            ofItemAtPath: infoPlistURL.path
        )
        let updatedKey = cache.cacheKey(for: appURL, pixelSize: 192)

        XCTAssertNotEqual(initialKey, updatedKey)
    }

    func testDiskCacheReturnsNilForMissingOrCorruptFile() throws {
        let cache = FileAppIconDiskCache(directory: fixtureDirectory)

        XCTAssertNil(cache.loadImage(forKey: "missing-key"))

        let corruptURL = fixtureDirectory.appendingPathComponent("corrupt.png")
        try Data("not-a-png".utf8).write(to: corruptURL)
        XCTAssertNil(cache.loadImage(forKey: "corrupt"))
    }

    func testDiskCachePrunesUnreferencedEntries() throws {
        let cache = FileAppIconDiskCache(directory: fixtureDirectory)
        let image = try makeTestCGImage(width: 64, height: 64)

        cache.saveImage(image, forKey: "keep-me")
        cache.saveImage(image, forKey: "remove-me")
        cache.prune(keeping: ["keep-me"])

        XCTAssertNotNil(cache.loadImage(forKey: "keep-me"))
        XCTAssertNil(cache.loadImage(forKey: "remove-me"))
    }

    func testRasterizerProducesExactPixelSize() throws {
        let sourceCG = try makeTestCGImage(width: 256, height: 128)
        let nsImage = NSImage(cgImage: sourceCG, size: NSSize(width: 256, height: 128))

        let rasterized = AppIconRasterizer.rasterize(nsImage, pixelSize: 192)

        XCTAssertNotNil(rasterized)
        XCTAssertEqual(rasterized?.width, 192)
        XCTAssertEqual(rasterized?.height, 192)
    }

    private func makeTestCGImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.65, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
