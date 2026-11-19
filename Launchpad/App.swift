import AppKit

struct App: Identifiable, Hashable, Sendable {
    let id: URL
    let name: String
    let sourceURL: URL
    let launchURL: URL
    let bundleIdentifier: String?
    let isSymbolicLink: Bool

    init(
        name: String,
        sourceURL: URL,
        launchURL: URL,
        bundleIdentifier: String?,
        isSymbolicLink: Bool
    ) {
        self.id = launchURL
        self.name = name
        self.sourceURL = sourceURL.standardizedFileURL
        self.launchURL = launchURL.standardizedFileURL
        self.bundleIdentifier = bundleIdentifier
        self.isSymbolicLink = isSymbolicLink
    }

    static func == (lhs: App, rhs: App) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
