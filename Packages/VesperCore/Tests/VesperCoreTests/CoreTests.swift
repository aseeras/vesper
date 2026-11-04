import XCTest
@testable import VesperCore

final class AutoRecordTests: XCTestCase {
    func testStartsAfterHoldAndFinishesAfterParking() {
        var c = AutoRecordController()
        XCTAssertNil(c.update(speed: 10, at: 0))
        XCTAssertNil(c.update(speed: 10, at: 1))
        XCTAssertEqual(c.update(speed: 10, at: 2.1), .startRecording)
        XCTAssertTrue(c.isRolling)
        // A brief stop in the pit lane doesn't end the mission.
        XCTAssertNil(c.update(speed: 0, at: 10))
        XCTAssertNil(c.update(speed: 20, at: 30))
        XCTAssertNil(c.update(speed: 0, at: 40))
        XCTAssertNil(c.update(speed: 0, at: 80))
        XCTAssertEqual(c.update(speed: 0, at: 85.1), .finishMission)
        XCTAssertNil(c.update(speed: 30, at: 90))
    }

    func testBlipOfSpeedDoesNotStart() {
        var c = AutoRecordController()
        XCTAssertNil(c.update(speed: 10, at: 0))
        XCTAssertNil(c.update(speed: 1, at: 1))
        XCTAssertNil(c.update(speed: 10, at: 1.5))
        XCTAssertNil(c.update(speed: 10, at: 3))
        XCTAssertEqual(c.update(speed: 10, at: 3.6), .startRecording)
    }
}

final class GForceTests: XCTestCase {
    func testLateralFromYawRateIsMountIndependent() {
        // Phone flat on its back: gravity along -z. Car turning left at 0.5 rad/s, 20 m/s.
        let centripetal = 20 * 0.5 / 9.80665
        let flat = GForceEstimator.estimate(speed: 20, rotationRate: Vec3(x: 0, y: 0, z: 0.5),
                                            gravity: Vec3(x: 0, y: 0, z: -1),
                                            userAcceleration: Vec3(x: centripetal, y: 0, z: 0), speedTrend: 0)
        XCTAssertEqual(flat.lateral, 20 * 0.5 / 9.80665, accuracy: 1e-6)
        XCTAssertEqual(flat.longitudinal, 0, accuracy: 0.01)

        // Same turn, phone standing upright in a dash mount: gravity along -y.
        let upright = GForceEstimator.estimate(speed: 20, rotationRate: Vec3(x: 0, y: 0.5, z: 0),
                                               gravity: Vec3(x: 0, y: -1, z: 0),
                                               userAcceleration: Vec3(x: 0.6, y: 0, z: 0), speedTrend: -2)
        XCTAssertEqual(upright.lateral, flat.lateral, accuracy: 1e-6)
        // All 0.6 g of horizontal push is explained by cornering, so nothing is left for braking.
        XCTAssertEqual(upright.longitudinal, 0, accuracy: 1e-6)
    }

    func testBrakingSign() {
        let r = GForceEstimator.estimate(speed: 30, rotationRate: Vec3(x: 0, y: 0, z: 0),
                                         gravity: Vec3(x: 0, y: 0, z: -1),
                                         userAcceleration: Vec3(x: 0, y: 0.9, z: 0), speedTrend: -8)
        XCTAssertEqual(r.lateral, 0, accuracy: 1e-9)
        XCTAssertEqual(r.longitudinal, -0.9, accuracy: 1e-9)
    }
}

final class FormatTests: XCTestCase {
    func testLapTime() {
        XCTAssertEqual(Format.lapTime(102.381), "1:42.381")
        XCTAssertEqual(Format.lapTime(59.9996), "1:00.000")
        XCTAssertEqual(Format.spokenLapTime(102.34), "1 minute 42 point 3")
        XCTAssertEqual(Format.speed(50, .kmh), "180 KM/H")
        XCTAssertEqual(Format.speed(50, .mph), "112 MPH")
    }
}

final class EngineRPMTests: XCTestCase {
    func testRecoversV12RPMFromSyntheticEngineNote() {
        for rpm in [1_500.0, 3_200, 5_600, 6_800] {
            // Fresh estimator each time: a real engine can't jump thousands of rpm in 50 ms.
            var estimator = EngineRPMEstimator(cylinders: 12, sampleRate: 44_100)
            let f = estimator.frequency(forRPM: rpm)
            let samples: [Float] = (0..<2_048).map { i in
                let t = Double(i) / 44_100
                // Fundamental plus harmonics and a little noise, like exhaust pulses.
                let s = sin(2 * .pi * f * t) + 0.5 * sin(4 * .pi * f * t) + 0.25 * sin(6 * .pi * f * t)
                return Float(s + Double.random(in: -0.05...0.05))
            }
            let est = estimator.estimate(samples)
            XCTAssertNotNil(est, "rpm \(rpm)")
            XCTAssertEqual(est ?? 0, rpm, accuracy: rpm * 0.03, "rpm \(rpm)")
        }
    }

    func testSilenceGivesNothing() {
        var estimator = EngineRPMEstimator()
        let noise: [Float] = (0..<2_048).map { _ in Float.random(in: -1...1) }
        XCTAssertNil(estimator.estimate(noise))
    }
}

final class LensHUDTests: XCTestCase {
    func testLapDeltaAgainstPreviousBest() {
        let best = Lap(number: 2, start: 0, end: 100, topSpeed: 60)
        let faster = Lap(number: 3, start: 100, end: 199.58, topSpeed: 62)
        let hud = LensHUD.lapComplete(faster, previousBest: best, unit: .mph)
        XCTAssertEqual(hud.headline, "L3  1:39.580")
        XCTAssertEqual(hud.detail, "−0.42 NEW BEST")
        XCTAssertTrue(hud.positive)
        XCTAssertEqual(hud.footnote, "TOP 139 MPH")

        let slower = LensHUD.lapComplete(Lap(number: 4, start: 0, end: 101, topSpeed: 60), previousBest: best, unit: .mph)
        XCTAssertEqual(slower.detail, "+1.00 TO BEST")
        XCTAssertFalse(slower.positive)
    }

    func testLiveGaugesShowSpeedWithoutRevs() {
        let best = Lap(number: 2, start: 0, end: 102.381, topSpeed: 60)
        let a = LensHUD.live(speed: 50, unit: .mph, lap: 3, best: best)
        XCTAssertEqual(a.headline, "112 MPH")
        XCTAssertEqual(a.detail, "LAP 3")
        XCTAssertEqual(a.footnote, "BEST 1:42.381")
        // A fraction of a mph produces the identical layout, so the lens doesn't refresh.
        XCTAssertEqual(a, LensHUD.live(speed: 50.05, unit: .mph, lap: 3, best: best))
        let out = LensHUD.live(speed: 0, unit: .kmh, lap: 0, best: nil)
        XCTAssertEqual(out.headline, "0 KM/H")
        XCTAssertEqual(out.detail, "OUT LAP")
        XCTAssertNil(out.footnote)
        for hud in [a, out, LensHUD.liveRoad(speed: 20, unit: .mph, distance: 5_000, elapsed: 600)] {
            XCTAssertFalse([hud.headline, hud.detail ?? "", hud.footnote ?? ""].joined().contains("RPM"))
        }
    }
}
