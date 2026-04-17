import XCTest
@testable import TrackieClient

final class TrackieClientTests: XCTestCase {
    func testShortIdIsEightChars() {
        let item = TrackieItem(title: "hello")
        XCTAssertEqual(item.shortId.count, 8)
    }

    func testDefaultsAreDistinctFromPiTalk() {
        // PiTalk uses 18080/18081; Trackie must not collide.
        XCTAssertNotEqual(TrackieDefaults.brokerPort, 18080)
        XCTAssertNotEqual(TrackieDefaults.brokerPort, 18081)
    }

    func testRequestRoundTrips() throws {
        let req = TrackieRequest(type: "add", title: "hello", project: "trackie")
        let data = try JSONEncoder().encode(req)
        let back = try JSONDecoder().decode(TrackieRequest.self, from: data)
        XCTAssertEqual(back.type, "add")
        XCTAssertEqual(back.title, "hello")
        XCTAssertEqual(back.project, "trackie")
    }
}
