import AppKit

struct AppDeletionPolicy {
    let allowedRoots: [URL]
    let protectedRoots: [String]
    let ownBundleURL: URL
    let ownBundleIdentifier: String?

    init(
        allowedRoots: [URL] = AppDeletionPolicy.defaultAllowedRoots,
        protectedRoots: [String] = ["/System", "/Library/Apple", "/usr"],
        ownBundleURL: URL = Bundle.main.bundleURL,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.allowedRoots = allowedRoots
        self.protectedRoots = protectedRoots
        self.ownBundleURL = ownBundleURL
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    static var defaultAllowedRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    func canDelete(_ app: App, fileManager: FileManager = .default) -> Bool {
        guard app.sourceURL.pathExtension == "app" else { return false }
        guard !app.isSymbolicLink else { return false }
        guard contains(app.sourceURL, in: allowedRoots) else { return false }
        guard !isProtected(app.sourceURL), !isProtected(app.launchURL) else { return false }
        guard !isOwnApp(app) else { return false }
        guard fileManager.fileExists(atPath: app.sourceURL.path) else { return false }

        let parentURL = app.sourceURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parentURL.path) else { return false }

        guard let values = try? app.sourceURL.resourceValues(
            forKeys: [.isDirectoryKey, .volumeIsReadOnlyKey]
        ) else {
            return false
        }

        return values.isDirectory == true && values.volumeIsReadOnly != true
    }

    private func contains(_ url: URL, in roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    private func isProtected(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return protectedRoots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    private func isOwnApp(_ app: App) -> Bool {
        let ownURL = ownBundleURL.resolvingSymlinksInPath().standardizedFileURL
        if app.launchURL == ownURL || app.sourceURL == ownURL {
            return true
        }

        guard let ownBundleIdentifier,
              let appBundleIdentifier = app.bundleIdentifier else {
            return false
        }
        return ownBundleIdentifier == appBundleIdentifier
    }
}

enum AppDeletionService {
    static func isRunning(_ app: App, workspace: NSWorkspace = .shared) -> Bool {
        let targetURL = app.launchURL.resolvingSymlinksInPath().standardizedFileURL

        return workspace.runningApplications.contains { runningApp in
            if let bundleIdentifier = app.bundleIdentifier,
               runningApp.bundleIdentifier == bundleIdentifier {
                return true
            }

            guard let runningURL = runningApp.bundleURL?.resolvingSymlinksInPath().standardizedFileURL else {
                return false
            }
            return runningURL == targetURL
        }
    }

    static func moveToTrash(
        _ app: App,
        workspace: NSWorkspace = .shared,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        workspace.recycle([app.sourceURL]) { newURLs, error in
            let result: Result<URL, Error>
            if let trashURL = newURLs[app.sourceURL] {
                result = .success(trashURL)
            } else if let error {
                result = .failure(error)
            } else {
                result = .failure(
                    NSError(
                        domain: "com.supremacysakura.launchpad",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "系统未返回废纸篓中的位置。"]
                    )
                )
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
