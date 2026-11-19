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

    private func makeApp(_ name: String) -> App {
        App(
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            icon: NSImage(size: NSSize(width: 128, height: 128))
        )
    }
}
