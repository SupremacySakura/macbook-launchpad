import XCTest

final class AppPaginationTests: XCTestCase {
    func testComputesAdaptiveGridFromViewport() {
        let compact = LaunchpadGridMetrics(viewportSize: CGSize(width: 1440, height: 760))
        XCTAssertEqual(compact.columns, 7)
        XCTAssertEqual(compact.rows, 4)
        XCTAssertEqual(compact.capacity, 28)

        let roomy = LaunchpadGridMetrics(viewportSize: CGSize(width: 1512, height: 844))
        XCTAssertEqual(roomy.columns, 8)
        XCTAssertEqual(roomy.rows, 5)
        XCTAssertEqual(roomy.capacity, 40)
    }

    func testComputesPageCountAndClampsPage() {
        XCTAssertEqual(AppPaging.pageCount(itemCount: 0, capacity: 40), 0)
        XCTAssertEqual(AppPaging.pageCount(itemCount: 1, capacity: 40), 1)
        XCTAssertEqual(AppPaging.pageCount(itemCount: 41, capacity: 40), 2)

        XCTAssertEqual(AppPaging.clampedPage(9, itemCount: 41, capacity: 40), 1)
        XCTAssertEqual(AppPaging.clampedPage(-1, itemCount: 41, capacity: 40), 0)
    }

    func testSlicesItemsForPage() {
        let apps = (0..<41).map(makeApp)

        XCTAssertEqual(
            AppPaging.apps(on: 0, from: apps, capacity: 40).map(\.name).count,
            40
        )
        XCTAssertEqual(
            AppPaging.apps(on: 1, from: apps, capacity: 40).map(\.name),
            ["App 40"]
        )
    }

    func testColumnMajorFramesFillDownThenRight() {
        let metrics = LaunchpadGridMetrics(viewportSize: CGSize(width: 1440, height: 760))
        let first = metrics.itemFrame(
            at: 0,
            itemCount: metrics.capacity,
            layout: .columnMajor
        )
        let second = metrics.itemFrame(
            at: 1,
            itemCount: metrics.capacity,
            layout: .columnMajor
        )
        let secondColumn = metrics.itemFrame(
            at: metrics.rows,
            itemCount: metrics.capacity,
            layout: .columnMajor
        )
        let expectedOriginX = (1440 - metrics.gridSize.width) / 2

        XCTAssertEqual(first.minX, expectedOriginX, accuracy: 0.001)
        XCTAssertEqual(first.minY, metrics.topInset, accuracy: 0.001)
        XCTAssertEqual(second.minX, expectedOriginX, accuracy: 0.001)
        XCTAssertEqual(
            second.minY,
            metrics.topInset + LaunchpadGridMetrics.cellHeight + LaunchpadGridMetrics.verticalSpacing,
            accuracy: 0.001
        )
        XCTAssertEqual(
            secondColumn.minX,
            expectedOriginX + LaunchpadGridMetrics.cellWidth + LaunchpadGridMetrics.horizontalSpacing,
            accuracy: 0.001
        )
        XCTAssertEqual(secondColumn.minY, metrics.topInset, accuracy: 0.001)
    }

    func testCenteredRowsLayoutCentersSingleResult() {
        let metrics = LaunchpadGridMetrics(viewportSize: CGSize(width: 1440, height: 760))
        let frame = metrics.itemFrame(
            at: 0,
            itemCount: 1,
            layout: .centeredRows
        )

        XCTAssertEqual(frame.midX, 720, accuracy: 0.001)
        XCTAssertEqual(frame.midY, 380, accuracy: 0.001)
    }

