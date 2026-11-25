import Darwin
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

    func testScanIncludesHiddenSymlinkedApp() throws {
        let rootDir = fixtureDirectory.appendingPathComponent("Apps", isDirectory: true)
        let cryptexDir = fixtureDirectory.appendingPathComponent("Cryptex", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cryptexDir, withIntermediateDirectories: true)

        let safariTarget = try makeFakeBundle(
            in: cryptexDir,
            directoryName: "Safari",
            displayName: "Safari"
        )
        let hiddenSymlink = rootDir.appendingPathComponent("Safari.app")
        try FileManager.default.createSymbolicLink(at: hiddenSymlink, withDestinationURL: safariTarget)
        XCTAssertEqual(lchflags(hiddenSymlink.path, UInt32(UF_HIDDEN)), 0)

        let scanner = FileSystemAppScanner(directories: [rootDir])
        let apps = scanner.scan()

        XCTAssertEqual(apps.map(\.name), ["Safari"])
        XCTAssertEqual(apps.first?.isSymbolicLink, true)
        XCTAssertEqual(
            apps.first?.launchURL,
            safariTarget.resolvingSymlinksInPath().standardizedFileURL
        )
    }

    func testScanFollowsSymlinkedSubdirectoryWithoutCycles() throws {
        let rootDir = fixtureDirectory.appendingPathComponent("Apps", isDirectory: true)
        let externalDir = fixtureDirectory.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)

        try makeFakeBundle(in: externalDir, directoryName: "BrewApp", displayName: "BrewApp")
        try FileManager.default.createSymbolicLink(
            at: rootDir.appendingPathComponent("HomebrewApps"),
            withDestinationURL: externalDir
        )
        // Cyclic symlink back to rootDir
        try FileManager.default.createSymbolicLink(
            at: externalDir.appendingPathComponent("Loop"),
            withDestinationURL: rootDir
        )

        let scanner = FileSystemAppScanner(directories: [rootDir])

        XCTAssertEqual(scanner.scan().map(\.name), ["BrewApp"])
    }

    func testScanSkipsBrokenSymlinkAndDotDirectories() throws {
        let missingTarget = fixtureDirectory.appendingPathComponent("Missing.app")
        try FileManager.default.createSymbolicLink(
            at: fixtureDirectory.appendingPathComponent("Broken.app"),
            withDestinationURL: missingTarget
        )

        let dotDir = fixtureDirectory.appendingPathComponent(".hidden-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        try makeFakeBundle(in: dotDir, directoryName: "Secret", displayName: "Secret")

        try makeFakeBundle(directoryName: "Visible", displayName: "Visible")

        let scanner = FileSystemAppScanner(directories: [fixtureDirectory])

        XCTAssertEqual(scanner.scan().map(\.name), ["Visible"])
    }

    func testScanPopulatesSearchAliasesAndHandlesEmptyDisplayName() throws {
        try makeFakeBundle(
            directoryName: "Visual Studio Code",
            displayName: "Code"
        )
        try makeFakeBundle(
            directoryName: "EmptyDisplay",
            displayName: "   ",
            bundleName: "FallbackBundle"
        )

        let scanner = FileSystemAppScanner(directories: [fixtureDirectory])
        let apps = scanner.scan()

        XCTAssertEqual(apps.map(\.name), ["Code", "FallbackBundle"])
        XCTAssertTrue(apps[0].searchAliases.contains("Visual Studio Code"))
        XCTAssertTrue(apps[1].searchAliases.contains("EmptyDisplay"))
    }

    func testDefaultDirectoriesIncludesCryptexApplications() {
        let paths = FileSystemAppScanner.defaultDirectories.map(\.path)
        XCTAssertTrue(paths.contains("/System/Cryptexes/App/System/Applications"))
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
