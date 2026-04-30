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

final class TrackieOrderingTests: XCTestCase {
    func testDoneItemsCanBeSortedNewestCompletedFirst() {
        let now = Date(timeIntervalSince1970: 1_000)
        let older = TrackieItem(
            title: "older done",
            status: .done,
            createdAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(-1),
            completedAt: now.addingTimeInterval(-10)
        )
        let newest = TrackieItem(
            title: "newest done",
            status: .done,
            createdAt: now.addingTimeInterval(-40),
            updatedAt: now.addingTimeInterval(-20),
            completedAt: now
        )
        let middle = TrackieItem(
            title: "middle done",
            status: .done,
            createdAt: now.addingTimeInterval(-20),
            updatedAt: now.addingTimeInterval(-2),
            completedAt: now.addingTimeInterval(-5)
        )

        let sorted = [older, newest, middle].sortedByMostRecentlyCompleted()

        XCTAssertEqual(sorted.map(\.title), ["newest done", "middle done", "older done"])
    }

    func testMovePendingItemsUsesFilteredOffsets() {
        var items = [
            TrackieItem(title: "done", status: .done),
            TrackieItem(title: "one", status: .pending),
            TrackieItem(title: "scratched", status: .scratched),
            TrackieItem(title: "two", status: .pending),
            TrackieItem(title: "three", status: .pending),
            TrackieItem(title: "trashed", status: .trashed),
        ]

        items.moveItems(withStatus: .pending, from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(items.map(\.title), [
            "done",
            "three",
            "scratched",
            "one",
            "two",
            "trashed",
        ])
    }
}
