import Foundation

@MainActor
final class PanelClient: ObservableObject {
    @Published var state: PanelState?
    @Published var error: String?
    @Published var lastAction: String?
    @Published var probes: [SurfaceProbe] = []
    @Published var autopilotCooldownSec: Double = 8
    @Published var actionDelayMs: Double = 1200
    @Published var fanoutPerCycle: Int = 2
    @Published var scope = ScopeContract()
    @Published var completedCycles: Int = 0
    @Published var interactionHealth = InteractionHealth(score: 50, label: "Unrated", notes: ["Run refresh to compute health"])
    @Published var cycleJournal: [String] = []
    @Published var intentLatched: Bool = false
    @Published var latchedIntentChecksum: String = ""
    @Published var actionsInCurrentScope: Int = 0
    @Published var agitationScore: Int = 0
    @Published var lastDelta: String = ""
    @Published var panicMode: Bool = false
    @Published var panicReason: String = ""
    @Published var laneByTarget: [String: LanePriority] = [:]
    @Published var throttleByTarget: [String: SessionThrottle] = [:]
    private var lastAutopilotAt: Date?
    private var lastAutopilotAtByTarget: [String: Date] = [:]
    private var consecutiveErrors: Int = 0
    private var previousCandidateCount: Int = 0
    private var previousSmokeStatus: String = "unknown"

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let session: URLSession

    var baseURL: URL {
        didSet { UserDefaults.standard.set(baseURL.absoluteString, forKey: "manicai.baseURL") }
    }

