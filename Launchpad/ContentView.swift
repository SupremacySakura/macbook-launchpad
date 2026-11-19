import AppKit
import SwiftUI

struct ContentView: View {
    @State private var apps: [App] = []
    @State private var query = ""
    @State private var launchingAppID: App.ID?
    @State private var escapeMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var itemFrames: [App.ID: CGRect] = [:]
    @State private var searchBarFrame: CGRect = .zero
    @FocusState private var searchFocused: Bool

    private let columns = Array(
        repeating: GridItem(.fixed(152), spacing: 24, alignment: .top),
        count: 8
    )

    private var visibleApps: [App] {
        AppSearch.filter(apps, query: query)
    }

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                    .padding(.top, 64)

                applicationGrid
                    .padding(.top, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .coordinateSpace(name: "launchpad-window")
        .preferredColorScheme(.dark)
        .onAppear(perform: prepare)
        .onPreferenceChange(AppItemFramesKey.self) { frames in
            itemFrames = frames
        }
        .onPreferenceChange(SearchBarFrameKey.self) { frame in
            searchBarFrame = frame
        }
        .onDisappear {
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
            }
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            TextField("搜索", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit(launchFirstMatch)
        }
        .padding(.horizontal, 18)
        .frame(width: 340, height: 44)
        .background(Capsule().fill(.white.opacity(0.14)))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchBarFrameKey.self,
                    value: proxy.frame(in: .named("launchpad-window"))
                )
            }
        )
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
    }

    private var applicationGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 1)
                        .id("grid-top")

                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(visibleApps) { app in
                            appItem(app)
                        }
                    }
                    .padding(.horizontal, 56)
                    .padding(.top, 23)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
            .onAppear {
                resetScrollPosition(proxy)
            }
            .onChange(of: apps.count) {
                resetScrollPosition(proxy)
            }
            .onChange(of: query) { _, _ in
                resetScrollPosition(proxy)
            }
        }
    }

    private func resetScrollPosition(_ proxy: ScrollViewProxy) {
        let scroll = {
            proxy.scrollTo("grid-top", anchor: .top)
        }
        DispatchQueue.main.async(execute: scroll)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: scroll)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: scroll)
    }

    private func appItem(_ app: App) -> some View {
        Button {
            launch(app)
        } label: {
            VStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)

                Text(app.name)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 144)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .frame(width: 152)
            .scaleEffect(launchingAppID == app.id ? 1.1 : 1.0)
            .animation(.easeOut(duration: 0.1), value: launchingAppID)
        }
        .buttonStyle(.plain)
        .help(app.name)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AppItemFramesKey.self,
                    value: [app.id: proxy.frame(in: .named("launchpad-window"))]
                )
            }
        )
    }

    private func prepare() {
        if apps.isEmpty {
            apps = FileSystemAppScanner().scan()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            searchFocused = true
        }

        installEscapeMonitor()
        installMouseMonitor()
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }

            if query.isEmpty {
                NSApp.terminate(nil)
            } else {
                query = ""
            }
            return nil
        }
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if isClickOnInteractiveElement(event) {
                return event
            }
            NSApp.terminate(nil)
            return nil
        }
    }

    private func isClickOnInteractiveElement(_ event: NSEvent) -> Bool {
        guard let contentView = event.window?.contentView else { return false }

        var point = contentView.convert(event.locationInWindow, from: nil)
        if !contentView.isFlipped {
            point.y = contentView.bounds.height - point.y
        }

        if searchBarFrame.contains(point) {
            return true
        }
        return itemFrames.values.contains { $0.contains(point) }
    }

    private func launchFirstMatch() {
        guard let first = visibleApps.first else { return }
        launch(first)
    }

    private func launch(_ app: App) {
        guard launchingAppID == nil else { return }

        withAnimation(.easeOut(duration: 0.1)) {
            launchingAppID = app.id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSWorkspace.shared.open(app.url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                NSApp.terminate(nil)
            }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct AppItemFramesKey: PreferenceKey {
    static var defaultValue: [App.ID: CGRect] = [:]

    static func reduce(value: inout [App.ID: CGRect], nextValue: () -> [App.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct SearchBarFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}
