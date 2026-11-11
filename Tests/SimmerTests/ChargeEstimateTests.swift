import XCTest
@testable import SimmerShared

final class ChargeEstimateTests: XCTestCase {
    func battery(_ pct: Double, amps: Double, maxCap: Int = 5000) -> BatterySnapshot {
        var b = BatterySnapshot(); b.present = true; b.percent = Int(pct); b.hardwarePercent = pct
        b.rawMaxCapacity = maxCap; b.amperageA = amps; b.voltageV = 12.5
        return b
    }

    func testChargingBelowTaperIsLinear() {
        // 50 → 70 % of 5 Ah at 2.5 A = 1 Ah / 2.5 A = 0.4 h = 24 min
        XCTAssertEqual(ChargeEstimate.minutes(to: 70, battery: battery(50, amps: 2.5)), 24)
    }

    func testTaperMakesTheLastPercentSlower() {
        let to80 = ChargeEstimate.minutes(to: 80, battery: battery(60, amps: 2.5))!
        let to100 = ChargeEstimate.minutes(to: 100, battery: battery(60, amps: 2.5))!
        XCTAssertEqual(to80, 24)
        XCTAssertGreaterThan(to100 - to80, 24, "the top 20% takes longer than the 60→80% stretch")
    }

    func testAlreadyTaperingScalesCurrentBack() {
        // At 90% the measured current is already reduced; the estimate must not explode or go negative.
        let m = ChargeEstimate.minutes(to: 95, battery: battery(90, amps: 1.0))!
        XCTAssertGreaterThan(m, 5); XCTAssertLessThan(m, 60)
    }

    func testDischargeTowardLimit() {
        // 90 → 80 % of 5 Ah at 1 A = 0.5 h
        XCTAssertEqual(ChargeEstimate.minutes(to: 80, battery: battery(90, amps: -1.0)), 30)
    }

    func testNilWhenIdleOrWrongDirection() {
        XCTAssertNil(ChargeEstimate.minutes(to: 80, battery: battery(80, amps: 0)))
        XCTAssertNil(ChargeEstimate.minutes(to: 70, battery: battery(80, amps: 2)), "charging but target below")
        XCTAssertNil(ChargeEstimate.minutes(to: 90, battery: battery(80, amps: -1)), "draining but target above")
        XCTAssertNil(ChargeEstimate.minutes(to: 80, battery: battery(79.8, amps: 2)), "already there")
    }

    func testFormat() {
        XCTAssertEqual(ChargeEstimate.format(minutes: 25), "25 min")
        XCTAssertEqual(ChargeEstimate.format(minutes: 60), "1 h")
        XCTAssertEqual(ChargeEstimate.format(minutes: 70), "1 h 10 min")
    }
}
