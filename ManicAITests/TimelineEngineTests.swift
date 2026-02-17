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

    func testLayerEdgesAndQuality() {
        let events = [
            PromptEvent(id: UUID(), ts: 1, route: "a", target: "t", prompt: "p", kind: .duplex),
            PromptEvent(id: UUID(), ts: 5, route: "b", target: "t", prompt: "p", kind: .service),
            PromptEvent(id: UUID(), ts: 15, route: "c", target: "t", prompt: "p", kind: .ontology),
            PromptEvent(id: UUID(), ts: 25, route: "d", target: "t", prompt: "p", kind: .git)
        ]
        let edges = TimelineEngine.layerEdges(events)
        XCTAssertFalse(edges.isEmpty)
        XCTAssertTrue(edges.contains(where: { $0.from == .duplex && $0.to == .service }))
        let q = TimelineEngine.edgeQuality(from: .duplex, to: .service, latencySec: 5)
        XCTAssertGreaterThanOrEqual(q, 80)
    }

    func testLayerCountsAndCadenceStats() {
        let events = [
            PromptEvent(id: UUID(), ts: 0, route: "a", target: "x", prompt: "p", kind: .prompt),
            PromptEvent(id: UUID(), ts: 10, route: "b", target: "x", prompt: "p", kind: .service),
            PromptEvent(id: UUID(), ts: 40, route: "c", target: "x", prompt: "p", kind: .service),
            PromptEvent(id: UUID(), ts: 100, route: "d", target: "x", prompt: "p", kind: .git)
        ]
        let counts = TimelineEngine.layerCounts(events)
        XCTAssertEqual(counts[.service], 2)
        XCTAssertEqual(counts[.git], 1)

        let c = TimelineEngine.cadenceStats(events)
        XCTAssertEqual(c.meanSec, 33.333333333333336, accuracy: 0.001)
        XCTAssertEqual(c.p50Sec, 30, accuracy: 0.001)
        XCTAssertEqual(c.p90Sec, 60, accuracy: 0.001)
    }
}
