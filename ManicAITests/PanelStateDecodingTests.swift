import XCTest
@testable import ManicAI

final class PanelStateDecodingTests: XCTestCase {
    func testDecodePanelState() throws {
        let json = """
        {
          "ts": 1,
          "sessions": [{"raw":"a"}],
          "panes": [{
            "target":"coggy:0.0",
            "command":"claude",
            "liveness":"warm",
            "idle_sec": 12,
            "throughput_bps": 2.5,
            "auth_rituals": ["token"],
            "capture":"hello"
          }],
          "takeover_candidates": [],
          "smoke": {"status":"pass"},
          "vibe": {
            "pipeline_status":"emotionally available",
            "build_latency":"healing",
            "developer_state":"low-battery but aligned"
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PanelState.self, from: json)
        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.panes.first?.target, "coggy:0.0")
        XCTAssertEqual(decoded.vibe.pipelineStatus, "emotionally available")
    }
}
