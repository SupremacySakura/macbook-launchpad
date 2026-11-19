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

    func testScanFindsApplicationsInDirectory() throws {
        try makeFakeBundle(named: "Beta")
        try makeFakeBundle(named: "Alpha")

        let scanner = FileSystemAppScanner(directories: [fixtureDirectory])
        let names = scanner.scan().map(\.name)

        XCTAssertEqual(names, ["Alpha", "Beta"])
    }

    func testScanIgnoresNonApplicationEntries() throws {
        try makeFakeBundle(named: "Alpha")
        try FileManager.default.createDirectory(
            at: fixtureDirectory.appendingPathComponent("Folder", isDirectory: true),
            withIntermediateDirectories: true
        )

        let scanner = FileSystemAppScanner(directories: [fixtureDirectory])

        XCTAssertEqual(scanner.scan().map(\.name), ["Alpha"])
    }

    func testScanDeduplicatesTheSameDirectory() throws {
        try makeFakeBundle(named: "Alpha")

        let scanner = FileSystemAppScanner(directories: [fixtureDirectory, fixtureDirectory])

        XCTAssertEqual(scanner.scan().map(\.name), ["Alpha"])
    }

    private func makeFakeBundle(named name: String) throws {
        let contents = fixtureDirectory
            .appendingPathComponent("\(name).app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleName": name,
            "CFBundleIdentifier": "test.\(name.lowercased())",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
