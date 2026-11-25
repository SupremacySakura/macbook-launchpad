import AppKit
import SwiftUI

struct ContentView: View {
    @State private var apps: [App]
    @State private var searchIndex: AppSearchIndex
    @State private var filteredApps: [App]
    @State private var query = ""
    @State private var isScanning: Bool
    @State private var didPrepare = false
    @State private var launchingAppID: App.ID?
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var searchBarFrame: CGRect = .zero
    @State private var appearanceButtonFrame: CGRect = .zero
    @State private var gridFrame: CGRect = .zero
    @State private var pageIndicatorFrame: CGRect = .zero
    @State private var gridSize: CGSize = .zero
    @State private var scrollPosition: Int? = 0
    @State private var pageBeforeSearch = 0
    @State private var dragResetToken = 0
    @State private var deletionPrompt: DeletionPrompt?
    @State private var deletingAppID: App.ID?
    @State private var contextMenu: AppContextMenu?
    @State private var hasAppeared = false
    @State private var isClosing = false
    @State private var isInitialScanInFlight = true
    @State private var isCacheDirty = false
    @State private var deletedAppIDsDuringScan: Set<App.ID> = []
    @State private var appearanceMode = LaunchpadAppearanceMode.loadSaved()
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemColorScheme

    private let iconStore: AppIconStore
    private let scanner: any AppScanner
    private let cache: any AppListCache
    private let cacheQueue: DispatchQueue
    private let safeAreaInsets: EdgeInsets
    private let onAppearanceChange: (LaunchpadAppearanceMode) -> Void
    private let deletionPolicy = AppDeletionPolicy()