    func testColumnMajorSparsePageStartsAtGridOrigin() {
        let metrics = LaunchpadGridMetrics(viewportSize: CGSize(width: 1440, height: 760))
        let frame = metrics.itemFrame(
            at: 0,
            itemCount: 1,
            layout: .columnMajor
        )

        XCTAssertEqual(
            frame.minX,
            (1440 - metrics.gridSize.width) / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(frame.minY, metrics.topInset, accuracy: 0.001)
    }

    func testPagingStageExcludesAllFourOuterBands() {
        let containerSize = CGSize(width: 1440, height: 900)
        let stageTop: CGFloat = 120
        let stageFrame = LaunchpadPointerRegions.pagingStageFrame(
            containerSize: containerSize,
            stageTop: stageTop
        )

        XCTAssertEqual(stageFrame.minX, 56, accuracy: 0.001)
        XCTAssertEqual(stageFrame.maxX, 1384, accuracy: 0.001)
        XCTAssertEqual(stageFrame.minY, stageTop, accuracy: 0.001)
        XCTAssertEqual(stageFrame.maxY, 836, accuracy: 0.001)

        XCTAssertTrue(
            LaunchpadPointerRegions.isInPagingStage(
                CGPoint(x: 720, y: 500),
                containerSize: containerSize,
                stageTop: stageTop
            )
        )
        XCTAssertFalse(
            LaunchpadPointerRegions.isInPagingStage(
                CGPoint(x: 20, y: 500),
                containerSize: containerSize,
                stageTop: stageTop
            )
        )
        XCTAssertFalse(
            LaunchpadPointerRegions.isInPagingStage(
                CGPoint(x: 1420, y: 500),
                containerSize: containerSize,
                stageTop: stageTop
            )
        )
        XCTAssertFalse(
            LaunchpadPointerRegions.isInPagingStage(
                CGPoint(x: 720, y: 110),
                containerSize: containerSize,
                stageTop: stageTop
            )
        )
        XCTAssertFalse(
            LaunchpadPointerRegions.isInPagingStage(
                CGPoint(x: 720, y: 850),
                containerSize: containerSize,
                stageTop: stageTop
            )
        )
    }

    func testPagingOffsetFollowsPointerAndResistsAtBounds() {
        let middle = LaunchpadPagingMotion.displayedOffset(
            translation: CGSize(width: -140, height: 4),
            startPage: 1,
            pageCount: 3,
            pageWidth: 1440
        )
        let firstPageEdge = LaunchpadPagingMotion.displayedOffset(
            translation: CGSize(width: 100, height: 2),
            startPage: 0,
            pageCount: 3,
            pageWidth: 1440
        )

        XCTAssertEqual(middle, -140, accuracy: 0.001)
        XCTAssertEqual(firstPageEdge, 28, accuracy: 0.001)
    }

    func testPagingTargetUsesDistanceOrVelocity() {
        let pageWidth: CGFloat = 1000

        XCTAssertEqual(
            LaunchpadPagingMotion.targetPage(
                startPage: 0,
                translation: CGSize(width: -170, height: 4),
                predictedEndTranslation: CGSize(width: -180, height: 4),
                pageCount: 3,
                pageWidth: pageWidth
            ),
            1
        )
        XCTAssertEqual(
            LaunchpadPagingMotion.targetPage(
                startPage: 0,
                translation: CGSize(width: -30, height: 2),
                predictedEndTranslation: CGSize(width: -280, height: 2),
                pageCount: 3,
                pageWidth: pageWidth
            ),
            1
        )
        XCTAssertEqual(
            LaunchpadPagingMotion.targetPage(
                startPage: 0,
                translation: CGSize(width: -30, height: 2),
                predictedEndTranslation: CGSize(width: 20, height: 2),
                pageCount: 3,
                pageWidth: pageWidth
            ),
            0
        )
        XCTAssertEqual(
            LaunchpadPagingMotion.targetPage(
                startPage: 0,
                translation: CGSize(width: 300, height: 2),
                predictedEndTranslation: CGSize(width: 420, height: 2),
                pageCount: 3,
                pageWidth: pageWidth
            ),
            0
        )
    }

    private func makeApp(_ index: Int) -> App {
        let url = URL(fileURLWithPath: "/Applications/App \(index).app")
        return App(
            name: "App \(index)",
            sourceURL: url,
            launchURL: url,
            bundleIdentifier: "test.app.\(index)",
            isSymbolicLink: false
        )
    }
}
