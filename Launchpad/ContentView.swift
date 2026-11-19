import AppKit
import SwiftUI

struct ContentView: View {
    @State private var apps: [App] = []
    @State private var query = ""
    @State private var isScanning = true
    @State private var didPrepare = false
    @State private var launchingAppID: App.ID?
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var searchBarFrame: CGRect = .zero
    @State private var gridFrame: CGRect = .zero
    @State private var pageIndicatorFrame: CGRect = .zero
    @State private var gridSize: CGSize = .zero
    @State private var scrollPosition: Int? = 0
    @State private var pageBeforeSearch = 0
    @State private var deletionPrompt: DeletionPrompt?
    @State private var deletingAppID: App.ID?
    @State private var contextMenu: AppContextMenu?
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var iconStore = AppIconStore()

    private let scanner: any AppScanner
    private let safeAreaInsets: EdgeInsets
    private let deletionPolicy = AppDeletionPolicy()

    init(
        scanner: any AppScanner = FileSystemAppScanner(),
        safeAreaInsets: EdgeInsets = EdgeInsets()
    ) {
        self.scanner = scanner
        self.safeAreaInsets = safeAreaInsets
    }

    private var visibleApps: [App] {
        AppSearch.filter(apps, query: query)
    }

    private var metrics: LaunchpadGridMetrics {
        LaunchpadGridMetrics(viewportSize: gridSize)
    }

    private var pageCount: Int {
        guard gridSize.width > 0, gridSize.height > 0 else { return 0 }
        return AppPaging.pageCount(itemCount: visibleApps.count, capacity: metrics.capacity)
    }

    private var currentPage: Int {
        AppPaging.clampedPage(
            scrollPosition ?? 0,
            itemCount: visibleApps.count,
            capacity: metrics.capacity
        )
    }

    private var currentPageApps: [App] {
        Array(
            AppPaging.apps(
                on: currentPage,
                from: visibleApps,
                capacity: metrics.capacity
            )
        )
    }

    private var isBusy: Bool {
        deletionPrompt != nil || deletingAppID != nil
    }

    private var blocksDismissal: Bool {
        isBusy || contextMenu != nil
    }

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                    .padding(.top, 24 + safeAreaInsets.top)

                pagedGrid
                    .padding(.top, 16)

