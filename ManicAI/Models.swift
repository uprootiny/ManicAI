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
