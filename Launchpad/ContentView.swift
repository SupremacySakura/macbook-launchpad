import AppKit
import SwiftUI

struct ContentView: View {
    @State private var apps: [App]
    @State private var query = ""
    @State private var isScanning: Bool
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
    @State private var pagingDragOffset: CGFloat = 0
    @State private var pagingDragStartPage = 0
    @State private var pagingDragAxis: PagingDragAxis = .undecided
    @State private var deletionPrompt: DeletionPrompt?
    @State private var deletingAppID: App.ID?
    @State private var contextMenu: AppContextMenu?
    @State private var hasAppeared = false
    @State private var isClosing = false
    @State private var isInitialScanInFlight = true
    @State private var deletedAppIDsDuringScan: Set<App.ID> = []
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var iconStore = AppIconStore()

    private let scanner: any AppScanner
    private let cache: any AppListCache
    private let cacheQueue: DispatchQueue
    private let safeAreaInsets: EdgeInsets
    private let deletionPolicy = AppDeletionPolicy()

    init(
        scanner: any AppScanner = FileSystemAppScanner(),
        cache: any AppListCache = FileAppListCache(),
        safeAreaInsets: EdgeInsets = EdgeInsets()
    ) {
        self.scanner = scanner
        self.cache = cache
        self.cacheQueue = DispatchQueue(
            label: "com.supremacysakura.launchpad.app-list-cache",
            qos: .utility
        )
        self.safeAreaInsets = safeAreaInsets

        let cachedApps = cache.load()
        _apps = State(initialValue: cachedApps)
        _isScanning = State(initialValue: cachedApps.isEmpty)
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

    private var itemLayout: LaunchpadGridLayout {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .columnMajor
            : .centeredRows
    }

    private var isBusy: Bool {
        deletionPrompt != nil || deletingAppID != nil || isClosing
    }

    private var blocksDismissal: Bool {
        isBusy || contextMenu != nil
    }

    private var foregroundScale: CGFloat {
        if reduceMotion { return 1 }
        return isClosing || !hasAppeared ? 0.992 : 1
    }

    private var foregroundOpacity: Double {
        isClosing ? 0 : 1
    }

    private var backgroundOpacity: Double {
        isClosing ? 0 : 1
    }

    private var pageSettleAnimation: Animation {
        .timingCurve(
            0.22,
            1,
            0.36,
            1,
            duration: LaunchpadPagingMotion.settleDuration
        )
    }

    var body: some View {
        ZStack {
            LaunchpadBackground()
                .opacity(backgroundOpacity)

            if gridFrame != .zero {
                pagingRegionChrome
                    .opacity(backgroundOpacity)
                    .allowsHitTesting(false)
            }

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
            .scaleEffect(foregroundScale)
            .opacity(foregroundOpacity)

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

    private var pagingRegionChrome: some View {
        GeometryReader { proxy in
            let stageFrame = LaunchpadPointerRegions.pagingStageFrame(
                containerSize: proxy.size,
                stageTop: gridFrame.minY
            )
            let cornerRadius: CGFloat = 42

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                LaunchpadPalette.stage.opacity(0.92),
                                LaunchpadPalette.midnight.opacity(0.88),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: stageFrame.width, height: stageFrame.height)
                    .position(x: stageFrame.midX, y: stageFrame.midY)
                    .shadow(color: .black.opacity(0.48), radius: 34, y: 18)

                DismissBandShape(
                    stageFrame: stageFrame,
                    cornerRadius: cornerRadius
                )
                .fill(
                    LinearGradient(
                        colors: [
                            LaunchpadPalette.exitBand.opacity(0.52),
                            LaunchpadPalette.deepest.opacity(0.78),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: FillStyle(eoFill: true)
                )

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                LaunchpadPalette.mint.opacity(0.34),
                                LaunchpadPalette.electricBlue.opacity(0.52),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: stageFrame.width, height: stageFrame.height)
                    .position(x: stageFrame.midX, y: stageFrame.midY)
            }
        }
        .transition(.opacity)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LaunchpadPalette.frost.opacity(0.58))

            TextField("搜索", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .tint(LaunchpadPalette.mint)
                .focused($searchFocused)
                .onSubmit(launchFirstMatch)
        }
        .padding(.horizontal, 18)
        .frame(width: 340, height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .fill(LaunchpadPalette.frost.opacity(0.045))
                .allowsHitTesting(false)
        )
        .overlay(
            Capsule()
                .stroke(
                    searchFocused
                        ? LaunchpadPalette.electricBlue.opacity(0.62)
                        : LaunchpadPalette.frost.opacity(0.14),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
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
                        .offset(x: pagingDragOffset)
                    }
                    .scrollIndicators(.never)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrollPosition)
                    .defaultScrollAnchor(.leading)
                    .highPriorityGesture(
                        pagingDragGesture(
                            pageWidth: proxy.size.width,
                            pageCount: pageItems
                        )
                    )
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
        metrics: LaunchpadGridMetrics,
        viewportSize: CGSize
    ) -> some View {
        let layout = itemLayout

        return ZStack(alignment: .topLeading) {
            ForEach(Array(pageApps.enumerated()), id: \.element.id) { index, app in
                let frame = metrics.itemFrame(
                    at: index,
                    itemCount: pageApps.count,
                    layout: layout
                )

                appItem(app)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
    }

    private func appItem(_ app: App) -> some View {
        let icon = iconStore.icons[app.id]

        return Button {
            launch(app)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LaunchpadPalette.frost.opacity(0.065))
                        .frame(width: 128, height: 128)
                        .overlay {
                            Image(systemName: "app.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(LaunchpadPalette.frost.opacity(0.22))
                        }
                        .opacity(icon == nil ? 1 : 0)

                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 128, height: 128)
                            .shadow(color: .black.opacity(0.24), radius: 7, y: 5)
                            .transition(.opacity)
                    }
                }
                .frame(width: 128, height: 128)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.16),
                    value: icon != nil
                )

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
                        .fill(
                            index == currentPage
                                ? LaunchpadPalette.mint
                                : LaunchpadPalette.frost.opacity(0.24)
                        )
                        .frame(width: 8, height: 8)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(index + 1) 页")
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.30),
            value: currentPage
        )
        .frame(height: 24)
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
        .opacity(pageCount > 1 ? 1 : 0)
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
                                    .fill(LaunchpadPalette.frost.opacity(0.055))
                                    .frame(width: 128, height: 128)

                                Capsule()
                                    .fill(LaunchpadPalette.frost.opacity(0.045))
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

        if reduceMotion {
            hasAppeared = true
        } else {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.26)) {
                hasAppeared = true
            }
        }

        installKeyMonitor()
        installMouseMonitor()

        let scanner = self.scanner
        Task {
            let scannedApps = await Task.detached(priority: .userInitiated) {
                scanner.scan()
            }.value

            guard !Task.isCancelled else { return }

            let reconciledApps = scannedApps.filter {
                !deletedAppIDsDuringScan.contains($0.id)
            }
            let diff = AppListDiff.between(cached: apps, scanned: reconciledApps)
            if diff.hasChanges {
                for removedApp in diff.removed {
                    iconStore.remove(removedApp)
                }
                apps = reconciledApps
            }

            isInitialScanInFlight = false
            deletedAppIDsDuringScan.removeAll()
            saveAppListCache()
            isScanning = false
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

            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "q" {
                dismissLaunchpad()
                return nil
            }

            guard !isClosing else { return nil }

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
                    dismissLaunchpad()
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
            let containerSize = contentView.bounds.size

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

            if shouldDismiss(from: point, in: containerSize) {
                dismissLaunchpad()
                return nil
            }

            return event
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
                itemCount: currentPageApps.count,
                layout: itemLayout
            )
            .offsetBy(dx: gridFrame.minX, dy: gridFrame.minY)

            if itemFrame.contains(point) {
                return app
            }
        }
        return nil
    }

    private func shouldDismiss(from point: CGPoint, in containerSize: CGSize) -> Bool {
        guard gridFrame != .zero else { return false }
        guard !searchBarFrame.contains(point) else { return false }
        if pageCount > 1, pageIndicatorFrame.contains(point) {
            return false
        }
        guard app(at: point) == nil else { return false }

        return !LaunchpadPointerRegions.isInPagingStage(
            point,
            containerSize: containerSize,
            stageTop: gridFrame.minY
        )
    }

    private func pagingDragGesture(pageWidth: CGFloat, pageCount: Int) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { drag in
                handlePagingDragChanged(
                    drag,
                    pageWidth: pageWidth,
                    pageCount: pageCount
                )
            }
            .onEnded { drag in
                handlePagingDragEnded(
                    drag,
                    pageWidth: pageWidth,
                    pageCount: pageCount
                )
            }
    }

    private func handlePagingDragChanged(
        _ drag: DragGesture.Value,
        pageWidth: CGFloat,
        pageCount: Int
    ) {
        guard !isBusy, !isClosing, pageWidth > 0 else { return }

        if pagingDragAxis == .undecided {
            let startX = drag.startLocation.x
            guard startX >= LaunchpadPointerRegions.sideBandWidth,
                  startX <= pageWidth - LaunchpadPointerRegions.sideBandWidth else {
                pagingDragAxis = .blocked
                return
            }

            guard LaunchpadPagingMotion.hasHorizontalIntent(drag.translation) else {
                pagingDragAxis = .vertical
                return
            }

            pagingDragStartPage = currentPage
            pagingDragAxis = .horizontal
        }

        guard pagingDragAxis == .horizontal else { return }

        pagingDragOffset = LaunchpadPagingMotion.displayedOffset(
            translation: drag.translation,
            startPage: pagingDragStartPage,
            pageCount: pageCount,
            pageWidth: pageWidth
        )
    }

    private func handlePagingDragEnded(
        _ drag: DragGesture.Value,
        pageWidth: CGFloat,
        pageCount: Int
    ) {
        let wasHorizontal = pagingDragAxis == .horizontal
        pagingDragAxis = .undecided

        guard wasHorizontal, !isBusy, !isClosing else {
            pagingDragOffset = 0
            return
        }

        let target = LaunchpadPagingMotion.targetPage(
            startPage: pagingDragStartPage,
            translation: drag.translation,
            predictedEndTranslation: drag.predictedEndTranslation,
            pageCount: pageCount,
            pageWidth: pageWidth
        )

        if reduceMotion {
            scrollPosition = target
            pagingDragOffset = 0
        } else if target != currentPage {
            withAnimation(pageSettleAnimation) {
                scrollPosition = target
                pagingDragOffset = 0
            }
        } else {
            withAnimation(pageSettleAnimation) {
                pagingDragOffset = 0
            }
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
            resetPagingDrag()
            scrollPosition = 0
        } else if !oldWasEmpty && newIsEmpty {
            DispatchQueue.main.async {
                resetPagingDrag()
                scrollPosition = AppPaging.clampedPage(
                    pageBeforeSearch,
                    itemCount: visibleApps.count,
                    capacity: metrics.capacity
                )
            }
        } else if !newIsEmpty {
            resetPagingDrag()
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
            resetPagingDrag()
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

        resetPagingDrag()
        if reduceMotion {
            scrollPosition = target
        } else {
            withAnimation(pageSettleAnimation) {
                scrollPosition = target
            }
        }
    }

    private func resetPagingDrag() {
        pagingDragAxis = .undecided
        pagingDragOffset = 0
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
        guard launchingAppID == nil, deletingAppID == nil, !isClosing else { return }

        launchingAppID = app.id

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: app.launchURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    dismissLaunchpad()
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

    private func dismissLaunchpad() {
        guard !isClosing else { return }

        contextMenu = nil
        let duration: TimeInterval = reduceMotion ? 0.12 : 0.20
        withAnimation(
            reduceMotion
                ? .easeOut(duration: duration)
                : .timingCurve(0.23, 1, 0.32, 1, duration: duration)
        ) {
            isClosing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            flushAppListCache()
            NSApp.terminate(nil)
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
        if isInitialScanInFlight {
            deletedAppIDsDuringScan.insert(app.id)
        }
        saveAppListCache()

        DispatchQueue.main.async {
            let newPageCount = AppPaging.pageCount(
                itemCount: visibleApps.count,
                capacity: metrics.capacity
            )
            resetPagingDrag()
            scrollPosition = newPageCount == 0 ? 0 : min(pageBeforeDeletion, newPageCount - 1)
            prefetchIconsAroundCurrentPage()
        }
    }

    private func saveAppListCache() {
        let cache = self.cache
        let apps = self.apps
        cacheQueue.async {
            cache.save(apps)
        }
    }

    private func flushAppListCache() {
        let cache = self.cache
        let apps = self.apps
        cacheQueue.sync {
            cache.save(apps)
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

private enum PagingDragAxis {
    case undecided
    case horizontal
    case vertical
    case blocked
}

private struct DismissBandShape: Shape {
    let stageFrame: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: stageFrame,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )
        return path
    }
}

private enum LaunchpadPalette {
    static let deepest = Color(red: 0.006, green: 0.011, blue: 0.027)
    static let ink = Color(red: 0.016, green: 0.035, blue: 0.075)
    static let midnight = Color(red: 0.020, green: 0.071, blue: 0.137)
    static let stage = Color(red: 0.024, green: 0.137, blue: 0.153)
    static let exitBand = Color(red: 0.020, green: 0.071, blue: 0.235)
    static let electricBlue = Color(red: 0.16, green: 0.44, blue: 1.00)
    static let mint = Color(red: 0.39, green: 0.98, blue: 0.80)
    static let frost = Color(red: 0.74, green: 0.90, blue: 1.00)
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

private struct LaunchpadBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()

            LinearGradient(
                stops: [
                    .init(
                        color: LaunchpadPalette.midnight.opacity(0.76),
                        location: 0
                    ),
                    .init(
                        color: LaunchpadPalette.ink.opacity(0.89),
                        location: 0.46
                    ),
                    .init(
                        color: LaunchpadPalette.deepest.opacity(0.96),
                        location: 1
                    ),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    LaunchpadPalette.electricBlue.opacity(0.28),
                    .clear,
                ],
                center: UnitPoint(x: 0.88, y: 0.08),
                startRadius: 0,
                endRadius: 920
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    LaunchpadPalette.mint.opacity(0.09),
                    .clear,
                ],
                center: UnitPoint(x: 0.04, y: 0.94),
                startRadius: 0,
                endRadius: 720
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    .white.opacity(0.035),
                    .clear,
                    .black.opacity(0.24),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    .clear,
                    .black.opacity(0.34),
                ],
                center: .center,
                startRadius: 420,
                endRadius: 1220
            )
        }
        .ignoresSafeArea()
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
