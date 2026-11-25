import AppKit
import XCTest

final class AppSearchTests: XCTestCase {
    func testFiltersByCaseInsensitiveSubstring() {
        let apps = [makeApp("Safari"), makeApp("Chrome"), makeApp("Notes")]

        let result = AppSearch.filter(apps, query: "saf")

        XCTAssertEqual(result.map(\.name), ["Safari"])
    }

    func testUppercaseQueryMatchesLowercaseName() {
        let apps = [makeApp("Safari")]

        let result = AppSearch.filter(apps, query: "SAFARI")

        XCTAssertEqual(result.map(\.name), ["Safari"])
    }

    func testEmptyQueryReturnsAllApps() {
        let apps = [makeApp("Safari"), makeApp("Chrome")]

        XCTAssertEqual(AppSearch.filter(apps, query: "").map(\.name), ["Safari", "Chrome"])
        XCTAssertEqual(AppSearch.filter(apps, query: "   ").map(\.name), ["Safari", "Chrome"])
    }

    func testUnmatchedQueryReturnsNoApps() {
        let apps = [makeApp("Safari"), makeApp("Chrome")]

        XCTAssertTrue(AppSearch.filter(apps, query: "settings").isEmpty)
    }

    func testMockScannerSuppliesAppsThroughScanningSeam() {
        let scanner = MockAppScanner(apps: [makeApp("Safari"), makeApp("Chrome")])

        let result = AppSearch.filter(scanner.scan(), query: "chr")

        XCTAssertEqual(result.map(\.name), ["Chrome"])
    }

    func testFuzzySubsequenceMatchesConsonantsAndAbbreviations() {
        let apps = [makeApp("Safari"), makeApp("Terminal"), makeApp("Notes")]

        XCTAssertEqual(AppSearch.filter(apps, query: "sfr").map(\.name), ["Safari"])
        XCTAssertEqual(AppSearch.filter(apps, query: "trm").map(\.name), ["Terminal"])
    }

    func testAcronymAndCamelCaseMatchingWithAliases() {
        let apps = [
            makeApp("Google Chrome"),
            makeApp("DeskMate"),
            makeApp("Code", aliases: ["Visual Studio Code"]),
        ]

        XCTAssertEqual(AppSearch.filter(apps, query: "gc").map(\.name), ["Google Chrome"])
        XCTAssertEqual(AppSearch.filter(apps, query: "dm").map(\.name), ["DeskMate"])
        XCTAssertEqual(AppSearch.filter(apps, query: "vsc").map(\.name), ["Code"])
        XCTAssertEqual(AppSearch.filter(apps, query: "vscode").map(\.name), ["Code"])
    }

    func testTypoToleranceMatchesSmallTranspositionsAndEdits() {
        let apps = [makeApp("Safari"), makeApp("Google Chrome"), makeApp("Notes")]

        XCTAssertEqual(AppSearch.filter(apps, query: "chorme").map(\.name), ["Google Chrome"])
        XCTAssertEqual(AppSearch.filter(apps, query: "safrai").map(\.name), ["Safari"])
    }

    func testPinyinFullAndInitialsMatchChineseAppNames() {
        let apps = [makeApp("微信"), makeApp("哔哩哔哩"), makeApp("Safari")]

        XCTAssertEqual(AppSearch.filter(apps, query: "wx").map(\.name), ["微信"])
        XCTAssertEqual(AppSearch.filter(apps, query: "weixin").map(\.name), ["微信"])
        XCTAssertEqual(AppSearch.filter(apps, query: "blbl").map(\.name), ["哔哩哔哩"])
        XCTAssertEqual(AppSearch.filter(apps, query: "bilibili").map(\.name), ["哔哩哔哩"])
    }

    func testMultiTokenQueryMatchesAcrossWordsAndAliases() {
        let apps = [
            makeApp("Code", aliases: ["Visual Studio Code"]),
            makeApp("Google Chrome"),
            makeApp("Safari"),
        ]

        XCTAssertEqual(AppSearch.filter(apps, query: "vs code").map(\.name), ["Code"])
        XCTAssertEqual(AppSearch.filter(apps, query: "google chr").map(\.name), ["Google Chrome"])
    }

    func testRanksPrefixMatchesAheadOfFuzzyAndTypoMatches() {
        let apps = [
            makeApp("App Store"),
            makeApp("Safari"),
            makeApp("System Settings"),
            makeApp("Safrai Helper"),
        ]

        let result = AppSearch.filter(apps, query: "saf")
        XCTAssertEqual(result.first?.name, "Safari")
    }

    func testTwoCharacterNonBoundarySubsequenceDoesNotCreateNoise() {
        let apps = [makeApp("Activity Monitor")]

        XCTAssertTrue(AppSearch.filter(apps, query: "ar").isEmpty)
        XCTAssertEqual(AppSearch.filter(apps, query: "am").map(\.name), ["Activity Monitor"])
    }

    private func makeApp(_ name: String, aliases: [String] = []) -> App {
        let url = URL(fileURLWithPath: "/Applications/\(name).app")
        return App(
            name: name,
            sourceURL: url,
            launchURL: url,
            bundleIdentifier: "test.\(name)",
            isSymbolicLink: false,
            searchAliases: aliases
        )
    }
}

private struct MockAppScanner: AppScanner {
    let apps: [App]

    func scan() -> [App] {
        apps
    }
}
