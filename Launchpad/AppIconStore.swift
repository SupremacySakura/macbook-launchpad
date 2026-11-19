import AppKit
import SwiftUI

@MainActor
final class AppIconStore: ObservableObject {
    @Published private(set) var icons: [App.ID: NSImage] = [:]

    private var loading: Set<App.ID> = []
    private var failed: Set<App.ID> = []

    func prefetch(_ apps: [App], priority: TaskPriority = .userInitiated) {
        for app in apps {
            guard icons[app.id] == nil,
                  !loading.contains(app.id),
                  !failed.contains(app.id) else {
                continue
            }

            loading.insert(app.id)
            Task.detached(priority: priority) { [weak self] in
                let icon = Self.loadIcon(at: app.launchURL)
                await self?.finishLoading(icon, for: app.id)
            }
        }
    }

    func remove(_ app: App) {
        icons.removeValue(forKey: app.id)
        loading.remove(app.id)
        failed.remove(app.id)
    }

    private func finishLoading(_ icon: NSImage?, for appID: App.ID) {
        loading.remove(appID)

        guard let icon else {
            failed.insert(appID)
            return
        }

        icon.size = NSSize(width: 128, height: 128)
        icons[appID] = icon
    }

    nonisolated private static func loadIcon(at url: URL) -> NSImage? {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
