import XCTest

final class AppScannerTests: XCTestCase {
    private var fixtureDirectory: URL!

    override func setUpWithError() throws {
        fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    func testScanFindsApplicationsAndSortsByDisplayName() throws {
        try makeFakeBundle(directoryName: "ZetaFolder", displayName: "Beta")
        try makeFakeBundle(directoryName: "AlphaFolder", bundleName: "Alpha")

        let scanner = FileSystemAppScanner(directories: [fixtureDirectory])
        let names = scanner.scan().map(\.name)

        XCTAssertEqual(names, ["Alpha", "Beta"])
    }

    func testScanIncludesNestedUtilitiesApplications() throws {
        let utilities = fixtureDirectory.appendingPathComponent("Utilities", isDirectory: true)
        try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
        try makeFakeBundle(in: utilities, directoryName: "FakeTerminal", displayName: "FakeTerminal")

        let scanner = FileSystemAppScanner(directories: [fixtureDirectory])

        XCTAssertEqual(scanner.scan().map(\.name), ["FakeTerminal"])
    }

    func testScanFallsBackToBundleFilenameWithoutInfoPlist() throws {
        let bundleURL = fixtureDirectory
            .appendingPathComponent("FallbackName.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let scanner = FileSystemAppScanner(directories: [fixtureDirectory])

        XCTAssertEqual(scanner.scan().map(\.name), ["FallbackName"])
    }

    func testScanIgnoresNonApplicationEntries() throws {
        try makeFakeBundle(directoryName: "Alpha", bundleName: "Alpha")
        try FileManager.default.createDirectory(
            at: fixtureDirectory.appendingPathComponent("Folder", isDirectory: true),
            withIntermediateDirectories: true
        )

        let scanner = FileSystemAppScanner(directories: [fixtureDirectory])

        XCTAssertEqual(scanner.scan().map(\.name), ["Alpha"])
    }

    func testScanDeduplicatesSymlinkedApplications() throws {
        let realDirectory = fixtureDirectory.appendingPathComponent("Real", isDirectory: true)
        let aliasDirectory = fixtureDirectory.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aliasDirectory, withIntermediateDirectories: true)

        let bundleURL = try makeFakeBundle(
            in: realDirectory,
            directoryName: "Alpha",
            bundleName: "Alpha"
        )
        try FileManager.default.createSymbolicLink(
            at: aliasDirectory.appendingPathComponent("AlphaLink.app"),
            withDestinationURL: bundleURL
        )

        let scanner = FileSystemAppScanner(directories: [realDirectory, aliasDirectory])

        XCTAssertEqual(scanner.scan().map(\.name), ["Alpha"])
    }

    @discardableResult
    private func makeFakeBundle(
        in parent: URL? = nil,
        directoryName: String,
        displayName: String? = nil,
        bundleName: String? = nil
    ) throws -> URL {
        let parent = parent ?? fixtureDirectory!
        let bundleURL = parent.appendingPathComponent("\(directoryName).app", isDirectory: true)
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

        var plist: [String: Any] = ["CFBundleIdentifier": "test.\(UUID().uuidString)"]
        if let displayName {
            plist["CFBundleDisplayName"] = displayName
        }
        if let bundleName {
            plist["CFBundleName"] = bundleName
        }

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return bundleURL
    }
}
