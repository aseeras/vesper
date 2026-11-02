import XCTest
@testable import VesperCore

final class HighlightTests: XCTestCase {
    private func session() -> (TelemetryTrack, [Lap]) {
        let fixes = Fixtures.circle(radius: 300, speed: 40, laps: 4)
        let duration = fixes.last!.t
        let spikes: [(t: Double, lateral: Double, longitudinal: Double)] = [
            (30, 1.25, 0), (60, 0.2, -1.1), (95, 1.1, 0), (130, 0.9, 0), (160, 0.1, -0.9), (180, 1.2, 0),
        ]
        let track = TelemetryTrack(fixes: fixes, gforces: Fixtures.gforces(duration: duration, spikes: spikes))
        let gate = LapDetector.autoGate(for: fixes)!
        return (track, LapDetector.laps(gate: gate, fixes: fixes))
    }

    func testDetectsTheBigMoments() {
        let (track, laps) = session()
        let moments = HighlightEngine.detectMoments(track: track, laps: laps)
        XCTAssertEqual(moments.filter { $0.kind == .corner }.count, 4)
        XCTAssertEqual(moments.filter { $0.kind == .braking }.count, 2)
        XCTAssertEqual(moments.filter { $0.kind == .fastestLap }.count, 1)
        XCTAssertEqual(moments.filter { $0.kind == .topSpeed }.count, 1)
        XCTAssertTrue(moments.contains { $0.caption == "LATERAL 1.30 G" })
    }

    func testPlanFitsBudgetAndStaysInOrder() {
        let (track, laps) = session()
        var options = HighlightOptions()
        options.targetDuration = 30
        options.videoStart = 5
        options.videoEnd = track.duration
        let plan = HighlightEngine.plan(track: track, laps: laps, options: options)

        XCTAssertFalse(plan.segments.isEmpty)
        XCTAssertLessThanOrEqual(plan.totalDuration, options.targetDuration + 4 * options.beat)
        for (a, b) in zip(plan.segments, plan.segments.dropFirst()) {
            XCTAssertLessThanOrEqual(a.sourceEnd, b.sourceStart + 1e-9)
        }
        for s in plan.segments {
            XCTAssertGreaterThan(s.sourceDuration, 0)
            XCTAssertGreaterThanOrEqual(s.sourceStart, options.videoStart)
            XCTAssertLessThanOrEqual(s.sourceEnd, options.videoEnd)
        }
        XCTAssertTrue(plan.segments.contains { $0.role == .slowMotion })
        XCTAssertLessThanOrEqual(plan.segments.filter { $0.role == .slowMotion }.count, options.maxSlowMotionMoments)
    }

    func testOutputTimeMapsBackToSource() {
        let (track, laps) = session()
        let plan = HighlightEngine.plan(track: track, laps: laps, options: HighlightOptions())
        let i = plan.segments.firstIndex { $0.role == .slowMotion }!
        let start = plan.outputStart(ofSegment: i)
        let hit = plan.source(atOutput: start + 1)!
        XCTAssertEqual(hit.index, i)
        XCTAssertEqual(hit.missionTime, plan.segments[i].sourceStart + 0.5, accuracy: 1e-9)
    }

    func testQuietDriveStillMakesAFilm() {
        let fixes = Fixtures.circle(radius: 500, speed: 10, laps: 1)
        let track = TelemetryTrack(fixes: fixes, gforces: Fixtures.gforces(duration: fixes.last!.t, spikes: []))
        var options = HighlightOptions()
        options.videoEnd = track.duration
        let plan = HighlightEngine.plan(track: track, laps: [], options: options)
        XCTAssertGreaterThan(plan.totalDuration, 5)
    }
}
