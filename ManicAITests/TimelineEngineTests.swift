import XCTest
@testable import ManicAI

final class TimelineEngineTests: XCTestCase {
    func testTracksGrouping() {
        let events = [
            PromptEvent(id: UUID(), ts: 1, route: "a", target: "t1", prompt: "p1"),
            PromptEvent(id: UUID(), ts: 2, route: "a", target: "t2", prompt: "p2"),
            PromptEvent(id: UUID(), ts: 3, route: "a", target: "t1", prompt: "p3")
        ]
        let tracks = TimelineEngine.tracks(events)
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks.first(where: { $0.name == "t1" })?.events.count, 2)
    }

    func testRangeSelection() {
        let events = [
            PromptEvent(id: UUID(), ts: 1, route: "a", target: "t1", prompt: "p1"),
            PromptEvent(id: UUID(), ts: 2, route: "a", target: "t1", prompt: "p2"),
            PromptEvent(id: UUID(), ts: 3, route: "a", target: "t1", prompt: "p3")
        ]
        let xs = TimelineEngine.rangeEvents(events, start: 2, end: 1)
        XCTAssertEqual(xs.count, 2)
        XCTAssertEqual(xs.first?.prompt, "p2")
    }

    func testCadenceDeltas() {
        let events = [
            PromptEvent(id: UUID(), ts: 1, route: "a", target: "t1", prompt: "p1"),
            PromptEvent(id: UUID(), ts: 4, route: "a", target: "t1", prompt: "p2"),
            PromptEvent(id: UUID(), ts: 10, route: "a", target: "t1", prompt: "p3")
        ]
        let ds = TimelineEngine.cadenceDeltas(events)
        XCTAssertEqual(ds.count, 2)
        XCTAssertEqual(ds[0], 3)
        XCTAssertEqual(ds[1], 6)
    }

    func testPromptEventBackwardDecodeDefaultsKind() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","ts":1,"route":"x","target":"t","prompt":"p"}
        """.data(using: .utf8)!
        let ev = try JSONDecoder().decode(PromptEvent.self, from: json)
        XCTAssertEqual(ev.kind, .prompt)
        XCTAssertEqual(ev.route, "x")
    }

    func testPromptEventDecodeWithOntologyKind() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","ts":1,"route":"x","target":"t","prompt":"p","kind":"ontology"}
        """.data(using: .utf8)!
        let ev = try JSONDecoder().decode(PromptEvent.self, from: json)
        XCTAssertEqual(ev.kind, .ontology)
    }
}
