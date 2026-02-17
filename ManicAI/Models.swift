import Foundation

struct PanelState: Decodable {
    let ts: Int?
    let sessions: [SessionInfo]
    let panes: [PaneInfo]
    let takeoverCandidates: [PaneInfo]
    let projects: [ProjectInfo]
    let queue: [QueueItem]
    let smoke: SmokeSummary
    let vibe: VibeSummary

    enum CodingKeys: String, CodingKey {
        case ts
        case sessions
        case panes
        case takeoverCandidates = "takeover_candidates"
        case projects
        case queue
        case smoke
        case vibe
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = try c.decodeIfPresent(Int.self, forKey: .ts)
        sessions = try c.decodeIfPresent([SessionInfo].self, forKey: .sessions) ?? []
        panes = try c.decodeIfPresent([PaneInfo].self, forKey: .panes) ?? []
        takeoverCandidates = try c.decodeIfPresent([PaneInfo].self, forKey: .takeoverCandidates) ?? []
        projects = try c.decodeIfPresent([ProjectInfo].self, forKey: .projects) ?? []
        queue = try c.decodeIfPresent([QueueItem].self, forKey: .queue) ?? []
        smoke = try c.decodeIfPresent(SmokeSummary.self, forKey: .smoke) ?? SmokeSummary(status: "unknown", passes: nil, fails: nil, log: nil)
        vibe = try c.decodeIfPresent(VibeSummary.self, forKey: .vibe) ?? VibeSummary(pipelineStatus: "unknown", buildLatency: "unknown", developerState: "unknown")
    }
}

struct SessionInfo: Decodable, Identifiable {
    var id: String { raw }
    let raw: String
}

struct PaneInfo: Decodable, Identifiable {
    var id: String { target }
    let target: String
    let command: String
    let liveness: String
    let idleSec: Int
    let throughputBps: Double
    let authRituals: [String]
    let capture: String

    enum CodingKeys: String, CodingKey {
        case target
        case command
        case liveness
        case idleSec = "idle_sec"
        case throughputBps = "throughput_bps"
        case authRituals = "auth_rituals"
        case capture
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? "unknown"
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? "-"
        liveness = try c.decodeIfPresent(String.self, forKey: .liveness) ?? "unknown"
        idleSec = try c.decodeIfPresent(Int.self, forKey: .idleSec) ?? -1
        throughputBps = try c.decodeIfPresent(Double.self, forKey: .throughputBps) ?? 0
        authRituals = try c.decodeIfPresent([String].self, forKey: .authRituals) ?? []
        capture = try c.decodeIfPresent(String.self, forKey: .capture) ?? ""
    }
}

struct ProjectInfo: Decodable, Identifiable {
    var id: String { path }
    let path: String
    let branch: String?
    let dirtyFiles: Int?
    let smoke: Bool?

    enum CodingKeys: String, CodingKey {
        case path
        case branch
        case dirtyFiles = "dirty_files"
        case smoke
    }
}

struct QueueItem: Decodable, Identifiable {
    let id: UUID = UUID()
    let prompt: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case prompt
        case status
    }
}

struct SmokeSummary: Decodable {
    let status: String
    let passes: Int?
    let fails: Int?
    let log: String?
}

struct VibeSummary: Decodable {
    let pipelineStatus: String
    let buildLatency: String
    let developerState: String

    enum CodingKeys: String, CodingKey {
        case pipelineStatus = "pipeline_status"
        case buildLatency = "build_latency"
        case developerState = "developer_state"
    }
}

struct AutopilotRequest: Encodable {
    let prompt: String
    let project: String?
    let maxTargets: Int
    let autoApprove: Bool

    enum CodingKeys: String, CodingKey {
        case prompt
        case project
        case maxTargets = "max_targets"
        case autoApprove = "auto_approve"
    }
}

struct SurfaceProbe: Identifiable {
    let id = UUID()
    let baseURL: URL
    let healthy: Bool
    let stateReachable: Bool
    let sessions: Int
    let candidates: Int
    let smokeStatus: String
    let error: String?
}

struct ScopeContract {
    var objective: String = "Stabilize active project loops into smoke-green, bounded work."
    var doneCriteria: String = "Smoke is pass and blocker count decreases."
    var intentLatch: String = ""
    var requireIntentLatch: Bool = true
    var attentionBudgetActions: Int = 6
    var maxCycles: Int = 3
    var requireSmokePassToStop: Bool = true
    var freezeOnDrift: Bool = true
}