    init(
        scanner: any AppScanner = FileSystemAppScanner(),
        cache: any AppListCache = FileAppListCache(),
        initialApps: [App]? = nil,
        iconStore: AppIconStore? = nil,
        safeAreaInsets: EdgeInsets = EdgeInsets(),
        onAppearanceChange: @escaping (LaunchpadAppearanceMode) -> Void = { _ in }
    ) {
        self.scanner = scanner
        self.cache = cache
        self.iconStore = iconStore ?? AppIconStore()
        self.cacheQueue = DispatchQueue(
            label: "com.supremacysakura.launchpad.app-list-cache",
            qos: .utility
        )
        self.safeAreaInsets = safeAreaInsets
        self.onAppearanceChange = onAppearanceChange

        let cachedApps = initialApps ?? cache.load()
        _apps = State(initialValue: cachedApps)
        _searchIndex = State(initialValue: AppSearchIndex(apps: cachedApps))
        _filteredApps = State(initialValue: cachedApps)
        _isScanning = State(initialValue: cachedApps.isEmpty)
        _isCacheDirty = State(initialValue: cachedApps.isEmpty)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    private var theme: LaunchpadTheme {
        LaunchpadTheme(colorScheme: appearanceMode.colorScheme ?? systemColorScheme)
    }

    private var metrics: LaunchpadGridMetrics {
        LaunchpadGridMetrics(viewportSize: gridSize)
    }

    private var pageCount: Int {
        guard gridSize.width > 0, gridSize.height > 0 else { return 0 }
        return AppPaging.pageCount(itemCount: filteredApps.count, capacity: metrics.capacity)
    }

    private var currentPage: Int {
        AppPaging.clampedPage(
            scrollPosition ?? 0,
            itemCount: filteredApps.count,
            capacity: metrics.capacity
        )
    }

    private var currentPageApps: [App] {
        Array(
            AppPaging.apps(
                on: currentPage,
                from: filteredApps,
                capacity: metrics.capacity
            )
        )
    }

    private var itemLayout: LaunchpadGridLayout {
        isSearching ? .centeredRows : .columnMajor
    }

    private var isBusy: Bool {
        deletionPrompt != nil || deletingAppID != nil || isClosing
    }

    private var blocksDismissal: Bool {
        isBusy || contextMenu != nil
    }

    private var foregroundScale: CGFloat {
        if reduceMotion { return 1 }
        return isClosing || !hasAppeared ? 0.985 : 1
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
        let currentTheme = theme

        ZStack {
            LaunchpadBackdropView(
                theme: currentTheme,
                appearance: appearanceMode.nsAppearance
            )
            .opacity(backgroundOpacity)

            if gridFrame != .zero {
                LaunchpadStageChrome(
                    stageTop: gridFrame.minY,
                    theme: currentTheme
                )
                .opacity(backgroundOpacity)
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                topBar(theme: currentTheme)
                    .padding(.top, 22 + safeAreaInsets.top)

                LaunchpadPagedGridView(
                    apps: filteredApps,
                    isScanning: isScanning,
                    isSearching: isSearching,
                    hasAnyApps: !apps.isEmpty,
                    itemLayout: itemLayout,
                    isBusy: isBusy,
                    isClosing: isClosing,
                    launchingAppID: launchingAppID,
                    resetDragToken: dragResetToken,
                    scrollPosition: $scrollPosition,
                    iconStore: iconStore,
                    theme: currentTheme,
                    reduceMotion: reduceMotion,
                    pageSettleAnimation: pageSettleAnimation,
                    onGridSizeChange: { newSize in
                        gridSize = newSize
                    },
                    onLaunch: launch,
                    onClearSearch: {
                        query = ""
                    }
                )
                .padding(.top, 16)
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

                LaunchpadPageIndicator(
                    pageCount: pageCount,
                    currentPage: currentPage,
                    theme: currentTheme,
                    reduceMotion: reduceMotion,
                    onSelectPage: goToPage
                )
                .padding(.top, 8)
                .padding(.bottom, 16 + safeAreaInsets.bottom)
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
            .padding(.leading, safeAreaInsets.leading)
            .padding(.trailing, safeAreaInsets.trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(!isBusy)
            .scaleEffect(foregroundScale)
            .opacity(foregroundOpacity)

            if let contextMenu {
                AppContextMenuOverlay(
                    app: contextMenu.app,
                    canDelete: contextMenu.canDelete,
                    location: contextMenu.location,
                    theme: currentTheme,
                    onDismiss: {
                        self.contextMenu = nil
                    },
                    onRevealInFinder: {
                        let url = contextMenu.app.sourceURL
                        self.contextMenu = nil
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    },
                    onDelete: {
                        let app = contextMenu.app
                        self.contextMenu = nil
                        DispatchQueue.main.async {
                            requestDeletion(app)
                        }
                    }
                )
                .zIndex(10)
            }
        }
        .coordinateSpace(name: "launchpad-window")
        .preferredColorScheme(appearanceMode.colorScheme)
        .onAppear(perform: prepare)
        .onChange(of: query) { oldQuery, newQuery in
            updateFilteredApps()
            handleQueryChange(from: oldQuery, to: newQuery)
        }
        .onChange(of: pageCount) { _, _ in
            clampCurrentPage()
        }
        .onChange(of: currentPage) { _, newPage in
            guard !isSearching else { return }
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

    private func topBar(theme: LaunchpadTheme) -> some View {
        ZStack {
            LaunchpadSearchBar(
                query: $query,
                matchCount: filteredApps.count,
                isSearching: isSearching,
                searchFocused: $searchFocused,
                theme: theme,
                onSubmit: launchFirstMatch,
                onClear: {
                    query = ""
                    searchFocused = true
                }
            )
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

            HStack {
                Spacer(minLength: 0)

                LaunchpadAppearanceButton(
                    mode: appearanceMode,
                    theme: theme,
                    action: toggleAppearance
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AppearanceButtonFrameKey.self,
                            value: proxy.frame(in: .named("launchpad-window"))
                        )
                    }
                )
                .onPreferenceChange(AppearanceButtonFrameKey.self) { frame in
                    appearanceButtonFrame = frame
                }
                .padding(.trailing, 28)
            }
        }
    }

    private func toggleAppearance() {
        let nextMode = appearanceMode.next
        appearanceMode = nextMode
        nextMode.save()
        onAppearanceChange(nextMode)
    }

    private func updateFilteredApps() {
        filteredApps = searchIndex.filter(query: query)
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true

        if reduceMotion {
            hasAppeared = true
        } else {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
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
            let wasInitiallyEmpty = apps.isEmpty

            if diff.hasChanges {
                for removedApp in diff.removed {
                    iconStore.remove(removedApp)
                }
                apps = reconciledApps
                searchIndex = AppSearchIndex(apps: reconciledApps)
                updateFilteredApps()
                isCacheDirty = true
                saveAppListCache()
            } else if wasInitiallyEmpty && !reconciledApps.isEmpty {
                isCacheDirty = true
                saveAppListCache()
            }

            isInitialScanInFlight = false
            deletedAppIDsDuringScan.removeAll()
            isScanning = false
            prefetchIconsAroundCurrentPage()
            iconStore.pruneDiskCache(for: reconciledApps)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(16))
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
                if !isSearching {
                    dismissLaunchpad()
                } else {
                    query = ""
                }
                return nil
            }

            guard !isSearching,
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

                if let app = app(at: point) {
                    contextMenu = AppContextMenu(
                        app: app,
                        canDelete: deletionPolicy.canDelete(app),
                        location: point
                    )
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
        guard !appearanceButtonFrame.contains(point) else { return false }
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

    private func handleQueryChange(from oldQuery: String, to newQuery: String) {
        let oldWasEmpty = oldQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let newIsEmpty = newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if oldWasEmpty && !newIsEmpty {
            dragResetToken &+= 1
            scrollPosition = 0
        } else if !oldWasEmpty && newIsEmpty {
            DispatchQueue.main.async {
                dragResetToken &+= 1
                scrollPosition = AppPaging.clampedPage(
                    pageBeforeSearch,
                    itemCount: filteredApps.count,
                    capacity: metrics.capacity
                )
            }
        } else if !newIsEmpty {
            dragResetToken &+= 1
            scrollPosition = 0
        }
    }

    private func clampCurrentPage() {
        let target = AppPaging.clampedPage(
            scrollPosition ?? 0,
            itemCount: filteredApps.count,
            capacity: metrics.capacity
        )
        if scrollPosition != target {
            dragResetToken &+= 1
            scrollPosition = target
        }
    }

    private func goToPage(_ page: Int) {
        guard pageCount > 0 else { return }

        let target = AppPaging.clampedPage(
            page,
            itemCount: filteredApps.count,
            capacity: metrics.capacity
        )
        guard target != currentPage else { return }

        dragResetToken &+= 1
        if reduceMotion {
            scrollPosition = target
        } else {
            withAnimation(pageSettleAnimation) {
                scrollPosition = target
            }
        }
    }

    private func prefetchIconsAroundCurrentPage() {
        guard pageCount > 0 else { return }

        iconStore.prefetch(currentPageApps, priority: .userInitiated)

        let nextPage = currentPage + 1
        if nextPage < pageCount {
            let nextApps = Array(
                AppPaging.apps(
                    on: nextPage,
                    from: filteredApps,
                    capacity: metrics.capacity
                )
            )
            iconStore.prefetch(nextApps, priority: .utility)
        }
    }

    private func launchFirstMatch() {
        let candidates = isSearching ? filteredApps : currentPageApps
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
        let duration: TimeInterval = reduceMotion ? 0.08 : 0.14
        withAnimation(
            reduceMotion
                ? .easeOut(duration: duration)
                : .timingCurve(0.22, 1, 0.36, 1, duration: duration)
        ) {
            isClosing = true
        }

        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            flushAppListCacheIfNeeded()
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
        searchIndex = AppSearchIndex(apps: apps)
        updateFilteredApps()
        iconStore.remove(app)
        if isInitialScanInFlight {
            deletedAppIDsDuringScan.insert(app.id)
        }
        isCacheDirty = true
        saveAppListCache()

        DispatchQueue.main.async {
            let newPageCount = AppPaging.pageCount(
                itemCount: filteredApps.count,
                capacity: metrics.capacity
            )
            dragResetToken &+= 1
            scrollPosition = newPageCount == 0 ? 0 : min(pageBeforeDeletion, newPageCount - 1)
            prefetchIconsAroundCurrentPage()
        }
    }

    private func saveAppListCache() {
        let cache = self.cache
        let apps = self.apps
        isCacheDirty = false
        cacheQueue.async {
            cache.save(apps)
        }
    }

    private func flushAppListCacheIfNeeded() {
        let shouldWrite = isCacheDirty
        let cache = self.cache
        let apps = self.apps
        isCacheDirty = false
        cacheQueue.sync {
            if shouldWrite {
                cache.save(apps)
            }
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
}

// MARK: - Stage Chrome

private struct LaunchpadStageChrome: View {
    let stageTop: CGFloat
    let theme: LaunchpadTheme

    var body: some View {
        GeometryReader { proxy in
            let stageFrame = LaunchpadPointerRegions.pagingStageFrame(
                containerSize: proxy.size,
                stageTop: stageTop
            )
            let cornerRadius: CGFloat = 36

            if stageFrame != .zero {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.stageFillTop, theme.stageFillBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [theme.stageBorderTop, theme.stageBorderBottom],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .frame(width: stageFrame.width, height: stageFrame.height)
                    .position(x: stageFrame.midX, y: stageFrame.midY)
                    .shadow(color: theme.stageShadow, radius: 28, y: 10)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Top Bar Controls

private struct LaunchpadSearchBar: View {
    @Binding var query: String
    let matchCount: Int
    let isSearching: Bool
    var searchFocused: FocusState<Bool>.Binding
    let theme: LaunchpadTheme
    let onSubmit: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(searchFocused.wrappedValue ? theme.accent : theme.searchIcon)

            TextField(
                "",
                text: $query,
                prompt: Text("搜索应用").foregroundStyle(theme.searchPlaceholder)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15.5, weight: .regular))
            .foregroundStyle(theme.searchText)
            .tint(theme.accent)
            .focused(searchFocused)
            .onSubmit(onSubmit)

            if isSearching {
                HStack(spacing: 6) {
                    Text("\(matchCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.searchBadgeText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(theme.searchBadgeFill, in: Capsule())

                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.searchIcon)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 360, height: 42)
        .background(theme.searchFill, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    searchFocused.wrappedValue ? theme.searchFocusedBorder : theme.searchBorder,
                    lineWidth: searchFocused.wrappedValue ? 1.0 : 0.75
                )
                .allowsHitTesting(false)
        )
        .shadow(
            color: searchFocused.wrappedValue ? theme.searchFocusedHalo : theme.stageShadow,
            radius: searchFocused.wrappedValue ? 16 : 14,
            y: 4
        )
        .animation(.easeOut(duration: 0.16), value: isSearching)
        .animation(.easeOut(duration: 0.16), value: searchFocused.wrappedValue)
    }
}

private struct LaunchpadAppearanceButton: View {
    let mode: LaunchpadAppearanceMode
    let theme: LaunchpadTheme
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: mode.iconName)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(theme.utilityIcon)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isHovering ? theme.itemHoverFill : theme.utilityFill)
                )
                .overlay(
                    Circle()
                        .stroke(theme.utilityBorder, lineWidth: 0.75)
                )
                .scaleEffect(isHovering ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("切换外观：\(mode.label)")
        .accessibilityLabel("切换外观，当前为\(mode.label)")
    }
}

// MARK: - Paged Grid (Isolated 120Hz Drag State)

private struct LaunchpadPagedGridView: View {
    let apps: [App]
    let isScanning: Bool
    let isSearching: Bool
    let hasAnyApps: Bool
    let itemLayout: LaunchpadGridLayout
    let isBusy: Bool
    let isClosing: Bool
    let launchingAppID: App.ID?
    let resetDragToken: Int
    @Binding var scrollPosition: Int?
    let iconStore: AppIconStore
    let theme: LaunchpadTheme
    let reduceMotion: Bool
    let pageSettleAnimation: Animation
    let onGridSizeChange: (CGSize) -> Void
    let onLaunch: (App) -> Void
    let onClearSearch: () -> Void

    @State private var pagingDragOffset: CGFloat = 0
    @State private var pagingDragStartPage = 0
    @State private var pagingDragAxis: PagingDragAxis = .undecided

    var body: some View {
        GeometryReader { proxy in
            let pageMetrics = LaunchpadGridMetrics(viewportSize: proxy.size)
            let pageCount = AppPaging.pageCount(
                itemCount: apps.count,
                capacity: pageMetrics.capacity
            )
            let currentPage = AppPaging.clampedPage(
                scrollPosition ?? 0,
                itemCount: apps.count,
                capacity: pageMetrics.capacity
            )
            let primaryMatchID = isSearching ? apps.first?.id : nil

            ZStack {
                if isScanning && !hasAnyApps {
                    LaunchpadLoadingPlaceholder(
                        metrics: pageMetrics,
                        viewportSize: proxy.size,
                        theme: theme
                    )
                } else if apps.isEmpty {
                    LaunchpadEmptyState(
                        isSearching: isSearching,
                        theme: theme,
                        onClearSearch: onClearSearch
                    )
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(0..<pageCount, id: \.self) { pageIndex in
                                let pageApps = Array(
                                    AppPaging.apps(
                                        on: pageIndex,
                                        from: apps,
                                        capacity: pageMetrics.capacity
                                    )
                                )

                                LaunchpadPageView(
                                    pageApps: pageApps,
                                    metrics: pageMetrics,
                                    viewportSize: proxy.size,
                                    layout: itemLayout,
                                    launchingAppID: launchingAppID,
                                    primaryMatchID: primaryMatchID,
                                    iconStore: iconStore,
                                    theme: theme,
                                    reduceMotion: reduceMotion,
                                    onLaunch: onLaunch
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
                            pageCount: pageCount,
                            currentPage: currentPage
                        )
                    )
                }
            }
            .onAppear {
                onGridSizeChange(proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                onGridSizeChange(newSize)
            }
            .onChange(of: resetDragToken) { _, _ in
                resetPagingDrag()
            }
        }
    }

    private func pagingDragGesture(
        pageWidth: CGFloat,
        pageCount: Int,
        currentPage: Int
    ) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { drag in
                handlePagingDragChanged(
                    drag,
                    pageWidth: pageWidth,
                    pageCount: pageCount,
                    currentPage: currentPage
                )
            }
            .onEnded { drag in
                handlePagingDragEnded(
                    drag,
                    pageWidth: pageWidth,
                    pageCount: pageCount,
                    currentPage: currentPage
                )
            }
    }

    private func handlePagingDragChanged(
        _ drag: DragGesture.Value,
        pageWidth: CGFloat,
        pageCount: Int,
        currentPage: Int
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
        pageCount: Int,
        currentPage: Int
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

    private func resetPagingDrag() {
        pagingDragAxis = .undecided
        pagingDragOffset = 0
    }
}

private struct LaunchpadPageView: View {
    let pageApps: [App]
    let metrics: LaunchpadGridMetrics
    let viewportSize: CGSize
    let layout: LaunchpadGridLayout
    let launchingAppID: App.ID?
    let primaryMatchID: App.ID?
    let iconStore: AppIconStore
    let theme: LaunchpadTheme
    let reduceMotion: Bool
    let onLaunch: (App) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(pageApps.enumerated()), id: \.element.id) { index, app in
                let frame = metrics.itemFrame(
                    at: index,
                    itemCount: pageApps.count,
                    layout: layout
                )

                AppItemView(
                    app: app,
                    slot: iconStore.slot(for: app.id),
                    isLaunching: launchingAppID == app.id,
                    isPrimarySearchMatch: primaryMatchID == app.id,
                    theme: theme,
                    reduceMotion: reduceMotion,
                    onLaunch: { onLaunch(app) }
                )
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
    }
}

// MARK: - App Item

private struct AppItemView: View {
    let app: App
    let slot: AppIconSlot
    let isLaunching: Bool
    let isPrimarySearchMatch: Bool
    let theme: LaunchpadTheme
    let reduceMotion: Bool
    let onLaunch: () -> Void

    @State private var isHovering = false

    private var tileFill: Color {
        if isHovering { return theme.itemHoverFill }
        if isPrimarySearchMatch { return theme.itemPrimaryMatchFill }
        return .clear
    }

    private var tileBorder: Color {
        if isHovering { return theme.itemHoverBorder }
        if isPrimarySearchMatch { return theme.itemPrimaryMatchBorder }
        return .clear
    }

    var body: some View {
        Button(action: onLaunch) {
            VStack(spacing: 10) {
                ZStack {
                    if let cgImage = slot.image {
                        Image(decorative: cgImage, scale: slot.scale)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: AppIconStore.iconPointSize, height: AppIconStore.iconPointSize)
                            .shadow(
                                color: theme.isDark
                                    ? Color.black.opacity(0.28)
                                    : Color.black.opacity(0.10),
                                radius: 8,
                                y: 4
                            )
                            .transition(.opacity)
                    } else {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(theme.placeholderFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(theme.placeholderBorder, lineWidth: 0.75)
                            )
                            .frame(width: AppIconStore.iconPointSize, height: AppIconStore.iconPointSize)
                    }
                }
                .frame(width: AppIconStore.iconPointSize, height: AppIconStore.iconPointSize)
                .scaleEffect(isLaunching ? 1.07 : (isHovering && !reduceMotion ? 1.04 : 1.0))
                .offset(y: isHovering && !reduceMotion ? -2 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: slot.image != nil)

                Text(app.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.itemLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 136)
                    .shadow(
                        color: theme.itemLabelShadow,
                        radius: theme.isDark ? 2 : 0,
                        y: theme.isDark ? 1 : 0
                    )
            }
            .padding(.top, 12)
            .frame(
                width: LaunchpadGridMetrics.cellWidth,
                height: LaunchpadGridMetrics.cellHeight,
                alignment: .top
            )
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(tileFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(tileBorder, lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .scaleEffect(isLaunching && !reduceMotion ? 1.03 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isLaunching)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(app.sourceURL.path)
    }
}

// MARK: - Morphing Page Indicator

private struct LaunchpadPageIndicator: View {
    let pageCount: Int
    let currentPage: Int
    let theme: LaunchpadTheme
    let reduceMotion: Bool
    let onSelectPage: (Int) -> Void

    @State private var hoveredPage: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<pageCount, id: \.self) { index in
                let isCurrent = index == currentPage
                let isHovered = hoveredPage == index

                Button {
                    onSelectPage(index)
                } label: {
                    Capsule(style: .continuous)
                        .fill(
                            isCurrent
                                ? theme.indicatorActive
                                : (isHovered ? theme.indicatorHover : theme.indicatorInactive)
                        )
                        .frame(width: isCurrent ? 22 : 6, height: 6)
                        .frame(width: isCurrent ? 28 : 18, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredPage = hovering ? index : (hoveredPage == index ? nil : hoveredPage)
                }
                .accessibilityLabel("第 \(index + 1) 页")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(theme.indicatorPillFill, in: Capsule())
        .overlay(
            Capsule()
                .stroke(theme.indicatorPillBorder, lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .animation(
            reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.26),
            value: currentPage
        )
        .opacity(pageCount > 1 ? 1 : 0)
        .allowsHitTesting(pageCount > 1)
    }
}

// MARK: - Loading & Empty States

private struct LaunchpadLoadingPlaceholder: View {
    let metrics: LaunchpadGridMetrics
    let viewportSize: CGSize
    let theme: LaunchpadTheme

    var body: some View {
        let itemCount = min(metrics.capacity, 20)
        let placeholderRows = stride(from: 0, to: itemCount, by: metrics.columns).map { start in
            Array(start..<min(start + metrics.columns, itemCount))
        }

        ZStack(alignment: .topLeading) {
            VStack(spacing: LaunchpadGridMetrics.verticalSpacing) {
                ForEach(Array(placeholderRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: LaunchpadGridMetrics.horizontalSpacing) {
                        ForEach(row, id: \.self) { _ in
                            VStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(theme.placeholderFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .stroke(theme.placeholderBorder, lineWidth: 0.75)
                                    )
                                    .frame(
                                        width: AppIconStore.iconPointSize,
                                        height: AppIconStore.iconPointSize
                                    )

                                Capsule()
                                    .fill(theme.placeholderFill)
                                    .frame(width: 72, height: 8)
                            }
                            .padding(.top, 12)
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
}

private struct LaunchpadEmptyState: View {
    let isSearching: Bool
    let theme: LaunchpadTheme
    let onClearSearch: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "square.grid.2x2")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(theme.searchIcon)
                .frame(width: 56, height: 56)
                .background(theme.searchFill, in: Circle())
                .overlay(
                    Circle()
                        .stroke(theme.searchBorder, lineWidth: 0.75)
                )

            Text(isSearching ? "未找到匹配应用" : "未找到应用")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.itemLabel)

            if isSearching {
                Button(action: onClearSearch) {
                    Text("按 Esc 清空搜索")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.searchPlaceholder)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Context Menu

private struct AppContextMenu {
    let app: App
    let canDelete: Bool
    let location: CGPoint
}

private struct AppContextMenuOverlay: View {
    let app: App
    let canDelete: Bool
    let location: CGPoint
    let theme: LaunchpadTheme
    let onDismiss: () -> Void
    let onRevealInFinder: () -> Void
    let onDelete: () -> Void

    @State private var hoveredAction: MenuAction?

    private enum MenuAction {
        case reveal
        case delete
    }

    private let menuWidth: CGFloat = 212
    private var menuHeight: CGFloat {
        canDelete ? 106 : 68
    }
    private let edgeMargin: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let origin = menuOrigin(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.menuSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                        .padding(.bottom, 2)

                    Button(action: onRevealInFinder) {
                        HStack(spacing: 9) {
                            Image(systemName: "folder")
                                .font(.system(size: 13, weight: .medium))
                            Text("在访达中显示")
                                .font(.system(size: 13))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(theme.menuText)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(hoveredAction == .reveal ? theme.menuHoverFill : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredAction = hovering ? .reveal : (hoveredAction == .reveal ? nil : hoveredAction)
                    }

                    if canDelete {
                        Rectangle()
                            .fill(theme.menuDivider)
                            .frame(height: 1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)

                        Button(action: onDelete) {
                            HStack(spacing: 9) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .medium))
                                Text("移到废纸篓")
                                    .font(.system(size: 13))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(theme.menuDestructive)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(hoveredAction == .delete ? theme.menuDestructiveHoverFill : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredAction = hovering ? .delete : (hoveredAction == .delete ? nil : hoveredAction)
                        }
                        .accessibilityLabel("将“\(app.name)”移到废纸篓")
                    }
                }
                .padding(6)
                .frame(width: menuWidth, alignment: .leading)
                .background(
                    theme.menuFill,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.menuBorder, lineWidth: 0.75)
                )
                .shadow(color: theme.menuShadow, radius: 22, y: 10)
                .offset(x: origin.x, y: origin.y)
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

// MARK: - Supporting Types

private enum PagingDragAxis {
    case undecided
    case horizontal
    case vertical
    case blocked
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

private struct SearchBarFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct AppearanceButtonFrameKey: PreferenceKey {
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
