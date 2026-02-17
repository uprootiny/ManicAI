import Foundation

struct PanelState: Decodable {
    let ts: Int
    let sessions: [SessionInfo]
    let panes: [PaneInfo]
    let takeoverCandidates: [PaneInfo]
    let smoke: SmokeSummary
    let vibe: VibeSummary

    enum CodingKeys: String, CodingKey {
        case ts
        case sessions
        case panes
        case takeoverCandidates = "takeover_candidates"
        case smoke
        case vibe
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
    let maxTargets: Int
    let autoApprove: Bool

    enum CodingKeys: String, CodingKey {
        case prompt
        case maxTargets = "max_targets"
        case autoApprove = "auto_approve"
    }
}
