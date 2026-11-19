import Foundation

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

    func itemFrame(at index: Int, itemCount: Int) -> CGRect {
        guard itemCount > 0, index >= 0, index < itemCount else { return .zero }

        let column = index % columns
        let row = index / columns
        let rowStart = row * columns
        let itemsInRow = min(columns, itemCount - rowStart)
        let rowCount = (itemCount + columns - 1) / columns
        let rowWidth = CGFloat(itemsInRow) * Self.cellWidth
            + CGFloat(itemsInRow - 1) * Self.horizontalSpacing
        let contentHeight = CGFloat(rowCount) * Self.cellHeight
            + CGFloat(rowCount - 1) * Self.verticalSpacing
        let originX = (viewportSize.width - rowWidth) / 2
        let originY = (viewportSize.height - contentHeight) / 2

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
