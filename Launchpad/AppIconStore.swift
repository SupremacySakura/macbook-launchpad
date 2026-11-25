import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class AppIconSlot {
    var image: CGImage?
    var scale: CGFloat

    init(scale: CGFloat = 2.0) {
        self.scale = scale
    }
}

@MainActor
final class AppIconStore {
    static let iconPointSize: CGFloat = 96

    private var slots: [App.ID: AppIconSlot] = [:]
    private var loadedKeys: [App.ID: String] = [:]
    private var inFlight: Set<App.ID> = []
    private var failed: Set<App.ID> = []
    private var pendingHigh: [App] = []
    private var pendingLow: [App] = []
    private var queuedIDs: Set<App.ID> = []
    private var activeWorkerCount = 0

    private let maxConcurrentLoads = 6
    private let backingScale: CGFloat
    private let diskCache: any AppIconDiskCache
    private let diskWriteQueue = DispatchQueue(
        label: "com.supremacysakura.launchpad.icon-disk-cache",
        qos: .utility
    )

    init(
        backingScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0,
        diskCache: any AppIconDiskCache = FileAppIconDiskCache()
    ) {
        self.backingScale = max(1.0, backingScale)
        self.diskCache = diskCache
    }

    func slot(for appID: App.ID) -> AppIconSlot {
        if let existing = slots[appID] {
            return existing
        }
        let slot = AppIconSlot(scale: backingScale)
        slots[appID] = slot
        return slot
    }

    func prefetch(_ apps: [App], priority: TaskPriority = .userInitiated) {
        let isHighPriority = priority == .userInitiated || priority == .high

        for app in apps {
            if let existingSlot = slots[app.id], existingSlot.image != nil {
                continue
            }
            guard !inFlight.contains(app.id), !failed.contains(app.id) else {
                continue
            }

            if queuedIDs.contains(app.id) {
                if isHighPriority, let index = pendingLow.firstIndex(where: { $0.id == app.id }) {
                    let promoted = pendingLow.remove(at: index)
                    pendingHigh.append(promoted)
                }
                continue
            }

            queuedIDs.insert(app.id)
            if isHighPriority {
                pendingHigh.append(app)
            } else {
                pendingLow.append(app)
            }
        }

        pumpQueue()
    }

    func remove(_ app: App) {
        if let slot = slots.removeValue(forKey: app.id) {
            slot.image = nil
        }
        if let key = loadedKeys.removeValue(forKey: app.id) {
            let diskCache = self.diskCache
            diskWriteQueue.async {
                diskCache.removeImage(forKey: key)
            }
        }
        inFlight.remove(app.id)
        failed.remove(app.id)
        queuedIDs.remove(app.id)
        pendingHigh.removeAll { $0.id == app.id }
        pendingLow.removeAll { $0.id == app.id }
    }

    func pruneDiskCache(for apps: [App]) {
        let pixelSize = targetPixelSize
        let urls = apps.map(\.launchURL)
        let diskCache = self.diskCache

        diskWriteQueue.async {
            let validKeys = Set(urls.map { diskCache.cacheKey(for: $0, pixelSize: pixelSize) })
            diskCache.prune(keeping: validKeys)
        }
    }

    private var targetPixelSize: Int {
        max(Int(Self.iconPointSize), Int((Self.iconPointSize * backingScale).rounded()))
    }

    private func pumpQueue() {
        while activeWorkerCount < maxConcurrentLoads, let (app, priority) = dequeueNext() {
            inFlight.insert(app.id)
            activeWorkerCount += 1

            let pixelSize = targetPixelSize
            let diskCache = self.diskCache
            let diskWriteQueue = self.diskWriteQueue

            Task.detached(priority: priority) { [weak self] in
                let result = Self.loadAndRasterize(
                    launchURL: app.launchURL,
                    pixelSize: pixelSize,
                    diskCache: diskCache,
                    diskWriteQueue: diskWriteQueue
                )
                await self?.finishLoading(result.image, key: result.key, for: app.id)
            }
        }
    }

    private func dequeueNext() -> (App, TaskPriority)? {
        if !pendingHigh.isEmpty {
            let app = pendingHigh.removeFirst()
            queuedIDs.remove(app.id)
            return (app, .userInitiated)
        }
        if !pendingLow.isEmpty {
            let app = pendingLow.removeFirst()
            queuedIDs.remove(app.id)
            return (app, .utility)
        }
        return nil
    }

    private func finishLoading(_ image: CGImage?, key: String, for appID: App.ID) {
        activeWorkerCount = max(0, activeWorkerCount - 1)
        inFlight.remove(appID)

        if let image {
            loadedKeys[appID] = key
            slot(for: appID).image = image
        } else {
            failed.insert(appID)
        }

        pumpQueue()
    }

    nonisolated private static func loadAndRasterize(
        launchURL: URL,
        pixelSize: Int,
        diskCache: any AppIconDiskCache,
        diskWriteQueue: DispatchQueue
    ) -> (image: CGImage?, key: String) {
        let key = diskCache.cacheKey(for: launchURL, pixelSize: pixelSize)

        if let cached = diskCache.loadImage(forKey: key) {
            return (cached, key)
        }

        let nsIcon = NSWorkspace.shared.icon(forFile: launchURL.path)
        guard let rasterized = AppIconRasterizer.rasterize(nsIcon, pixelSize: pixelSize) else {
            return (nil, key)
        }

        diskWriteQueue.async {
            diskCache.saveImage(rasterized, forKey: key)
        }

        return (rasterized, key)
    }
}
