import AppKit

protocol AppScanner: Sendable {
    func scan() -> [App]
}

struct FileSystemAppScanner: AppScanner {
    private static let maxDirectoryDepth = 4
    private static let resourceKeys: Set<URLResourceKey> = [
        .isSymbolicLinkKey,
        .isAliasFileKey,
        .isDirectoryKey,
        .isPackageKey,
    ]

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
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
        ]
    }

    func scan() -> [App] {
        var seenURLs = Set<URL>()
        var visitedDirectories = Set<URL>()
        var candidates: [ScanCandidate] = []

        for directory in directories {
            let rootPath = directory.standardizedFileURL.path
            let resolvedRoot = directory.resolvingSymlinksInPath().standardizedFileURL

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolvedRoot.path, isDirectory: &isDir),
                  isDir.boolValue,
                  visitedDirectories.insert(resolvedRoot).inserted else {
                continue
            }

            collectCandidates(
                in: directory,
                rootPath: rootPath,
                resolvedRoot: resolvedRoot,
                depth: 0,
                underSymlinkedDir: false,
                visitedDirectories: &visitedDirectories,
                seenURLs: &seenURLs,
                candidates: &candidates
            )
        }

        let apps: [App]
        if candidates.count < 8 {
            apps = candidates.map(makeApp(from:))
        } else {
            let storage = ConcurrentAppStorage(count: candidates.count)
            DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
                storage.set(makeApp(from: candidates[index]), at: index)
            }
            apps = storage.collect()
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func collectCandidates(
        in directory: URL,
        rootPath: String,
        resolvedRoot: URL,
        depth: Int,
        underSymlinkedDir: Bool,
        visitedDirectories: inout Set<URL>,
        seenURLs: inout Set<URL>,
        candidates: inout [ScanCandidate]
    ) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: []
        ) else {
            return
        }

        for url in entries {
            // Skip dot-files (e.g. .DS_Store, .localized) without skipping UF_HIDDEN apps like /Applications/Safari.app.
            guard !url.lastPathComponent.hasPrefix(".") else { continue }

            let values = try? url.resourceValues(forKeys: Self.resourceKeys)
            let isSymbolicLink = values?.isSymbolicLink ?? false
            let isAliasFile = values?.isAliasFile ?? false

            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                let canonicalURL: URL
                let effectiveSymbolicLink: Bool

                if isSymbolicLink {
                    canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
                    effectiveSymbolicLink = true
                } else if isAliasFile {
                    guard let resolvedAlias = try? URL(
                        resolvingAliasFileAt: url,
                        options: [.withoutUI, .withoutMounting]
                    ) else {
                        continue
                    }
                    canonicalURL = resolvedAlias.resolvingSymlinksInPath().standardizedFileURL
                    effectiveSymbolicLink = true
                } else {
                    canonicalURL = canonicalPath(
                        for: url,
                        rootPath: rootPath,
                        resolvedRoot: resolvedRoot,
                        underSymlinkedDir: underSymlinkedDir
                    )
                    effectiveSymbolicLink = false
                }

                var isTargetDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: canonicalURL.path, isDirectory: &isTargetDirectory),
                      isTargetDirectory.boolValue else {
                    continue
                }

                guard seenURLs.insert(canonicalURL).inserted else { continue }
                candidates.append(
                    ScanCandidate(
                        sourceURL: url,
                        canonicalURL: canonicalURL,
                        isSymbolicLink: effectiveSymbolicLink
                    )
                )
            } else if isAliasFile && !isSymbolicLink {
                guard let resolvedAlias = try? URL(
                    resolvingAliasFileAt: url,
                    options: [.withoutUI, .withoutMounting]
                ) else {
                    continue
                }
                let canonicalURL = resolvedAlias.resolvingSymlinksInPath().standardizedFileURL
                guard canonicalURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }

                var isTargetDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: canonicalURL.path, isDirectory: &isTargetDirectory),
                      isTargetDirectory.boolValue else {
                    continue
                }

                guard seenURLs.insert(canonicalURL).inserted else { continue }
                candidates.append(
                    ScanCandidate(
                        sourceURL: url,
                        canonicalURL: canonicalURL,
                        isSymbolicLink: true
                    )
                )
            } else if depth < Self.maxDirectoryDepth {
                if !isSymbolicLink {
                    guard values?.isDirectory == true, values?.isPackage != true else { continue }
                    let canonicalDir = canonicalPath(
                        for: url,
                        rootPath: rootPath,
                        resolvedRoot: resolvedRoot,
                        underSymlinkedDir: underSymlinkedDir
                    )
                    guard visitedDirectories.insert(canonicalDir).inserted else { continue }
                    collectCandidates(
                        in: url,
                        rootPath: rootPath,
                        resolvedRoot: resolvedRoot,
                        depth: depth + 1,
                        underSymlinkedDir: underSymlinkedDir,
                        visitedDirectories: &visitedDirectories,
                        seenURLs: &seenURLs,
                        candidates: &candidates
                    )
                } else {
                    let targetDir = url.resolvingSymlinksInPath().standardizedFileURL
                    guard targetDir.pathExtension.caseInsensitiveCompare("app") != .orderedSame else {
                        continue
                    }
                    let targetValues = try? targetDir.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                    guard targetValues?.isDirectory == true, targetValues?.isPackage != true else {
                        continue
                    }
                    guard visitedDirectories.insert(targetDir).inserted else { continue }
                    collectCandidates(
                        in: targetDir,
                        rootPath: rootPath,
                        resolvedRoot: resolvedRoot,
                        depth: depth + 1,
                        underSymlinkedDir: true,
                        visitedDirectories: &visitedDirectories,
                        seenURLs: &seenURLs,
                        candidates: &candidates
                    )
                }
            }
        }
    }

    private func canonicalPath(
        for url: URL,
        rootPath: String,
        resolvedRoot: URL,
        underSymlinkedDir: Bool
    ) -> URL {
        let standardizedPath = url.standardizedFileURL.path
        if !underSymlinkedDir && standardizedPath.hasPrefix(rootPath + "/") {
            let relativePath = String(standardizedPath.dropFirst(rootPath.count + 1))
            return resolvedRoot
                .appendingPathComponent(relativePath, isDirectory: true)
                .standardizedFileURL
        }
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func makeApp(from candidate: ScanCandidate) -> App {
        let bundle = Bundle(url: candidate.canonicalURL)
        let displayName = nonEmpty(bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        let bundleName = nonEmpty(bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
        let fallbackName = candidate.canonicalURL.deletingPathExtension().lastPathComponent
        let sourceFilename = candidate.sourceURL.deletingPathExtension().lastPathComponent
        let rawDisplay = FileManager.default.displayName(atPath: candidate.canonicalURL.path)
        let localizedDisplayName = nonEmpty(
            rawDisplay.lowercased().hasSuffix(".app")
                ? String(rawDisplay.dropLast(4))
                : rawDisplay
        )

        let name = displayName ?? bundleName ?? fallbackName

        var aliases: [String] = []
        var seenAliases: Set<String> = [name.lowercased()]
        for candidateAlias in [fallbackName, sourceFilename, displayName, bundleName, localizedDisplayName] {
            guard let alias = nonEmpty(candidateAlias) else { continue }
            let lowered = alias.lowercased()
            if seenAliases.insert(lowered).inserted {
                aliases.append(alias)
            }
        }

        return App(
            name: name,
            sourceURL: candidate.sourceURL,
            launchURL: candidate.canonicalURL,
            bundleIdentifier: bundle?.bundleIdentifier,
            isSymbolicLink: candidate.isSymbolicLink,
            searchAliases: aliases
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private struct ScanCandidate: Sendable {
        let sourceURL: URL
        let canonicalURL: URL
        let isSymbolicLink: Bool
    }

    private final class ConcurrentAppStorage: @unchecked Sendable {
        private let buffer: UnsafeMutableBufferPointer<App?>

        init(count: Int) {
            self.buffer = UnsafeMutableBufferPointer<App?>.allocate(capacity: count)
            self.buffer.initialize(repeating: nil)
        }

        deinit {
            buffer.deinitialize()
            buffer.deallocate()
        }

        func set(_ app: App, at index: Int) {
            buffer[index] = app
        }

        func collect() -> [App] {
            buffer.compactMap { $0 }
        }
    }
}
