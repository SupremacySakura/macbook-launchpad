import Foundation

enum LaunchpadGridLayout {
    case columnMajor
    case centeredRows
}

struct LaunchpadGridMetrics: Equatable {
    static let cellWidth: CGFloat = 152
    static let cellHeight: CGFloat = 152
    static let horizontalSpacing: CGFloat = 24
    static let verticalSpacing: CGFloat = 8
    static let maximumColumns = 8
    static let maximumRows = 5

    let viewportSize: CGSize
    let columns: Int
    let rows: Int

    init(viewportSize: CGSize) {
        self.viewportSize = viewportSize

        let horizontalPadding: CGFloat = 80
        let usableWidth = max(0, viewportSize.width - horizontalPadding)
        let calculatedColumns = Int(
            floor((usableWidth + Self.horizontalSpacing) / (Self.cellWidth + Self.horizontalSpacing))
        )
        self.columns = min(Self.maximumColumns, max(1, calculatedColumns))

        let calculatedRows = Int(
            floor((viewportSize.height + Self.verticalSpacing) / (Self.cellHeight + Self.verticalSpacing))
        )
        self.rows = min(Self.maximumRows, max(1, calculatedRows))
    }

    var capacity: Int {
        columns * rows
    }

    var gridSize: CGSize {
        CGSize(
            width: CGFloat(columns) * Self.cellWidth + CGFloat(columns - 1) * Self.horizontalSpacing,
            height: CGFloat(rows) * Self.cellHeight + CGFloat(rows - 1) * Self.verticalSpacing
        )
    }

    var topInset: CGFloat {
        max(0, (viewportSize.height - gridSize.height) / 2)
    }

    func itemFrame(
        at index: Int,
        itemCount: Int,
        layout: LaunchpadGridLayout = .columnMajor
    ) -> CGRect {
        guard itemCount > 0, index >= 0, index < itemCount else { return .zero }

        let column: Int
        let row: Int
        let originX: CGFloat
        let originY: CGFloat

        switch layout {
        case .columnMajor:
            column = index / rows
            row = index % rows
            originX = (viewportSize.width - gridSize.width) / 2
            originY = topInset

        case .centeredRows:
            column = index % columns
            row = index / columns
            let rowStart = row * columns
            let itemsInRow = min(columns, itemCount - rowStart)
            let rowCount = (itemCount + columns - 1) / columns
            let rowWidth = CGFloat(itemsInRow) * Self.cellWidth
                + CGFloat(itemsInRow - 1) * Self.horizontalSpacing
            let contentHeight = CGFloat(rowCount) * Self.cellHeight
                + CGFloat(rowCount - 1) * Self.verticalSpacing
            originX = (viewportSize.width - rowWidth) / 2
            originY = (viewportSize.height - contentHeight) / 2
        }

        return CGRect(
            x: originX + CGFloat(column) * (Self.cellWidth + Self.horizontalSpacing),
            y: originY + CGFloat(row) * (Self.cellHeight + Self.verticalSpacing),
            width: Self.cellWidth,
            height: Self.cellHeight
        )
    }
}

enum AppPaging {
    static func pageCount(itemCount: Int, capacity: Int) -> Int {
        guard itemCount > 0, capacity > 0 else { return 0 }
        return (itemCount + capacity - 1) / capacity
    }

    static func clampedPage(_ page: Int, itemCount: Int, capacity: Int) -> Int {
        let count = pageCount(itemCount: itemCount, capacity: capacity)
        guard count > 0 else { return 0 }
        return min(max(page, 0), count - 1)
    }

    static func apps(on page: Int, from apps: [App], capacity: Int) -> ArraySlice<App> {
        guard capacity > 0, !apps.isEmpty else { return [] }

        let start = min(max(page, 0) * capacity, apps.count)
        let end = min(start + capacity, apps.count)
        return apps[start..<end]
    }
}

enum LaunchpadPointerRegions {
    static let sideBandWidth: CGFloat = 56
    static let bottomBandHeight: CGFloat = 64

    static func pagingStageFrame(
        containerSize: CGSize,
        stageTop: CGFloat
    ) -> CGRect {
        let width = containerSize.width - sideBandWidth * 2
        let height = containerSize.height - bottomBandHeight - stageTop
        guard width > 0, height > 0 else { return .zero }

        return CGRect(
            x: sideBandWidth,
            y: stageTop,
            width: width,
            height: height
        )
    }

    static func isInPagingStage(
        _ point: CGPoint,
        containerSize: CGSize,
        stageTop: CGFloat
    ) -> Bool {
        pagingStageFrame(
            containerSize: containerSize,
            stageTop: stageTop
        ).contains(point)
    }
}

enum LaunchpadPagingMotion {
    static let settleDuration: TimeInterval = 0.40
    static let horizontalDominanceRatio: CGFloat = 1.2
    static let edgeResistance: CGFloat = 0.28

    static func hasHorizontalIntent(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * horizontalDominanceRatio
    }

    static func displayedOffset(
        translation: CGSize,
        startPage: Int,
        pageCount: Int,
        pageWidth: CGFloat
    ) -> CGFloat {
        guard pageWidth > 0, hasHorizontalIntent(translation) else { return 0 }
        guard availableTargetPage(
            from: startPage,
            translationWidth: translation.width,
            pageCount: pageCount
        ) != nil else {
            return translation.width * edgeResistance
        }

        let magnitude = abs(translation.width)
        guard magnitude > pageWidth else { return translation.width }

        let resistedMagnitude = pageWidth + (magnitude - pageWidth) * edgeResistance
        return translation.width < 0 ? -resistedMagnitude : resistedMagnitude
    }

    static func targetPage(
        startPage: Int,
        translation: CGSize,
        predictedEndTranslation: CGSize,
        pageCount: Int,
        pageWidth: CGFloat
    ) -> Int {
        guard pageWidth > 0, hasHorizontalIntent(translation) else { return startPage }
        guard let target = availableTargetPage(
            from: startPage,
            translationWidth: translation.width,
            pageCount: pageCount
        ) else {
            return startPage
        }

        let distanceThreshold = min(max(pageWidth * 0.16, 84), 180)
        let projectedThreshold = min(max(pageWidth * 0.24, 120), 260)
        let distancePassed = abs(translation.width) >= distanceThreshold
        let projectedPassed = abs(predictedEndTranslation.width) >= projectedThreshold
            && hasSameDirection(predictedEndTranslation.width, translation.width)

        return distancePassed || projectedPassed ? target : startPage
    }

    private static func availableTargetPage(
        from startPage: Int,
        translationWidth: CGFloat,
        pageCount: Int
    ) -> Int? {
        guard pageCount > 1, translationWidth != 0 else { return nil }

        let direction = translationWidth < 0 ? 1 : -1
        let target = startPage + direction
        return (0..<pageCount).contains(target) ? target : nil
    }

    private static func hasSameDirection(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        (lhs < 0 && rhs < 0) || (lhs > 0 && rhs > 0)
    }
}
