import AppKit

protocol AppScanner: Sendable {
    func scan() -> [App]
}

struct FileSystemAppScanner: AppScanner {
    let directories: [URL]

    init(directories: [URL] = FileSystemAppScanner.defaultDirectories) {
        self.directories = directories
    }

    static var defaultDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        ]
    }

    func scan() -> [App] {
        var seenURLs = Set<URL>()
        var apps: [App] = []

        for directory in directories {
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "app" else { continue }
                let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
                guard seenURLs.insert(canonicalURL).inserted else { continue }
                apps.append(makeApp(sourceURL: url, canonicalURL: canonicalURL))
            }
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func makeApp(sourceURL: URL, canonicalURL: URL) -> App {
        let bundle = Bundle(url: canonicalURL)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fallbackName = canonicalURL.deletingPathExtension().lastPathComponent
        let name = displayName ?? bundleName ?? fallbackName
        let isSymbolicLink = (try? sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false

        return App(
            name: name,
            sourceURL: sourceURL,
            launchURL: canonicalURL,
            bundleIdentifier: bundle?.bundleIdentifier,
            isSymbolicLink: isSymbolicLink
        )
    }
}
