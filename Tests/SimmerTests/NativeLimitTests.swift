import XCTest
@testable import SimmerShared

final class NativeLimitTests: XCTestCase {
    let steps = [80, 85, 90, 95, 100]

    func testRoundsUpToTheNextAvailableTarget() {
        XCTAssertEqual(NativeLimitMapper.target(for: 80, available: steps), 80)
        XCTAssertEqual(NativeLimitMapper.target(for: 82, available: steps), 85)
        XCTAssertEqual(NativeLimitMapper.target(for: 99, available: steps), 100)
    }

    func testBelowTheFloorUsesTheLowestTarget() {
        XCTAssertEqual(NativeLimitMapper.target(for: 60, available: steps), 80)
    }

    func testEmptyListMeansNoLimit() {
        XCTAssertEqual(NativeLimitMapper.target(for: 60, available: []), 100)
    }

    func testFinerTargetsAreUsedExactly() {
        XCTAssertEqual(NativeLimitMapper.target(for: 63, available: Array(10...100)), 63)
    }

    func testConfigDecodesWithoutChargeControl() throws {
        var obj = try JSONSerialization.jsonObject(with: SimmerJSON.encode(SimmerConfig())) as! [String: Any]
        obj.removeValue(forKey: "chargeControl")
        let cfg = try SimmerJSON.decode(SimmerConfig.self, JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(cfg.chargeControl, .automatic)
    }

    /// Read-only check against the real system service (skipped where it does not exist).
    func testReadsTheSystemServiceWhenPresent() throws {
        let n = NativeChargeLimit.shared
        try XCTSkipUnless(n.isSupported, "macOS Charge Limit not available here")
        XCTAssertFalse(n.availableLimits().isEmpty)
        XCTAssertNotNil(n.current())
    }
}
