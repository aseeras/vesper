import XCTest
@testable import VesperCore

final class VoiceCommandTests: XCTestCase {
    let cars = ["DB9", "Vantage V8", "Range Rover"]

    func parse(_ s: String) -> VoiceCommand? { VoiceCommandParser.parse(s, cars: cars) }

    func testNeedsTheWakeWord() {
        XCTAssertNil(parse("end mission"))
        XCTAssertNil(parse("let's do a track day"))
        XCTAssertNil(parse("Vesper"))
    }

    func testStartsDrives() {
        XCTAssertEqual(parse("Vesper, track day"), .start(.track))
        XCTAssertEqual(parse("Vespa grand tour"), .start(.road))
        XCTAssertEqual(parse("vesper start mission"), .start(nil))
    }

    func testEndsAndStandsDown() {
        XCTAssertEqual(parse("Vesper, end mission."), .end)
        XCTAssertEqual(parse("Vesper stop recording"), .end)
        XCTAssertEqual(parse("Vesper stand down"), .standDown)
    }

    func testPicksCars() {
        XCTAssertEqual(parse("Vesper, next car"), .nextCar)
        XCTAssertEqual(parse("Vesper use the DB 9"), .selectCar(0))
        XCTAssertEqual(parse("Vesper DB nine"), .selectCar(0))
        XCTAssertEqual(parse("Vesper, Vantage V8 please"), .selectCar(1))
        XCTAssertEqual(parse("Vesper range rover"), .selectCar(2))
    }

    func testUsesTheLastWakeWord() {
        XCTAssertEqual(parse("vesper track day no wait vesper grand tour"), .start(.road))
    }
}
