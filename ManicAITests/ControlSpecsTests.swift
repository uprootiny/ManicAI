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
}
