import XCTest
@testable import VesperCore

final class LapTests: XCTestCase {
    func testAutoGateFindsLapsOfExpectedLength() throws {
        // The first pass from the pits only opens lap 1, so 5 circuits give at least 3 timed laps.
        let fixes = Fixtures.circle(radius: 200, speed: 30, laps: 5)
        let gate = try XCTUnwrap(LapDetector.autoGate(for: fixes))
        let laps = LapDetector.laps(gate: gate, fixes: fixes)
        let expected = 2 * Double.pi * 200 / 30
        XCTAssertGreaterThanOrEqual(laps.count, 3)
        for lap in laps {
            XCTAssertEqual(lap.duration, expected, accuracy: 0.05)
            XCTAssertEqual(lap.topSpeed, 30, accuracy: 0.001)
        }
    }

    func testGateIgnoresWrongDirection() throws {
        let fixes = Fixtures.circle()
        var gate = try XCTUnwrap(LapDetector.autoGate(for: fixes))
        gate.heading = (gate.heading + 180).truncatingRemainder(dividingBy: 360)
        XCTAssertTrue(LapDetector.crossings(of: gate, in: fixes).isEmpty)
    }

    func testNoGateForPointToPointDrive() {
        let p = LocalProjection(origin: Fixtures.origin)
        let fixes = (0..<200).map { i in
            GPSFix(t: Double(i), point: p.unproject(Vec2(x: Double(i) * 30, y: 0)), speed: 30, course: 90)
        }
        XCTAssertNil(LapDetector.autoGate(for: fixes))
    }

    func testLiveTimerMatchesOfflineLaps() throws {
        let fixes = Fixtures.circle(laps: 3)
        let gate = try XCTUnwrap(LapDetector.autoGate(for: fixes))
        var live = LiveLapTimer(gate: gate)
        let liveLaps = fixes.compactMap { live.add($0) }
        let offline = LapDetector.laps(gate: gate, fixes: fixes)
        XCTAssertEqual(liveLaps.count, offline.count)
        for (a, b) in zip(liveLaps, offline) { XCTAssertEqual(a.duration, b.duration, accuracy: 1e-9) }
        XCTAssertNotNil(live.bestLap)
    }
}
