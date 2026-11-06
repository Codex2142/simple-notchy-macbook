#if canImport(XCTest)
import XCTest
import IslandBridge
@testable import IslandWindow

final class NotchDetectorTests: XCTestCase {
    func testNotchedMacBookProGeometry() {
        let metrics = ScreenMetrics(
            displayUUID: "UUID-MBP-14",
            displayName: "Built-in Liquid Retina XDR Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 37,
            auxiliaryTopLeftWidth: 664,
            auxiliaryTopRightWidth: 664
        )

        let geometry = NotchDetector.calculateGeometry(for: metrics)
        XCTAssertTrue(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect.width, 184)
        XCTAssertEqual(geometry.notchRect.height, 37)
        XCTAssertEqual(geometry.notchRect.midX, 756, accuracy: 1.0)
        XCTAssertEqual(geometry.notchRect.maxY, 982)
    }
}
#endif