struct InteractionHealth {
    let score: Int
    let label: String
    let notes: [String]
}

enum LanePriority: String, CaseIterable, Identifiable {
    case primary = "Primary"
    case secondary = "Secondary"
    case quarantine = "Quarantine"
    var id: String { rawValue }
}

struct SessionThrottle {
    var cooldownSec: Double?
    var delayMs: Double?
    var enabled: Bool = true
}

struct APICapabilities {
    var state: Bool = false
    var autopilot: Bool = false
    var smoke: Bool = false
    var paneSend: Bool = false
    var queue: Bool = false
    var queueRun: Bool = false
    var spawn: Bool = false
    var nudge: Bool = false
    var snapshotIngest: Bool = false
}

struct APICallStats {
    var success: Int = 0
    var failure: Int = 0

    var total: Int { success + failure }
    var fluency: Int {
        guard total > 0 else { return 0 }
        return Int((Double(success) / Double(total) * 100).rounded())
    }
}

enum ExecutionStrategy: String {
    case autopilot = "autopilot"
    case paneSmokeFallback = "pane+smoke"
}

struct CommutationPlanStep: Identifiable {
    let id = UUID()
    let target: String
    let lane: LanePriority
    let fluency: Int
    let throughputBps: Double
    let strategy: ExecutionStrategy
    let reason: String
}

struct BreakerConfig {
    var sampleWindow: Int = 6
    var minFailures: Int = 3
    var failureRateTrip: Double = 0.6
    var openCooldownSec: TimeInterval = 90
}

struct BreakerState {
    var openUntil: Date?
    var lastTripReason: String = ""
    var recent: [Bool] = []

    var isOpen: Bool {
        guard let until = openUntil else { return false }
        return until > Date()
    }
}

struct PromptEvent: Codable, Identifiable {
    let id: UUID
    let ts: TimeInterval
    let route: String
    let target: String?
    let prompt: String
    let kind: TimelineKind
    let summary: String?

    init(id: UUID, ts: TimeInterval, route: String, target: String?, prompt: String, kind: TimelineKind = .prompt, summary: String? = nil) {
        self.id = id
        self.ts = ts
        self.route = route
        self.target = target
        self.prompt = prompt
        self.kind = kind
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case id, ts, route, target, prompt, kind, summary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        ts = try c.decodeIfPresent(TimeInterval.self, forKey: .ts) ?? 0
        route = try c.decodeIfPresent(String.self, forKey: .route) ?? "-"
        target = try c.decodeIfPresent(String.self, forKey: .target)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        kind = try c.decodeIfPresent(TimelineKind.self, forKey: .kind) ?? .prompt
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
    }
}

enum TimelineKind: String, Codable, CaseIterable {
    case prompt
    case duplex
    case ontology
    case git
    case file
    case service
}

struct LayerEdgeMetric: Identifiable {
    var id: String { "\(from.rawValue)->\(to.rawValue)" }
    let from: TimelineKind
    let to: TimelineKind
    let count: Int
    let avgLatencySec: Double
    let avgQuality: Double
}

struct CadenceStats: Codable {
    let meanSec: Double
    let p50Sec: Double
    let p90Sec: Double
    let burstRatioPct: Double
    let longestIdleSec: Double
}

struct SessionProfileSnapshot: Codable {
    let exportedAt: TimeInterval
    let totalEvents: Int
    let layerCounts: [String: Int]
    let cadence: CadenceStats
    let openRouteBreakers: Int
    let openNodeRouteBreakers: Int
    let degradedMode: Bool
    let degradedReason: String
    let interactionHealthScore: Int
    let interactionHealthLabel: String
    let topEdges: [String]
    let notes: [String]
}

struct PerformanceSnapshot {
    var lastRefreshMs: Double = 0
    var avgRefreshMs: Double = 0
    var maxRefreshMs: Double = 0
    var persistFlushes: Int = 0
    var recomputePasses: Int = 0
    var droppedStateEvents: Int = 0
    var estimatedMemoryMB: Double = 0
    var persistQueued: Bool = false
    var recomputeQueued: Bool = false
}
