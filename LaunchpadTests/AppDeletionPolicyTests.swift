import XCTest

final class AppDeletionPolicyTests: XCTestCase {
    private var fixtureDirectory: URL!
    private var allowedRoot: URL!

    override func setUpWithError() throws {
        fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        allowedRoot = fixtureDirectory.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(
            at: allowedRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    func testAllowsOrdinaryAppInsideWritableRoot() throws {
        let app = try makeApp(named: "Example")
        let policy = makePolicy()

        XCTAssertTrue(policy.canDelete(app))
    }

    func testRejectsSymbolicLinkSource() throws {
        let app = try makeApp(named: "Linked", isSymbolicLink: true)
        let policy = makePolicy()

        XCTAssertFalse(policy.canDelete(app))
    }

    func testRejectsAppOutsideAllowedRoot() throws {
        let app = try makeApp(named: "Outside", root: fixtureDirectory)
        let policy = makePolicy()

        XCTAssertFalse(policy.canDelete(app))
    }

    func testRejectsProtectedLaunchTarget() throws {
        let app = try makeApp(
            named: "Protected",
            launchURL: URL(fileURLWithPath: "/System/Applications/Protected.app")
        )
        let policy = makePolicy()

        XCTAssertFalse(policy.canDelete(app))
    }

    func testRejectsLaunchpadItself() throws {
        let app = try makeApp(named: "Launchpad")
        let policy = makePolicy(ownBundleURL: app.launchURL, ownBundleIdentifier: app.bundleIdentifier)

        XCTAssertFalse(policy.canDelete(app))
    }

    func testRejectsPathThatOnlySharesAllowedRootPrefix() throws {
        let sibling = fixtureDirectory.appendingPathComponent("Applications-other", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let app = try makeApp(named: "Sibling", root: sibling)
        let policy = makePolicy()

        XCTAssertFalse(policy.canDelete(app))
    }

    private func makePolicy(
        ownBundleURL: URL? = nil,
        ownBundleIdentifier: String? = "test.launchpad"
    ) -> AppDeletionPolicy {
        AppDeletionPolicy(
            allowedRoots: [allowedRoot],
            protectedRoots: ["/System", "/Library/Apple", "/usr"],
            ownBundleURL: ownBundleURL ?? fixtureDirectory.appendingPathComponent("Self.app"),
            ownBundleIdentifier: ownBundleIdentifier
        )
    }

    private func makeApp(
        named name: String,
        root: URL? = nil,
        launchURL: URL? = nil,
        isSymbolicLink: Bool = false
    ) throws -> App {
        let root = root ?? allowedRoot!
        let sourceURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        return App(
            name: name,
            sourceURL: sourceURL,
            launchURL: launchURL ?? sourceURL,
            bundleIdentifier: "test.\(name.lowercased())",
            isSymbolicLink: isSymbolicLink
        )
    }
}