    let endpointPresets: [String] = [
        "http://173.212.203.211:8788",
        "http://hyle.hyperstitious.org:8788",
        "http://hyperstitious.art:8788",
        "http://149.102.153.201:8788",
        "http://173.212.203.211:9801",
        "http://173.212.203.211:9750",
        "http://127.0.0.1:8788"
    ]

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 2.5
        cfg.timeoutIntervalForResource = 5.0
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
        let saved = UserDefaults.standard.string(forKey: "manicai.baseURL")
        self.baseURL = URL(string: saved ?? "http://173.212.203.211:8788")!
        if let cooldown = UserDefaults.standard.object(forKey: "manicai.autopilotCooldownSec") as? Double {
            autopilotCooldownSec = cooldown
        }
        if let delay = UserDefaults.standard.object(forKey: "manicai.actionDelayMs") as? Double {
            actionDelayMs = delay
        }
        if let fanout = UserDefaults.standard.object(forKey: "manicai.fanoutPerCycle") as? Int {
            fanoutPerCycle = fanout
        }
    }

    func refresh() async {
        do {
            let url = pathURL("api/state")
            let (data, response) = try await session.data(from: url)
            try assertHTTP(response)
            state = try decoder.decode(PanelState.self, from: data)
            error = nil
            consecutiveErrors = 0
            lastAction = "Refreshed \(baseURL.host ?? "unknown")"
            computeDelta()
            recomputeInteractionHealth()
        } catch {
            consecutiveErrors += 1
            self.error = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func runAutopilot(prompt: String, maxTargets: Int = 2, autoApprove: Bool = true, project: String? = nil) async {
        if panicMode {
            self.error = "Panic mode active. Mutations blocked."
            return
        }
        UserDefaults.standard.set(autopilotCooldownSec, forKey: "manicai.autopilotCooldownSec")
        UserDefaults.standard.set(actionDelayMs, forKey: "manicai.actionDelayMs")
        UserDefaults.standard.set(fanoutPerCycle, forKey: "manicai.fanoutPerCycle")
        if scope.requireIntentLatch {
            let checksum = checksumForIntent(scope.intentLatch)
            if !intentLatched || checksum.isEmpty || checksum != latchedIntentChecksum {
                self.error = "Intent not latched. Update latch before action."
                return
            }
        }
        if actionsInCurrentScope >= max(1, scope.attentionBudgetActions) {
            self.error = "Attention budget exceeded (\(scope.attentionBudgetActions) actions). Re-anchor intent."
            return
        }
        if let last = lastAutopilotAt {
            let gap = Date().timeIntervalSince(last)
            if gap < autopilotCooldownSec {
                let remain = Int((autopilotCooldownSec - gap).rounded(.up))
                self.error = "Autopilot throttled: wait \(remain)s"
                consecutiveErrors += 1
                return
            }
        }
        do {
            let url = pathURL("api/autopilot/run")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let selectedProject = project ?? state?.projects.first?.path
            req.httpBody = try encoder.encode(AutopilotRequest(prompt: prompt, project: selectedProject, maxTargets: maxTargets, autoApprove: autoApprove))
            let (data, response) = try await session.data(for: req)
            try assertHTTP(response)
            let payload = String(data: data, encoding: .utf8) ?? ""
            lastAutopilotAt = Date()
            actionsInCurrentScope += 1
            lastAction = "Autopilot OK (\(selectedProject ?? "no-project")) \(payload.prefix(180))"
            await refresh()
        } catch {
            consecutiveErrors += 1
            self.error = "Autopilot failed: \(error.localizedDescription)"
        }
    }

    func runCommutedAutopilot(prompt: String, project: String?, autoApprove: Bool) async {
        if panicMode {
            self.error = "Panic mode active. Mutations blocked."
            return
        }
        let ordered = rankedTargets()
        let targets = Array(ordered.prefix(max(1, fanoutPerCycle)))
        if targets.isEmpty {
            await runAutopilot(prompt: prompt, maxTargets: 1, autoApprove: autoApprove, project: project)
            return
        }

        var cycleResults: [String] = []
        for pane in targets {
            if !isTargetEnabled(pane.target) { continue }
            let cooldown = throttleForTarget(pane.target).cooldownSec ?? autopilotCooldownSec
            if let last = lastAutopilotAtByTarget[pane.target], Date().timeIntervalSince(last) < cooldown {
                continue
            }
            await runAutopilot(prompt: prompt, maxTargets: 1, autoApprove: autoApprove, project: project)
            lastAutopilotAtByTarget[pane.target] = Date()
            cycleResults.append(pane.target)
            let delayMs = throttleForTarget(pane.target).delayMs ?? actionDelayMs
            let ns = UInt64(max(0, delayMs) * 1_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
        lastAction = "Commuted cycle over: \(cycleResults.joined(separator: ", "))"
    }

    func runScriptedNudges(sequence: [String], project: String?, autoApprove: Bool, pauseSec: Double) async {
        let steps = sequence.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !steps.isEmpty else {
            error = "Nudge script is empty"
            return
        }
        lastAction = "Running scripted nudges (\(steps.count) steps)"
        for (idx, prompt) in steps.enumerated() {
            await runCommutedAutopilot(prompt: prompt, project: project, autoApprove: autoApprove)
            if idx < steps.count - 1 {
                let ns = UInt64(max(0.5, pauseSec) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
        lastAction = "Scripted nudges complete (\(steps.count) steps)"
    }

    func runSmoke(project: String?) async -> String {
        if panicMode {
            self.error = "Panic mode active. Mutations blocked."
            return "panic-blocked"
        }
        let selectedProject = project ?? state?.projects.first?.path
        guard let selectedProject else {
            error = "Smoke skipped: no project selected"
            return "missing-project"
        }
        do {
            let url = pathURL("api/smoke")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["project": selectedProject]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: req)
            try assertHTTP(response)
            let text = String(data: data, encoding: .utf8) ?? ""
            lastAction = "Smoke executed for \(selectedProject)"
            cycleJournal.insert("smoke[\(selectedProject)]: \(text.prefix(160))", at: 0)
            actionsInCurrentScope += 1
            await refresh()
            return text
        } catch {
            consecutiveErrors += 1
            self.error = "Smoke failed: \(error.localizedDescription)"
            cycleJournal.insert("smoke-failed[\(selectedProject)]: \(error.localizedDescription)", at: 0)
            return "error"
        }
    }

    func runHealthyCycle(prompt: String, project: String?, autoApprove: Bool) async {
        if panicMode {
            self.error = "Panic mode active. Mutations blocked."
            return
        }
        guard completedCycles < max(1, scope.maxCycles) else {
            error = "Scope limit reached: max cycles \(scope.maxCycles)"
            return
        }
        let selectedProject = project ?? state?.projects.first?.path
        if scope.freezeOnDrift, (state?.queue.count ?? 0) > 6 {
            error = "Frozen by scope policy: queue depth too high"
            cycleJournal.insert("freeze: queue depth exceeded threshold", at: 0)
            return
        }

        cycleJournal.insert("cycle \(completedCycles + 1) start: \(scope.objective)", at: 0)
        await runCommutedAutopilot(prompt: prompt, project: selectedProject, autoApprove: autoApprove)
        let ns = UInt64(max(0, actionDelayMs) * 1_000_000)
        try? await Task.sleep(nanoseconds: ns)
        let smokeText = await runSmoke(project: selectedProject)
        completedCycles += 1
        cycleJournal.insert("cycle \(completedCycles) outcome: \(smokeText.prefix(120))", at: 0)
        recomputeInteractionHealth()
    }

    func resetCycleLedger() {
        completedCycles = 0
        cycleJournal.removeAll()
        actionsInCurrentScope = 0
        intentLatched = false
        latchedIntentChecksum = ""
        lastAction = "Cycle ledger reset"
    }

    func setLane(for target: String, lane: LanePriority) {
        laneByTarget[target] = lane
        if lane == .quarantine {
            var throttle = throttleByTarget[target] ?? SessionThrottle()
            throttle.enabled = false
            throttleByTarget[target] = throttle
        }
    }

    func lane(for target: String) -> LanePriority {
        laneByTarget[target] ?? .secondary
    }

    func setThrottle(for target: String, cooldownSec: Double?, delayMs: Double?) {
        var throttle = throttleByTarget[target] ?? SessionThrottle()
        throttle.cooldownSec = cooldownSec
        throttle.delayMs = delayMs
        throttleByTarget[target] = throttle
    }

    func setTargetEnabled(_ target: String, enabled: Bool) {
        var throttle = throttleByTarget[target] ?? SessionThrottle()
        throttle.enabled = enabled
        throttleByTarget[target] = throttle
    }

    func isTargetEnabled(_ target: String) -> Bool {
        throttleForTarget(target).enabled && lane(for: target) != .quarantine
    }

    func throttleForTarget(_ target: String) -> SessionThrottle {
        throttleByTarget[target] ?? SessionThrottle()
    }

    func engagePanic(reason: String = "manual") {
        panicMode = true
        panicReason = reason
        for pane in state?.takeoverCandidates ?? [] {
            setLane(for: pane.target, lane: .quarantine)
        }
        lastAction = "PANIC engaged (\(reason)). Read-only mode."
    }

    func clearPanic() {
        panicMode = false
        panicReason = ""
        lastAction = "Panic cleared. Mutations re-enabled."
    }

    func latchIntent(_ text: String) {
        scope.intentLatch = text
        latchedIntentChecksum = checksumForIntent(text)
        intentLatched = !latchedIntentChecksum.isEmpty
        actionsInCurrentScope = 0
        lastAction = intentLatched ? "Intent latched (\(latchedIntentChecksum))" : "Intent latch failed"
    }

    func clearIntentLatch() {
        intentLatched = false
        latchedIntentChecksum = ""
        actionsInCurrentScope = 0
        lastAction = "Intent latch cleared"
    }

    func setBaseURL(_ text: String) {
        guard let url = URL(string: text), url.scheme != nil, url.host != nil else {
            error = "Invalid URL: \(text)"
            return
        }
        baseURL = url
    }

    func choosePreset(_ preset: String) {
        setBaseURL(preset)
    }

    func probeAndSelectBestEndpoint() async {
        probes = []
        var best: SurfaceProbe?
        let candidates = endpointCandidates()

        for candidate in candidates {
            let probe = await probe(candidate)
            probes.append(probe)
            if best == nil, probe.stateReachable {
                best = probe
            } else if let current = best, probe.stateReachable, probe.candidates > current.candidates {
                best = probe
            }
        }

        if let best {
            baseURL = best.baseURL
            lastAction = "Selected \(best.baseURL.absoluteString)"
            await refresh()
        } else {
            error = "No reachable API surface discovered"
        }
    }

    private func probe(_ url: URL) async -> SurfaceProbe {
        let healthURL = url.appending(path: "health")
        let stateURL = url.appending(path: "api/state")
        var healthy = false
        var stateReachable = false
        var sessions = 0
        var candidates = 0
        var smoke = "unknown"
        var err: String?

        do {
            let (healthData, _) = try await session.data(from: healthURL)
            if let json = try? JSONSerialization.jsonObject(with: healthData) as? [String: Any] {
                healthy = String(describing: json["status"] ?? "") == "ok"
            }
        } catch {
            err = "health: \(error.localizedDescription)"
        }

        do {
            let (stateData, response) = try await session.data(from: stateURL)
            try assertHTTP(response)
            if let raw = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any] {
                stateReachable = true
                sessions = (raw["sessions"] as? [Any])?.count ?? 0
                candidates = (raw["takeover_candidates"] as? [Any])?.count ?? 0
                if let smokeMap = raw["smoke"] as? [String: Any] {
                    smoke = String(describing: smokeMap["status"] ?? "unknown")
                }
            }
        } catch {
            err = "state: \(error.localizedDescription)"
        }

        return SurfaceProbe(
            baseURL: url,
            healthy: healthy,
            stateReachable: stateReachable,
            sessions: sessions,
            candidates: candidates,
            smokeStatus: smoke,
            error: err
        )
    }

    private func endpointCandidates() -> [URL] {
        var urls: [URL] = []
        let seeds = endpointPresets + [baseURL.absoluteString]
        for seed in seeds {
            if let url = URL(string: seed) {
                urls.append(url)
            }
        }
        let hosts = ["173.212.203.211", "149.102.153.201", "hyle.hyperstitious.org", "hyperstitious.art"]
        let ports = [8788, 9801, 9750]
        for host in hosts {
            for port in ports {
                if let url = URL(string: "http://\(host):\(port)") {
                    urls.append(url)
                }
            }
        }
        return Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
    }

    private func pathURL(_ path: String) -> URL {
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        return URL(string: "\(base)/\(path)")!
    }

    private func assertHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func recomputeInteractionHealth() {
        guard let s = state else {
            interactionHealth = InteractionHealth(score: 20, label: "Disconnected", notes: ["No live state"])
            agitationScore = 80
            return
        }
        var score = 100
        var notes: [String] = []
        var agitation = 0

        if s.takeoverCandidates.isEmpty {
            score -= 20
            notes.append("No takeover candidates visible.")
            agitation += 15
        } else {
            notes.append("Candidates visible: \(s.takeoverCandidates.count).")
        }

        if s.smoke.status.lowercased() != "pass" {
            score -= 25
            notes.append("Smoke status not pass: \(s.smoke.status).")
            agitation += 20
        } else {
            notes.append("Smoke status pass.")
        }

        if s.queue.count > 6 {
            score -= 15
            notes.append("Queue depth high (\(s.queue.count)); risk of drift.")
            agitation += 20
        }

        if completedCycles >= max(1, scope.maxCycles) {
            score -= 10
            notes.append("Reached cycle limit; require human review.")
            agitation += 10
        }

        if scope.requireIntentLatch && !intentLatched {
            score -= 10
            notes.append("Intent latch missing.")
            agitation += 15
        }

        if panicMode {
            score -= 5
            notes.append("Panic mode active (read-only containment).")
            agitation = max(0, agitation - 20)
        }

        if actionsInCurrentScope > scope.attentionBudgetActions {
            score -= 15
            notes.append("Attention budget exceeded.")
            agitation += 20
        }

        if consecutiveErrors > 0 {
            score -= min(15, consecutiveErrors * 3)
            notes.append("Recent errors: \(consecutiveErrors).")
            agitation += min(20, consecutiveErrors * 4)
        }

        let label: String
        switch score {
        case 85...100: label = "Healthy"
        case 65..<85: label = "Watchful"
        case 45..<65: label = "Strained"
        default: label = "Unhealthy"
        }
        agitationScore = min(100, max(0, agitation))
        interactionHealth = InteractionHealth(score: max(0, score), label: label, notes: notes)
    }

    private func checksumForIntent(_ text: String) -> String {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        let scalar = normalized.unicodeScalars.reduce(0) { ($0 * 131 + Int($1.value)) % 1000003 }
        return String(format: "%06d", scalar % 1000000)
    }

    private func computeDelta() {
        guard let s = state else { return }
        let candidateDelta = s.takeoverCandidates.count - previousCandidateCount
        let smokeChanged = previousSmokeStatus != s.smoke.status
        var segments: [String] = []
        segments.append("candidates \(previousCandidateCount)->\(s.takeoverCandidates.count) (\(candidateDelta >= 0 ? "+" : "")\(candidateDelta))")
        if smokeChanged {
            segments.append("smoke \(previousSmokeStatus)->\(s.smoke.status)")
        } else {
            segments.append("smoke \(s.smoke.status) (unchanged)")
        }
        segments.append("queue \(s.queue.count)")
        lastDelta = segments.joined(separator: " | ")
        previousCandidateCount = s.takeoverCandidates.count
        previousSmokeStatus = s.smoke.status
    }

    private func rankedTargets() -> [PaneInfo] {
        let cands = state?.takeoverCandidates ?? []
        return cands.sorted { a, b in
            let la = laneRank(lane(for: a.target))
            let lb = laneRank(lane(for: b.target))
            if la != lb { return la < lb }
            if a.throughputBps != b.throughputBps { return a.throughputBps > b.throughputBps }
            return a.target < b.target
        }
    }

    private func laneRank(_ lane: LanePriority) -> Int {
        switch lane {
        case .primary: return 0
        case .secondary: return 1
        case .quarantine: return 2
        }
    }
}
