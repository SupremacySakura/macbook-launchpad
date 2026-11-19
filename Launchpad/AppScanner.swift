import AppKit

protocol AppScanner {
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
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents where url.pathExtension == "app" {
                let canonicalURL = url.standardizedFileURL
                guard seenURLs.insert(canonicalURL).inserted else { continue }
                apps.append(makeApp(at: canonicalURL))
            }
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func makeApp(at url: URL) -> App {
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let name = displayName ?? bundleName ?? fallbackName

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 128, height: 128)

        return App(name: name, url: url, icon: icon)
    }
}
