import AppKit
import SwiftUI

@main
struct LaunchpadApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = LaunchpadAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class LaunchpadAppDelegate: NSObject, NSApplicationDelegate {
    private var window: LaunchpadWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showLaunchpad()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showLaunchpad() {
        guard let screen = targetScreen() else { return }

        let screenInsets = screen.safeAreaInsets
        let safeAreaInsets = EdgeInsets(
            top: screenInsets.top,
            leading: screenInsets.left,
            bottom: screenInsets.bottom,
            trailing: screenInsets.right
        )

        let cache = FileAppListCache()
        let cachedApps = cache.load()
        let iconStore = AppIconStore(backingScale: screen.backingScaleFactor)

        if !cachedApps.isEmpty {
            let estimatedGridSize = CGSize(
                width: max(0, screen.frame.width - safeAreaInsets.leading - safeAreaInsets.trailing),
                height: max(0, screen.frame.height - safeAreaInsets.top - safeAreaInsets.bottom - 140)
            )
            let estimatedCapacity = LaunchpadGridMetrics(viewportSize: estimatedGridSize).capacity
            iconStore.prefetch(
                Array(cachedApps.prefix(estimatedCapacity)),
                priority: .userInitiated
            )
        }

        let initialAppearance = LaunchpadAppearanceMode.loadSaved()

        let window = LaunchpadWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let rootView = ContentView(
            cache: cache,
            initialApps: cachedApps,
            iconStore: iconStore,
            safeAreaInsets: safeAreaInsets,
            onAppearanceChange: { [weak window] mode in
                window?.appearance = mode.nsAppearance
            }
        )
        let hostingView = NSHostingView(rootView: rootView)

        window.appearance = initialAppearance.nsAppearance
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        window.setFrame(screen.frame, display: true)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        let shouldReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = shouldReduceMotion ? 0.08 : 0.18
            context.timingFunction = shouldReduceMotion
                ? CAMediaTimingFunction(name: .easeOut)
                : CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            window.animator().alphaValue = 1
        } completionHandler: {
            window.makeKey()
        }

        self.window = window
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main
    }
}

private final class LaunchpadWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