                pageIndicator
                    .padding(.top, 8)
                    .padding(.bottom, 16 + safeAreaInsets.bottom)
            }
            .padding(.leading, safeAreaInsets.leading)
            .padding(.trailing, safeAreaInsets.trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(!isBusy)

            if let contextMenu {
                contextMenuOverlay(contextMenu)
                    .zIndex(10)
            }
        }
        .coordinateSpace(name: "launchpad-window")
        .preferredColorScheme(.dark)
        .onAppear(perform: prepare)
        .onChange(of: query) { oldQuery, newQuery in
            handleQueryChange(from: oldQuery, to: newQuery)
        }
        .onChange(of: pageCount) { _, _ in
            clampCurrentPage()
        }
        .onChange(of: currentPage) { _, newPage in
            guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            pageBeforeSearch = newPage
        }
        .onChange(of: currentPageApps.map(\.id)) { _, _ in
            prefetchIconsAroundCurrentPage()
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
            }
        }
        .alert(item: $deletionPrompt) { prompt in
            alert(for: prompt)
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
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchBarFrameKey.self,
                    value: proxy.frame(in: .named("launchpad-window"))
                )
            }
        )
        .onPreferenceChange(SearchBarFrameKey.self) { frame in
            searchBarFrame = frame
        }
    }

    private var pagedGrid: some View {
        GeometryReader { proxy in
            let pageMetrics = LaunchpadGridMetrics(viewportSize: proxy.size)
            let pageItems = AppPaging.pageCount(
                itemCount: visibleApps.count,
                capacity: pageMetrics.capacity
            )

            ZStack {
                if isScanning && apps.isEmpty {
                    loadingPlaceholder(pageMetrics, viewportSize: proxy.size)
                } else if visibleApps.isEmpty {
                    emptyState
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(0..<pageItems, id: \.self) { pageIndex in
                                let pageApps = Array(
                                    AppPaging.apps(
                                        on: pageIndex,
                                        from: visibleApps,
                                        capacity: pageMetrics.capacity
                                    )
                                )

                                applicationPage(
                                    pageApps,
                                    pageIndex: pageIndex,
                                    metrics: pageMetrics,
                                    viewportSize: proxy.size
                                )
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .id(pageIndex)
                                .task(id: pageApps.map(\.id)) {
                                    guard abs(pageIndex - currentPage) <= 1 else { return }
                                    iconStore.prefetch(
                                        pageApps,
                                        priority: pageIndex == currentPage ? .userInitiated : .utility
                                    )
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.never)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrollPosition)
                    .defaultScrollAnchor(.leading)
                }
            }
            .onAppear {
                gridSize = proxy.size
            }
            .onChange(of: proxy.size) { _, newSize in
                gridSize = newSize
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GridFrameKey.self,
                    value: proxy.frame(in: .named("launchpad-window"))
                )
            }
        )
        .onPreferenceChange(GridFrameKey.self) { frame in
            gridFrame = frame
        }
    }

    private func applicationPage(
        _ pageApps: [App],
        pageIndex: Int,
        metrics: LaunchpadGridMetrics,
        viewportSize: CGSize
    ) -> some View {
        return ZStack(alignment: .topLeading) {
            VStack(spacing: LaunchpadGridMetrics.verticalSpacing) {
                ForEach(Array(rows(of: pageApps, columns: metrics.columns).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: LaunchpadGridMetrics.horizontalSpacing) {
                        ForEach(row) { app in
                            appItem(app)
                        }
                    }
                }
            }
            .position(
                x: viewportSize.width / 2,
                y: viewportSize.height / 2
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if pageIndex == currentPage && visibleApps.isEmpty {
                emptyState
            }
        }
    }

    private func appItem(_ app: App) -> some View {
        Button {
            launch(app)
        } label: {
            VStack(spacing: 6) {
                if let icon = iconStore.icons[app.id] {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 128, height: 128)
                } else {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: 128, height: 128)
                        .overlay {
                            Image(systemName: "app.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white.opacity(0.24))
                        }
                }

                Text(app.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 144)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .frame(width: LaunchpadGridMetrics.cellWidth, height: LaunchpadGridMetrics.cellHeight, alignment: .top)
            .scaleEffect(launchingAppID == app.id ? 1.08 : 1.0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: launchingAppID
            )
        }
        .buttonStyle(.plain)
        .help(app.sourceURL.path)
    }

    private var pageIndicator: some View {
        HStack(spacing: 10) {
            ForEach(0..<pageCount, id: \.self) { index in
                Button {
                    goToPage(index)
                } label: {
                    Circle()
                        .fill(index == currentPage ? .white : .white.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(index + 1) 页")
            }
        }
        .frame(height: 24)
        .opacity(pageCount > 1 ? 1 : 0)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PageIndicatorFrameKey.self,
                    value: proxy.frame(in: .named("launchpad-window"))
                )
            }
        )
        .onPreferenceChange(PageIndicatorFrameKey.self) { frame in
            pageIndicatorFrame = frame
        }
    }

    private func loadingPlaceholder(
        _ metrics: LaunchpadGridMetrics,
        viewportSize: CGSize
    ) -> some View {
        let itemCount = min(metrics.capacity, 20)
        let placeholderRows = integerRows(in: 0..<itemCount, columns: metrics.columns)

        return ZStack(alignment: .topLeading) {
            VStack(spacing: LaunchpadGridMetrics.verticalSpacing) {
                ForEach(Array(placeholderRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: LaunchpadGridMetrics.horizontalSpacing) {
                        ForEach(row, id: \.self) { _ in
                            VStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(.white.opacity(0.07))
                                    .frame(width: 128, height: 128)

                                Capsule()
                                    .fill(.white.opacity(0.06))
                                    .frame(width: 82, height: 8)
                            }
                            .frame(
                                width: LaunchpadGridMetrics.cellWidth,
                                height: LaunchpadGridMetrics.cellHeight,
                                alignment: .top
                            )
                        }
                    }
                }
            }
            .position(
                x: viewportSize.width / 2,
                y: viewportSize.height / 2
            )
        }
        .allowsHitTesting(false)
    }

    private var emptyState: some View {
        Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未找到应用" : "没有匹配的应用")
            .font(.system(size: 17))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true

        installKeyMonitor()
        installMouseMonitor()

        let scanner = self.scanner
        Task {
            let scannedApps = await Task.detached(priority: .userInitiated) {
                scanner.scan()
            }.value

            guard !Task.isCancelled else { return }
            apps = scannedApps
            isScanning = false
            scrollPosition = 0
            prefetchIconsAroundCurrentPage()
        }

        Task {
            try? await Task.sleep(for: .milliseconds(30))
            searchFocused = true
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === NSApp.keyWindow else { return event }

            if event.keyCode == 53, contextMenu != nil {
                contextMenu = nil
                return nil
            }

            if event.keyCode == 53, deletionPrompt != nil {
                deletionPrompt = nil
                return nil
            }

            guard !blocksDismissal else { return event }

            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
               textView.hasMarkedText() {
                return event
            }

            if event.keyCode == 53 {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    NSApp.terminate(nil)
                } else {
                    query = ""
                }
                return nil
            }

            guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  pageCount > 1,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                return event
            }

            if event.keyCode == 123 {
                goToPage(currentPage - 1)
                return nil
            }

            if event.keyCode == 124 {
                goToPage(currentPage + 1)
                return nil
            }

            return event
        }
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            guard let window = event.window,
                  window === NSApp.keyWindow,
                  let contentView = window.contentView else {
                return event
            }

            let point = launchpadPoint(for: event, in: contentView)

            if event.type == .rightMouseDown {
                guard !isBusy else { return event }

                if let app = app(at: point), deletionPolicy.canDelete(app) {
                    contextMenu = AppContextMenu(app: app, location: point)
                } else {
                    contextMenu = nil
                }
                return nil
            }

            guard !blocksDismissal else { return event }

            if isClickOnInteractiveElement(point) {
                return event
            }

            NSApp.terminate(nil)
            return nil
        }
    }

    private func launchpadPoint(for event: NSEvent, in contentView: NSView) -> CGPoint {
        var point = contentView.convert(event.locationInWindow, from: nil)
        if !contentView.isFlipped {
            point.y = contentView.bounds.height - point.y
        }
        return point
    }

    private func app(at point: CGPoint) -> App? {
        let pageMetrics = metrics
        for (index, app) in currentPageApps.enumerated() {
            let itemFrame = pageMetrics.itemFrame(
                at: index,
                itemCount: currentPageApps.count
            )
            .offsetBy(dx: gridFrame.minX, dy: gridFrame.minY)

            if itemFrame.contains(point) {
                return app
            }
        }
        return nil
    }

    private func isClickOnInteractiveElement(_ point: CGPoint) -> Bool {
        if searchBarFrame.contains(point) || pageIndicatorFrame.contains(point) {
            return true
        }

        let pageMetrics = metrics
        for index in currentPageApps.indices {
            let itemFrame = pageMetrics.itemFrame(
                at: index,
                itemCount: currentPageApps.count
            )
                .offsetBy(dx: gridFrame.minX, dy: gridFrame.minY)
            if itemFrame.contains(point) {
                return true
            }
        }

        return false
    }

    private func rows<Element>(of elements: [Element], columns: Int) -> [[Element]] {
        stride(from: 0, to: elements.count, by: columns).map { start in
            Array(elements[start..<min(start + columns, elements.count)])
        }
    }

    private func integerRows(in range: Range<Int>, columns: Int) -> [[Int]] {
        stride(from: range.lowerBound, to: range.upperBound, by: columns).map { start in
            Array(start..<min(start + columns, range.upperBound))
        }
    }

    private func handleQueryChange(from oldQuery: String, to newQuery: String) {
        let oldWasEmpty = oldQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let newIsEmpty = newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if oldWasEmpty && !newIsEmpty {
            scrollPosition = 0
        } else if !oldWasEmpty && newIsEmpty {
            DispatchQueue.main.async {
                scrollPosition = AppPaging.clampedPage(
                    pageBeforeSearch,
                    itemCount: visibleApps.count,
                    capacity: metrics.capacity
                )
            }
        } else if !newIsEmpty {
            scrollPosition = 0
        }
    }

    private func clampCurrentPage() {
        let target = AppPaging.clampedPage(
            scrollPosition ?? 0,
            itemCount: visibleApps.count,
            capacity: metrics.capacity
        )
        if scrollPosition != target {
            scrollPosition = target
        }
    }

    private func goToPage(_ page: Int) {
        guard pageCount > 0 else { return }

        let target = AppPaging.clampedPage(
            page,
            itemCount: visibleApps.count,
            capacity: metrics.capacity
        )
        guard target != currentPage else { return }

        if reduceMotion {
            scrollPosition = target
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                scrollPosition = target
            }
        }
    }

    private func prefetchIconsAroundCurrentPage() {
        guard pageCount > 0 else { return }

        let currentApps = currentPageApps
        iconStore.prefetch(currentApps)

        let nextPage = currentPage + 1
        if nextPage < pageCount {
            let nextApps = Array(
                AppPaging.apps(
                    on: nextPage,
                    from: visibleApps,
                    capacity: metrics.capacity
                )
            )
            iconStore.prefetch(nextApps, priority: .utility)
        }
    }

    private func launchFirstMatch() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = trimmedQuery.isEmpty ? currentPageApps : visibleApps
        guard let first = candidates.first else { return }
        launch(first)
    }

    private func launch(_ app: App) {
        guard launchingAppID == nil, deletingAppID == nil else { return }

        launchingAppID = app.id

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: app.launchURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        NSApp.terminate(nil)
                    }
                } else {
                    launchingAppID = nil
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if launchingAppID == app.id {
                launchingAppID = nil
            }
        }
    }

    private func requestDeletion(_ app: App) {
        guard deletionPolicy.canDelete(app) else { return }

        if AppDeletionService.isRunning(app) {
            deletionPrompt = .running(app)
        } else {
            deletionPrompt = .confirmation(app)
        }
    }

    private func deleteToTrash(_ app: App) {
        guard deletingAppID == nil else { return }

        if AppDeletionService.isRunning(app) {
            deletionPrompt = .running(app)
            return
        }

        deletingAppID = app.id
        AppDeletionService.moveToTrash(app) { result in
            deletingAppID = nil

            switch result {
            case .success:
                removeApp(app)
            case .failure(let error):
                deletionPrompt = .failure(app, error.localizedDescription)
            }
        }
    }

    private func removeApp(_ app: App) {
        let pageBeforeDeletion = currentPage
        apps.removeAll { $0.id == app.id }
        iconStore.remove(app)

        DispatchQueue.main.async {
            let newPageCount = AppPaging.pageCount(
                itemCount: visibleApps.count,
                capacity: metrics.capacity
            )
            scrollPosition = newPageCount == 0 ? 0 : min(pageBeforeDeletion, newPageCount - 1)
            prefetchIconsAroundCurrentPage()
        }
    }

    private func alert(for prompt: DeletionPrompt) -> Alert {
        switch prompt {
        case .confirmation(let app):
            return Alert(
                title: Text("将“\(app.name)”移到废纸篓？"),
                message: Text("\(app.sourceURL.path)\n\n应用数据和偏好设置不会被删除。"),
                primaryButton: .destructive(Text("移到废纸篓")) {
                    deleteToTrash(app)
                },
                secondaryButton: .cancel(Text("取消"))
            )

        case .running(let app):
            return Alert(
                title: Text("无法移动“\(app.name)”"),
                message: Text("该应用正在运行。请先退出应用，再将其移到废纸篓。"),
                dismissButton: .default(Text("好"))
            )

        case .failure(let app, let reason):
            return Alert(
                title: Text("无法移动“\(app.name)”"),
                message: Text(
                    "\(reason)\n\n如果系统阻止了此操作，请在“系统设置 > 隐私与安全性 > App 管理”中允许 Launchpad，并确认当前用户有修改应用目录的权限。"
                ),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func contextMenuOverlay(_ menu: AppContextMenu) -> some View {
        AppContextMenuOverlay(
            app: menu.app,
            location: menu.location,
            onDismiss: {
                contextMenu = nil
            },
            onDelete: {
                let app = menu.app
                contextMenu = nil
                DispatchQueue.main.async {
                    requestDeletion(app)
                }
            }
        )
    }
}

private struct AppContextMenu {
    let app: App
    let location: CGPoint
}

private struct AppContextMenuOverlay: View {
    let app: App
    let location: CGPoint
    let onDismiss: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private let menuWidth: CGFloat = 204
    private let menuHeight: CGFloat = 48
    private let edgeMargin: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let origin = menuOrigin(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                Button(action: onDelete) {
                    HStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))

                        Text("移到废纸篓")
                            .font(.system(size: 13))

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isHovering ? Color.red.opacity(0.16) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: menuWidth - 8, height: menuHeight - 8)
                .padding(4)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
                .offset(x: origin.x, y: origin.y)
                .onHover { hovering in
                    isHovering = hovering
                }
                .accessibilityLabel("将“\(app.name)”移到废纸篓")
            }
        }
    }

    private func menuOrigin(in containerSize: CGSize) -> CGPoint {
        let maximumX = max(edgeMargin, containerSize.width - menuWidth - edgeMargin)
        let maximumY = max(edgeMargin, containerSize.height - menuHeight - edgeMargin)

        return CGPoint(
            x: min(max(location.x + 4, edgeMargin), maximumX),
            y: min(max(location.y + 4, edgeMargin), maximumY)
        )
    }
}

private enum DeletionPrompt: Identifiable {
    case confirmation(App)
    case running(App)
    case failure(App, String)

    var id: String {
        switch self {
        case .confirmation(let app):
            return "confirmation-\(app.id.path)"
        case .running(let app):
            return "running-\(app.id.path)"
        case .failure(let app, let reason):
            return "failure-\(app.id.path)-\(reason)"
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

private struct SearchBarFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct GridFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct PageIndicatorFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}
