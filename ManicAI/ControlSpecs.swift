import Foundation

struct RouteSpec: Identifiable {
    let id: String
    let method: String
    let path: String
    let critical: Bool
}

enum ControlSpecs {
    static let routes: [RouteSpec] = [
        RouteSpec(id: "state", method: "GET", path: "/api/state", critical: true),
        RouteSpec(id: "autopilot", method: "POST", path: "/api/autopilot/run", critical: true),
        RouteSpec(id: "smoke", method: "POST", path: "/api/smoke", critical: true),
        RouteSpec(id: "queue_add", method: "POST", path: "/api/queue/add", critical: false),
        RouteSpec(id: "queue_run", method: "POST", path: "/api/queue/run", critical: false),
        RouteSpec(id: "pane_send", method: "POST", path: "/api/pane/send", critical: false),
        RouteSpec(id: "nudge", method: "POST", path: "/api/nudge", critical: false),
        RouteSpec(id: "spawn", method: "POST", path: "/api/spawn", critical: false),
        RouteSpec(id: "snapshot_ingest", method: "POST", path: "/api/snapshot/ingest", critical: false)
    ]

    static func missingCriticalRoutes(capabilities: APICapabilities) -> [String] {
        var missing: [String] = []
        if !capabilities.state { missing.append("/api/state") }
        if !capabilities.autopilot { missing.append("/api/autopilot/run") }
        if !capabilities.smoke { missing.append("/api/smoke") }
        return missing
    }
}

enum ProjectRegistry {
    static let owner = "uprootiny"

    private static let overrides: [String: String] = [
        "coggy": "coggy",
        "hyle": "hyle",
        "hyperpanel": "hyperpanel",
        "atlas": "atlas",
        "manicai": "ManicAI"
    ]

    static func inferRepoName(from path: String) -> String? {
        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let lower = cleaned.lowercased()
        for (token, repo) in overrides where lower.contains("/\(token)") || lower.hasSuffix(token) {
            return repo
        }
        guard let last = cleaned.split(separator: "/").last else { return nil }
        let normalized = String(last).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func githubURL(for path: String) -> URL? {
        guard let repo = inferRepoName(from: path) else { return nil }
        return URL(string: "https://github.com/\(owner)/\(repo)")
    }
}
