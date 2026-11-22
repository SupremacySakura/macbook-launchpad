import Foundation

protocol AppListCache: Sendable {
    func load() -> [App]
    func save(_ apps: [App])
}

struct FileAppListCache: AppListCache {
    static let currentVersion = 1

    let url: URL

    init(url: URL = FileAppListCache.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("com.supremacysakura.launchpad", isDirectory: true)
            .appendingPathComponent("app-list.json")
    }

    func load() -> [App] {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(StoredAppList.self, from: data),
              payload.version == Self.currentVersion else {
            return []
        }

        return payload.apps
    }

    func save(_ apps: [App]) {
        let directory = url.deletingLastPathComponent()
        let payload = StoredAppList(version: Self.currentVersion, apps: apps)

        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private struct StoredAppList: Codable {
        let version: Int
        let apps: [App]
    }
}

struct AppListDiff {
    let added: [App]
    let removed: [App]
    let changed: [App]
    let orderChanged: Bool

    var hasChanges: Bool {
        !added.isEmpty || !removed.isEmpty || !changed.isEmpty || orderChanged
    }

    static func between(cached: [App], scanned: [App]) -> AppListDiff {
        let cachedByID = firstAppByID(cached)
        let scannedByID = firstAppByID(scanned)

        let added = scanned.filter { cachedByID[$0.id] == nil }
        let removed = cached.filter { scannedByID[$0.id] == nil }
        let changed = scanned.filter { app in
            guard let cachedApp = cachedByID[app.id] else { return false }
            return !cachedApp.hasSameMetadata(as: app)
        }

        return AppListDiff(
            added: added,
            removed: removed,
            changed: changed,
            orderChanged: cached.map(\.id) != scanned.map(\.id)
        )
    }

    private static func firstAppByID(_ apps: [App]) -> [App.ID: App] {
        apps.reduce(into: [:]) { result, app in
            if result[app.id] == nil {
                result[app.id] = app
            }
        }
    }
}
