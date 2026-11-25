import XCTest

final class AppCacheTests: XCTestCase {
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

    func testCacheRoundTripPreservesAppMetadata() {
        let cache = FileAppListCache(
            url: fixtureDirectory
                .appendingPathComponent("nested", isDirectory: true)
                .appendingPathComponent("app-list.json")
        )
        let apps = [
            makeApp(
                name: "Alpha",
                sourceURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
                launchURL: URL(fileURLWithPath: "/Applications/Real/Alpha.app"),
                bundleIdentifier: "test.alpha",
                isSymbolicLink: true,
                searchAliases: ["Alpha Alias", "阿尔法"]
            ),
            makeApp(
                name: "Beta",
                sourceURL: URL(fileURLWithPath: "/Applications/Beta.app")
            ),
        ]

        cache.save(apps)
        let loadedApps = cache.load()

        XCTAssertEqual(loadedApps.count, 2)
        XCTAssertEqual(loadedApps[0].name, "Alpha")
        XCTAssertEqual(
            loadedApps[0].sourceURL,
            URL(fileURLWithPath: "/Applications/Alpha.app")
        )
        XCTAssertEqual(
            loadedApps[0].launchURL,
            URL(fileURLWithPath: "/Applications/Real/Alpha.app")
        )
        XCTAssertEqual(loadedApps[0].bundleIdentifier, "test.alpha")
        XCTAssertTrue(loadedApps[0].isSymbolicLink)
        XCTAssertEqual(loadedApps[0].searchAliases, ["Alpha Alias", "阿尔法"])
        XCTAssertEqual(loadedApps[1].name, "Beta")
        XCTAssertEqual(loadedApps[1].bundleIdentifier, "test.beta")
        XCTAssertFalse(loadedApps[1].isSymbolicLink)
        XCTAssertTrue(loadedApps[1].searchAliases.isEmpty)
    }

    func testCacheDecodesLegacyPayloadWithoutSearchAliases() throws {
        let url = fixtureDirectory.appendingPathComponent("legacy-no-aliases.json")
        let json = """
        {
          "version": 1,
          "apps": [
            {
              "name": "Safari",
              "sourceURL": "file:///Applications/Safari.app",
              "launchURL": "file:///System/Cryptexes/App/System/Applications/Safari.app",
              "bundleIdentifier": "com.apple.Safari",
              "isSymbolicLink": true
            }
          ]
        }
        """
        try Data(json.utf8).write(to: url)
        let cache = FileAppListCache(url: url)
        let loaded = cache.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Safari")
        XCTAssertTrue(loaded[0].searchAliases.isEmpty)
    }

    func testCacheReturnsEmptyWhenFileIsMissing() {
        let cache = FileAppListCache(
            url: fixtureDirectory.appendingPathComponent("missing.json")
        )

        XCTAssertTrue(cache.load().isEmpty)
    }

    func testCacheReturnsEmptyWhenFileIsInvalid() throws {
        let url = fixtureDirectory.appendingPathComponent("invalid.json")
        try Data("not-json".utf8).write(to: url)
        let cache = FileAppListCache(url: url)

        XCTAssertTrue(cache.load().isEmpty)
    }

    func testCacheReturnsEmptyWhenVersionDoesNotMatch() throws {
        let url = fixtureDirectory.appendingPathComponent("old-version.json")
        let json = """
        {
          "version": 0,
          "apps": [
            {
              "name": "Alpha",
              "sourceURL": "file:///Applications/Alpha.app",
              "launchURL": "file:///Applications/Alpha.app",
              "isSymbolicLink": false
            }
          ]
        }
        """
        try Data(json.utf8).write(to: url)
        let cache = FileAppListCache(url: url)

        XCTAssertTrue(cache.load().isEmpty)
    }

    func testDiffReportsAddedRemovedChangedAndOrderChanges() {
        let alpha = makeApp(
            name: "Alpha",
            sourceURL: URL(fileURLWithPath: "/Applications/Alpha.app")
        )
        let beta = makeApp(
            name: "Beta",
            sourceURL: URL(fileURLWithPath: "/Applications/Beta.app")
        )
        let renamedBeta = makeApp(
            name: "Beta Pro",
            sourceURL: URL(fileURLWithPath: "/Applications/Beta.app")
        )
        let gamma = makeApp(
            name: "Gamma",
            sourceURL: URL(fileURLWithPath: "/Applications/Gamma.app")
        )

        let diff = AppListDiff.between(
            cached: [alpha, beta],
            scanned: [renamedBeta, gamma]
        )

        XCTAssertEqual(diff.removed.map(\.name), ["Alpha"])
        XCTAssertEqual(diff.added.map(\.name), ["Gamma"])
        XCTAssertEqual(diff.changed.map(\.name), ["Beta Pro"])
        XCTAssertTrue(diff.orderChanged)
        XCTAssertTrue(diff.hasChanges)
    }

    func testDiffRequiresNoUpdateForEquivalentSnapshots() {
        let apps = [
            makeApp(
                name: "Alpha",
                sourceURL: URL(fileURLWithPath: "/Applications/Alpha.app")
            ),
            makeApp(
                name: "Beta",
                sourceURL: URL(fileURLWithPath: "/Applications/Beta.app")
            ),
        ]

        let diff = AppListDiff.between(cached: apps, scanned: apps)

        XCTAssertFalse(diff.hasChanges)
        XCTAssertTrue(diff.added.isEmpty)
        XCTAssertTrue(diff.removed.isEmpty)
        XCTAssertTrue(diff.changed.isEmpty)
    }

    func testDiffDetectsOrderChangeWithoutMetadataChanges() {
        let alpha = makeApp(
            name: "Alpha",
            sourceURL: URL(fileURLWithPath: "/Applications/Alpha.app")
        )
        let beta = makeApp(
            name: "Beta",
            sourceURL: URL(fileURLWithPath: "/Applications/Beta.app")
        )

        let diff = AppListDiff.between(cached: [alpha, beta], scanned: [beta, alpha])

        XCTAssertTrue(diff.added.isEmpty)
        XCTAssertTrue(diff.removed.isEmpty)
        XCTAssertTrue(diff.changed.isEmpty)
        XCTAssertTrue(diff.orderChanged)
        XCTAssertTrue(diff.hasChanges)
    }

    private func makeApp(
        name: String,
        sourceURL: URL,
        launchURL: URL? = nil,
        bundleIdentifier: String? = nil,
        isSymbolicLink: Bool = false,
        searchAliases: [String] = []
    ) -> App {
        App(
            name: name,
            sourceURL: sourceURL,
            launchURL: launchURL ?? sourceURL,
            bundleIdentifier: bundleIdentifier
                ?? "test.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            isSymbolicLink: isSymbolicLink,
            searchAliases: searchAliases
        )
    }
}
