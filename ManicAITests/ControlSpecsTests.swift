import XCTest
@testable import ManicAI

final class ControlSpecsTests: XCTestCase {
    func testCriticalRouteValidation() {
        var caps = APICapabilities()
        XCTAssertEqual(ControlSpecs.missingCriticalRoutes(capabilities: caps).count, 3)

        caps.state = true
        caps.autopilot = true
        caps.smoke = true
        XCTAssertTrue(ControlSpecs.missingCriticalRoutes(capabilities: caps).isEmpty)
    }

    func testProjectRegistryMappings() {
        XCTAssertEqual(ProjectRegistry.inferRepoName(from: "/home/uprootiny/dec27/hyle"), "hyle")
        XCTAssertEqual(ProjectRegistry.inferRepoName(from: "/home/uprootiny/coggy"), "coggy")
        XCTAssertEqual(ProjectRegistry.inferRepoName(from: "/home/uprootiny/Shevat/atlas"), "atlas")
    }

    func testProjectRegistryGithubURL() {
        let url = ProjectRegistry.githubURL(for: "/home/uprootiny/coggy")
        XCTAssertEqual(url?.absoluteString, "https://github.com/uprootiny/coggy")
    }

    func testAPICallStatsFluency() {
        var stats = APICallStats()
        XCTAssertEqual(stats.fluency, 0)
        stats.success = 3
        stats.failure = 1
        XCTAssertEqual(stats.fluency, 75)
    }

    func testControlSpecContainsCriticalRoutes() {
        let critical = ControlSpecs.routes.filter { $0.critical }.map(\.path)
        XCTAssertTrue(critical.contains("/api/state"))
        XCTAssertTrue(critical.contains("/api/autopilot/run"))
        XCTAssertTrue(critical.contains("/api/smoke"))
    }

    @MainActor
    func testCommutationPlanUsesFallbackForLowFluencyNode() throws {
        let json = """
        {
          "sessions": [{"raw":"0"}],
          "panes": [{
            "target":"coggy:0.0",
            "command":"claude",
            "liveness":"warm",
            "idle_sec": 1,
            "throughput_bps": 12.0,
            "auth_rituals": [],
            "capture":"x"
          }],
          "takeover_candidates": [{
            "target":"coggy:0.0",
            "command":"claude",
            "liveness":"warm",
            "idle_sec": 1,
            "throughput_bps": 12.0,
            "auth_rituals": [],
            "capture":"x"
          }],
          "projects": [{"path":"/home/uprootiny/coggy"}],
          "queue": [],
          "smoke": {"status":"pass"},
          "vibe": {"pipeline_status":"ok","build_latency":"ok","developer_state":"ok"}
        }
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(PanelState.self, from: json)
        let client = PanelClient()
        client.state = state
        client.fanoutPerCycle = 1
        client.enableFallbackRouting = true
        client.fallbackFluencyThreshold = 50
        client.apiStatsByNodeRoute["coggy:0.0|autopilot/run"] = APICallStats(success: 1, failure: 4)

        let plan = client.buildCommutationPlan(route: "autopilot/run")
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].strategy, .paneSmokeFallback)
    }
}
