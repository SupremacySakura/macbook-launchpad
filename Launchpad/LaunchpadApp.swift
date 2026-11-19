import AppKit
import SwiftUI

@main
struct LaunchpadApp: SwiftUI.App {
    @NSApplicationDelegateAdaptor(LaunchpadAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class LaunchpadAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.activate()
    }

    static func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct WindowConfigurator: NSViewRepresentable {
    final class Coordinator {
        var didRequestFullScreen = false
        var fullScreenRetryCount = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configure(window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            configure(window, coordinator: context.coordinator, animated: false)
        }
    }

    private func configure(_ window: NSWindow, coordinator: Coordinator, animated: Bool = true) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.level = .normal
        window.collectionBehavior = [.fullScreenPrimary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        LaunchpadAppDelegate.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            LaunchpadAppDelegate.activate()
            window.makeKey()
        }

        activateAfterDelay(0.4)

        guard !coordinator.didRequestFullScreen else { return }
        coordinator.didRequestFullScreen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !window.styleMask.contains(.fullScreen),
                      coordinator.fullScreenRetryCount < 1 else { return }
                coordinator.fullScreenRetryCount += 1
                window.toggleFullScreen(nil)
            }
        }

        guard animated else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    private func activateAfterDelay(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            LaunchpadAppDelegate.activate()
        }
    }
}
