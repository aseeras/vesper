import XCTest
@testable import VesperCore

final class CameraTests: XCTestCase {
    func testParsesCameraNodesAndEnforcementRelations() throws {
        let json = """
        {"elements":[
          {"type":"node","id":1,"lat":40.0,"lon":-75.0,"tags":{"highway":"speed_camera","maxspeed":"35 mph"}},
          {"type":"relation","id":9,"tags":{"type":"enforcement","enforcement":"traffic_signals"},
           "members":[{"type":"node","ref":2,"role":"device"},{"type":"node","ref":3,"role":"from"}]},
          {"type":"relation","id":10,"tags":{"type":"enforcement","enforcement":"maxspeed","maxspeed":"80"},
           "members":[{"type":"node","ref":4,"role":"from"}]},
          {"type":"node","id":2,"lat":40.001,"lon":-75.0},
          {"type":"node","id":3,"lat":40.002,"lon":-75.0},
          {"type":"node","id":4,"lat":40.003,"lon":-75.0},
          {"type":"node","id":5,"lat":40.004,"lon":-75.0,"tags":{"highway":"traffic_signals"}}
        ]}
        """
        let cams = try CameraSource.parse(Data(json.utf8))
        XCTAssertEqual(cams.map(\.id), [1, 2, 4])
        XCTAssertEqual(cams[0].kind, .speed)
        XCTAssertEqual(cams[0].limit ?? 0, 35 * 0.44704, accuracy: 0.01)
        XCTAssertEqual(cams[1].kind, .redLight)
        XCTAssertNil(cams[1].limit)
        XCTAssertEqual(cams[2].kind, .speed)
        XCTAssertEqual(cams[2].limit ?? 0, 80 / 3.6, accuracy: 0.01)
        XCTAssertTrue(CameraSource.query(around: GeoPoint(latitude: 40, longitude: -75), radius: 10_000)
            .contains("around:10000,40.0,-75.0"))
    }

    /// Camera 500 m due north.
    private let camera = EnforcementCamera(id: 7, kind: .speed, point: GeoPoint(latitude: 40.0045, longitude: -75.0))
    private func fix(lat: Double, course: Double, speed: Double = 25) -> GPSFix {
        GPSFix(t: 0, point: GeoPoint(latitude: lat, longitude: -75.0), speed: speed, course: course)
    }

    func testWarnsOnceForACameraAheadOnly() {
        var a = CameraAlerter()
        // 25 m/s × 15 s = 375 m trigger: 500 m away is too early.
        XCTAssertNil(a.update(fix: fix(lat: 40.0, course: 0), cameras: [camera]))
        // ~280 m away, heading north: warn.
        let alert = a.update(fix: fix(lat: 40.002, course: 0), cameras: [camera])
        XCTAssertEqual(alert?.camera.id, 7)
        XCTAssertEqual(alert?.distance ?? 0, 280, accuracy: 10)
        // Not again on the same pass.
        XCTAssertNil(a.update(fix: fix(lat: 40.003, course: 0), cameras: [camera]))
    }

    func testIgnoresCamerasBehindOrWithoutCourse() {
        var a = CameraAlerter()
        XCTAssertNil(a.update(fix: fix(lat: 40.002, course: 180), cameras: [camera]))
        XCTAssertNil(a.update(fix: fix(lat: 40.002, course: -1), cameras: [camera]))
        XCTAssertNil(a.update(fix: fix(lat: 40.002, course: 0, speed: 0), cameras: [camera]))
    }

    func testRearmsAfterDrivingAway() {
        var a = CameraAlerter()
        XCTAssertNotNil(a.update(fix: fix(lat: 40.002, course: 0), cameras: [camera]))
        _ = a.update(fix: fix(lat: 39.98, course: 180), cameras: [camera])   // ~2.7 km away
        XCTAssertNotNil(a.update(fix: fix(lat: 40.002, course: 0), cameras: [camera]))
    }

    func testLensCard() {
        let alert = CameraAlerter.Alert(camera: EnforcementCamera(id: 1, kind: .redLight, point: GeoPoint(latitude: 0, longitude: 0),
                                                                  limit: 35 * 0.44704), distance: 290)
        let hud = LensHUD.camera(alert, unit: .mph)
        XCTAssertEqual(hud.headline, "RED-LIGHT CAMERA")
        XCTAssertEqual(hud.detail, "1,000 FT AHEAD")
        XCTAssertEqual(hud.footnote, "LIMIT 35 MPH")
        XCTAssertEqual(LensHUD.camera(alert, unit: .kmh).detail, "300 M AHEAD")
    }
}
