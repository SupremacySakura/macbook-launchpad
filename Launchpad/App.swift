import AppKit

struct App: Identifiable, Hashable, Sendable, Codable {
    let id: URL
    let name: String
    let sourceURL: URL
    let launchURL: URL
    let bundleIdentifier: String?
    let isSymbolicLink: Bool
    let searchAliases: [String]

    init(
        name: String,
        sourceURL: URL,
        launchURL: URL,
        bundleIdentifier: String?,
        isSymbolicLink: Bool,
        searchAliases: [String] = []
    ) {
        self.id = launchURL
        self.name = name
        self.sourceURL = sourceURL.standardizedFileURL
        self.launchURL = launchURL.standardizedFileURL
        self.bundleIdentifier = bundleIdentifier
        self.isSymbolicLink = isSymbolicLink
        self.searchAliases = searchAliases
    }

    static func == (lhs: App, rhs: App) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    func hasSameMetadata(as other: App) -> Bool {
        id == other.id
            && name == other.name
            && sourceURL == other.sourceURL
            && launchURL == other.launchURL
            && bundleIdentifier == other.bundleIdentifier
            && isSymbolicLink == other.isSymbolicLink
            && searchAliases == other.searchAliases
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case sourceURL
        case launchURL
        case bundleIdentifier
        case isSymbolicLink
        case searchAliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            sourceURL: try container.decode(URL.self, forKey: .sourceURL),
            launchURL: try container.decode(URL.self, forKey: .launchURL),
            bundleIdentifier: try container.decodeIfPresent(
                String.self,
                forKey: .bundleIdentifier
            ),
            isSymbolicLink: try container.decode(Bool.self, forKey: .isSymbolicLink),
            searchAliases: try container.decodeIfPresent(
                [String].self,
                forKey: .searchAliases
            ) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(launchURL, forKey: .launchURL)
        try container.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(isSymbolicLink, forKey: .isSymbolicLink)
        if !searchAliases.isEmpty {
            try container.encode(searchAliases, forKey: .searchAliases)
        }
    }
}
