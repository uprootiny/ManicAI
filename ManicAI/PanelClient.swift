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
    @Published var actionLog: [String] = []
    @Published var capabilities = APICapabilities()
    @Published var isRefreshing: Bool = false
    @Published var apiStatsByRoute: [String: APICallStats] = [:]
    @Published var apiStatsByNodeRoute: [String: APICallStats] = [:]
    @Published var panicMode: Bool = false
    @Published var panicReason: String = ""
    @Published var degradedMode: Bool = false
    @Published var degradedReason: String = ""
    @Published var laneByTarget: [String: LanePriority] = [:]
    @Published var throttleByTarget: [String: SessionThrottle] = [:]
    @Published var autoTuneScheduler: Bool = true
    @Published var minFluencyForPrimary: Int = 65
    @Published var enableFallbackRouting: Bool = true
    @Published var fallbackFluencyThreshold: Int = 45
    @Published var schedulerNotes: [String] = []
    @Published var commutationPreview: [CommutationPlanStep] = []
    @Published var telemetryHalfLifeHours: Int = 24
    @Published var telemetryLoadedAt: Date?
    @Published var breakerConfig = BreakerConfig()
    @Published var routeBreakers: [String: BreakerState] = [:]
    @Published var nodeRouteBreakers: [String: BreakerState] = [:]
    @Published var cadenceBackoffFactor: Double = 1.0
    @Published var cadenceNote: String = "normal"
    @Published var promptHistory: [PromptEvent] = []
    @Published var cadenceReport: String = ""
    @Published var promptHistoryPath: String = ""
    @Published var cadenceReportPath: String = ""
    @Published var profileSnapshotPath: String = ""
    @Published var profileSnapshotMarkdownPath: String = ""
    @Published var layerEdges: [LayerEdgeMetric] = []
    @Published var eventBudgetSummary: String = ""
    @Published var performance = PerformanceSnapshot()
    @Published var highPressureMode: Bool = false
    @Published var highPressureReason: String = ""
    private var lastAutopilotAt: Date?
    private var lastAutopilotAtByTarget: [String: Date] = [:]
    private var refreshQueued: Bool = false
    private var lastCapabilityScanAt: Date?
    private var lastStateServiceEventAt: Date?
    private var refreshSamplesMs: [Double] = []
    private var droppedStateServiceEvents: Int = 0
    private var consecutiveErrors: Int = 0
    private var previousCandidateCount: Int = 0
    private var previousSmokeStatus: String = "unknown"
    private var persistTask: Task<Void, Never>?
    private var recomputeTask: Task<Void, Never>?

    private let maxPromptHistoryEntries = 2000
    private let maxPersistedPromptEntries = 600
    private let maxActionLogEntries = 200
    private let maxSchedulerNotesEntries = 200

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let session: URLSession
    private let allowLocalFallback: Bool
    private static let logFormatter = ISO8601DateFormatter()
    private static let routeStatsKey = "manicai.telemetry.routeStats.v1"
    private static let nodeStatsKey = "manicai.telemetry.nodeStats.v1"
    private static let actionLogKey = "manicai.telemetry.actionLog.v1"
    private static let schedulerNotesKey = "manicai.telemetry.schedulerNotes.v1"
    private static let promptHistoryMemKey = "manicai.telemetry.promptHistory.v1"

    var baseURL: URL {
        didSet { UserDefaults.standard.set(baseURL.absoluteString, forKey: "manicai.baseURL") }
    }

    let endpointPresets: [String] = [
        "http://173.212.203.211:8788",
        "http://173.212.203.211:8421",
        "http://hyle.hyperstitious.org:8788",
        "http://hyle.hyperstitious.org:8421",
        "http://hyperstitious.art:8788",
        "http://hyperstitious.art:8421",
        "http://149.102.153.201:8788",
        "http://149.102.153.201:8421",
        "http://173.212.203.211:9801",
        "http://173.212.203.211:9750"
    ]

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 2.5
        cfg.timeoutIntervalForResource = 5.0
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
        self.allowLocalFallback = ProcessInfo.processInfo.environment["MANICAI_ALLOW_LOCAL"] == "1"
        let saved = UserDefaults.standard.string(forKey: "manicai.baseURL")
        if
            let saved,
            let savedURL = URL(string: saved),
            !Self.isLoopbackHost(savedURL.host),
            savedURL.scheme != nil
        {
            self.baseURL = savedURL
        } else {
            self.baseURL = URL(string: "http://173.212.203.211:8788")!
        }
        if let cooldown = UserDefaults.standard.object(forKey: "manicai.autopilotCooldownSec") as? Double {
            autopilotCooldownSec = cooldown
        }
        if let delay = UserDefaults.standard.object(forKey: "manicai.actionDelayMs") as? Double {
            actionDelayMs = delay
        }
        if let fanout = UserDefaults.standard.object(forKey: "manicai.fanoutPerCycle") as? Int {
            fanoutPerCycle = fanout
        }
        if let hl = UserDefaults.standard.object(forKey: "manicai.telemetry.halfLifeHours") as? Int {
            telemetryHalfLifeHours = max(1, hl)
        }
        loadTelemetryMemory()
        let urls = historyURLs()
        promptHistoryPath = urls.history.path
        cadenceReportPath = urls.report.path
        let profile = profileURLs()
        profileSnapshotPath = profile.json.path
        profileSnapshotMarkdownPath = profile.markdown.path
    }

    func refresh() async {
        if isRefreshing {
            refreshQueued = true
            return
        }
        let t0 = Date()
        isRefreshing = true
        do {
            let url = pathURL("api/state")
            let (data, response) = try await session.data(from: url)
            try assertHTTP(response)
            state = try decoder.decode(PanelState.self, from: data)
            error = nil
            consecutiveErrors = 0
            lastAction = "Refreshed \(baseURL.host ?? "unknown")"
            log("refresh ok: \(baseURL.absoluteString)")
            if shouldRecordStateServiceEvent() {
                recordTimelineEvent(kind: .service, route: "api/state", target: baseURL.host, text: "refresh ok")
                lastStateServiceEventAt = Date()
            } else {
                droppedStateServiceEvents += 1
            }
            if shouldScanCapabilities() {
                await detectCapabilities()
                lastCapabilityScanAt = Date()
            }
            computeDelta()
            commutationPreview = buildCommutationPlan(route: "autopilot/run")
            recomputeInteractionHealth()
        } catch {
            consecutiveErrors += 1
            self.error = "Refresh failed: \(error.localizedDescription)"
            log("refresh failed: \(error.localizedDescription)")
            recordTimelineEvent(kind: .service, route: "api/state", target: baseURL.host, text: "refresh failed: \(error.localizedDescription)")
        }
        recordRefreshDurationMs(Date().timeIntervalSince(t0) * 1000)
        isRefreshing = false
        if refreshQueued {
            refreshQueued = false
            await refresh()
        }
    }

    func runAutopilot(prompt: String, maxTargets: Int = 2, autoApprove: Bool = true, project: String? = nil, nodeHint: String? = nil) async {
        if panicMode {
            self.error = "Panic mode active. Mutations blocked."
            return
        }
        if let deny = denyReason(route: "autopilot/run", nodeHint: nodeHint) {
            self.error = deny
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
            recordPromptEvent(route: "autopilot/run", target: nodeHint, prompt: prompt)
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
            log("autopilot ok: \(payload.prefix(120))")
            recordTimelineEvent(kind: .service, route: "api/autopilot/run", target: nodeHint, text: "ok")
            recordArtifactEvents(from: payload, target: nodeHint)
            markRoute("autopilot/run", ok: true, nodeHint: nodeHint)
            await refresh()
        } catch {
            consecutiveErrors += 1
            self.error = "Autopilot failed: \(error.localizedDescription)"
            log("autopilot failed: \(error.localizedDescription)")
            recordTimelineEvent(kind: .service, route: "api/autopilot/run", target: nodeHint, text: "failed: \(error.localizedDescription)")
            markRoute("autopilot/run", ok: false, nodeHint: nodeHint)
        }
    }

    func autopilotPreflightReason(nodeHint: String? = nil) -> String? {
        if panicMode {
            return "Panic mode active. Mutations blocked."
        }
        if let deny = denyReason(route: "autopilot/run", nodeHint: nodeHint) {
            return deny
        }
        if scope.requireIntentLatch {
            let checksum = checksumForIntent(scope.intentLatch)
            if !intentLatched || checksum.isEmpty || checksum != latchedIntentChecksum {
                return "Intent not latched. Update latch before action."
            }
        }
        if actionsInCurrentScope >= max(1, scope.attentionBudgetActions) {
            return "Attention budget exceeded (\(scope.attentionBudgetActions) actions). Re-anchor intent."
        }
        if let last = lastAutopilotAt {
            let gap = Date().timeIntervalSince(last)
            if gap < autopilotCooldownSec {
                let remain = Int((autopilotCooldownSec - gap).rounded(.up))
                return "Autopilot throttled: wait \(remain)s"
            }
        }
        return nil
    }

    func runCommutedAutopilot(prompt: String, project: String?, autoApprove: Bool) async {
        if panicMode {
            self.error = "Panic mode active. Mutations blocked."
            return
        }
        if degradedMode {
            noteScheduler("degraded mode: commuted autopilot skipped")
            return
        }
        let plan = buildCommutationPlan(route: "autopilot/run")
        commutationPreview = plan
        if plan.isEmpty {
            await runAutopilot(prompt: prompt, maxTargets: 1, autoApprove: autoApprove, project: project)
            return
        }

        var cycleResults: [String] = []
        for step in plan {
            let paneTarget = step.target
            if !isTargetEnabled(paneTarget) { continue }
            let cooldown = throttleForTarget(paneTarget).cooldownSec ?? autopilotCooldownSec
            if let last = lastAutopilotAtByTarget[paneTarget], Date().timeIntervalSince(last) < cooldown {
                continue
            }
            switch step.strategy {
            case .autopilot:
                await runAutopilot(prompt: prompt, maxTargets: 1, autoApprove: autoApprove, project: project, nodeHint: paneTarget)
            case .paneSmokeFallback:
                noteScheduler("fallback engage \(paneTarget): pane/send + smoke (\(step.reason))")
                let send = await paneSend(target: paneTarget, text: prompt, enter: true)
                if send.contains("failed") {
                    markRoute("fallback", ok: false, nodeHint: paneTarget)
                } else {
                    _ = await runSmoke(project: project)
                    markRoute("fallback", ok: true, nodeHint: paneTarget)
                }
            }
            lastAutopilotAtByTarget[paneTarget] = Date()
            cycleResults.append("\(paneTarget):\(step.strategy.rawValue)")
            maybeRetuneLane(target: paneTarget, route: "autopilot/run")
            let delayMs = throttleForTarget(paneTarget).delayMs ?? actionDelayMs
            let effectiveDelayMs = delayMs * cadenceBackoffFactor
            let ns = UInt64(max(0, effectiveDelayMs) * 1_000_000)
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
        if let deny = denyReason(route: "smoke", nodeHint: nil) {
            self.error = deny
            return "breaker-blocked"
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
            log("smoke ok[\(selectedProject)]: \(text.prefix(120))")
            recordTimelineEvent(kind: .service, route: "api/smoke", target: selectedProject, text: "ok")
            recordArtifactEvents(from: text, target: selectedProject)
            markRoute("smoke", ok: true)
            await refresh()
            return text
        } catch {
            consecutiveErrors += 1
            self.error = "Smoke failed: \(error.localizedDescription)"
            cycleJournal.insert("smoke-failed[\(selectedProject)]: \(error.localizedDescription)", at: 0)
            log("smoke failed[\(selectedProject)]: \(error.localizedDescription)")
            recordTimelineEvent(kind: .service, route: "api/smoke", target: selectedProject, text: "failed: \(error.localizedDescription)")
            markRoute("smoke", ok: false)
            return "error"
        }
    }

    func queueAdd(prompt: String, project: String?, sessionID: String?) async -> String {
        recordPromptEvent(route: "queue/add", target: sessionID, prompt: prompt)
        let payload: [String: Any] = [
            "prompt": prompt,
            "project": project ?? "",
            "session_id": sessionID ?? ""
        ]
        return await mutate(path: "api/queue/add", payload: payload, action: "queue/add")
    }

    func queueRun(project: String?, sessionID: String?) async -> String {
        let payload: [String: Any] = [
            "project": project ?? "",
            "session_id": sessionID ?? ""
        ]
        return await mutate(path: "api/queue/run", payload: payload, action: "queue/run")
    }

    func paneSend(target: String, text: String, enter: Bool = true) async -> String {
        recordPromptEvent(route: "pane/send", target: target, prompt: text)
        let payload: [String: Any] = [
            "target": target,
            "text": text,
            "enter": enter
        ]
        return await mutate(path: "api/pane/send", payload: payload, action: "pane/send", nodeHint: target)
    }

    func nudge(sessionID: String, text: String) async -> String {
        recordPromptEvent(route: "nudge", target: sessionID, prompt: text)
        let payload: [String: Any] = [
            "session_id": sessionID,
            "text": text
        ]
        return await mutate(path: "api/nudge", payload: payload, action: "nudge", nodeHint: sessionID)
    }

    func snapshotIngest(name: String, text: String) async -> String {
        let payload: [String: Any] = [
            "name": name,
            "text": text
        ]
        return await mutate(path: "api/snapshot/ingest", payload: payload, action: "snapshot/ingest")
    }

    func spawn(sessionName: String, project: String?, command: String) async -> String {
        let payload: [String: Any] = [
            "session_name": sessionName,
            "project": project ?? "",
            "command": command
        ]
        return await mutate(path: "api/spawn", payload: payload, action: "spawn", nodeHint: sessionName)
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

    func fluencyForTarget(_ target: String, route: String) -> Int {
        let key = "\(target)|\(route)"
        if let stat = apiStatsByNodeRoute[key], stat.total > 0 {
            return stat.fluency
        }
        if let global = apiStatsByRoute[route], global.total > 0 {
            return global.fluency
        }
        return 0
    }

    func statsForTarget(_ target: String, route: String) -> APICallStats {
        apiStatsByNodeRoute["\(target)|\(route)"] ?? APICallStats()
    }

    func engagePanic(reason: String = "manual") {
        panicMode = true
        panicReason = reason
        degradedMode = true
        degradedReason = "panic"
        for pane in state?.takeoverCandidates ?? [] {
            setLane(for: pane.target, lane: .quarantine)
        }
        lastAction = "PANIC engaged (\(reason)). Read-only mode."
    }

    func clearPanic() {
        panicMode = false
        panicReason = ""
        degradedMode = false
        degradedReason = ""
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
            log("invalid url: \(text)")
            return
        }
        baseURL = url
        log("endpoint set: \(url.absoluteString)")
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
            log("endpoint auto-selected: \(best.baseURL.absoluteString)")
            await refresh()
        } else {
            error = "No reachable API surface discovered"
            log("recon failed: no reachable api surface")
        }
    }

    private func probe(_ url: URL) async -> SurfaceProbe {
        let healthURL = url.appending(path: "health")
        let stateURL = url.appending(path: "api/state")
        let tmuxURL = url.appending(path: "tmux")
        var healthy = false
        var stateReachable = false
        var stateLatencyMs: Int?
        var stateKind = "unknown"
        var stateTurn: Int?
        var sessions = 0
        var candidates = 0
        var smoke = "unknown"
        var tmuxReachable = false
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
            let t0 = Date()
            let (stateData, response) = try await session.data(from: stateURL)
            try assertHTTP(response)
            stateLatencyMs = Int((Date().timeIntervalSince(t0) * 1000).rounded())
            if let raw = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any] {
                stateReachable = true
                if raw["sessions"] is [Any] || raw["takeover_candidates"] is [Any] {
                    stateKind = "hyperpanel"
                    sessions = (raw["sessions"] as? [Any])?.count ?? 0
                    candidates = (raw["takeover_candidates"] as? [Any])?.count ?? 0
                    if let smokeMap = raw["smoke"] as? [String: Any] {
                        smoke = String(describing: smokeMap["status"] ?? "unknown")
                    }
                } else if raw["atoms"] is [String: Any] || raw["turn"] != nil {
                    stateKind = "coggy"
                    stateTurn = raw["turn"] as? Int
                    sessions = 1
                    candidates = 0
                    smoke = "n/a"
                }
            }
        } catch {
            err = "state: \(error.localizedDescription)"
        }

        do {
            let (tmuxData, response) = try await session.data(from: tmuxURL)
            try assertHTTP(response)
            let html = String(data: tmuxData, encoding: .utf8) ?? ""
            tmuxReachable = html.contains("<html") || html.contains("TMUX")
        } catch {
            if err == nil {
                err = "tmux: \(error.localizedDescription)"
            }
        }

        return SurfaceProbe(
            baseURL: url,
            healthy: healthy,
            stateReachable: stateReachable,
            stateLatencyMs: stateLatencyMs,
            stateKind: stateKind,
            stateTurn: stateTurn,
            sessions: sessions,
            candidates: candidates,
            smokeStatus: smoke,
            tmuxReachable: tmuxReachable,
            tmuxURL: tmuxURL,
            error: err
        )
    }

    private func endpointCandidates() -> [URL] {
        var urls: [URL] = []
        var seen: Set<String> = []

        func appendUnique(_ raw: String) {
            guard let url = URL(string: raw), let scheme = url.scheme, let host = url.host else { return }
            if !allowLocalFallback && isLoopbackHost(host) { return }
            let key = "\(scheme)://\(host):\(url.port ?? (scheme == "https" ? 443 : 80))"
            if seen.insert(key).inserted {
                urls.append(url)
            }
        }

        for seed in endpointPresets {
            appendUnique(seed)
        }
        appendUnique(baseURL.absoluteString)
        if allowLocalFallback {
            appendUnique("http://127.0.0.1:8788")
        }
        let hosts = ["173.212.203.211", "149.102.153.201", "hyle.hyperstitious.org", "hyperstitious.art", "hypersticial.art"]
        let ports = [8788, 8421, 9801, 9750]
        for host in hosts {
            for port in ports {
                appendUnique("http://\(host):\(port)")
            }
        }
        return urls
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func isLoopbackHost(_ host: String?) -> Bool {
        Self.isLoopbackHost(host)
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

    private func detectCapabilities() async {
        capabilities.state = await endpointOKGet("api/state")
        let routes = await fetchRouteHints()
        capabilities.autopilot = routes.contains("/api/autopilot/run")
        capabilities.smoke = routes.contains("/api/smoke")
        capabilities.paneSend = routes.contains("/api/pane/send")
        capabilities.queue = routes.contains("/api/queue/add")
        capabilities.queueRun = routes.contains("/api/queue/run")
        capabilities.spawn = routes.contains("/api/spawn")
        capabilities.nudge = routes.contains("/api/nudge")
        capabilities.snapshotIngest = routes.contains("/api/snapshot/ingest")
    }

    private func endpointOKGet(_ path: String) async -> Bool {
        do {
            let (_, response) = try await session.data(from: pathURL(path))
            if let http = response as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    private func fetchRouteHints() async -> Set<String> {
        do {
            let (data, response) = try await session.data(from: pathURL(""))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return []
            }
            let html = String(data: data, encoding: .utf8) ?? ""
            var hits: Set<String> = []
            let known = ["/api/autopilot/run", "/api/smoke", "/api/pane/send", "/api/queue/add", "/api/queue/run", "/api/spawn", "/api/nudge", "/api/snapshot/ingest"]
            for route in known where html.contains(route) {
                hits.insert(route)
            }
            return hits
        } catch {
            return []
        }
    }

    private func log(_ message: String) {
        let ts = Self.logFormatter.string(from: Date())
        actionLog.insert("[\(ts)] \(message)", at: 0)
        if actionLog.count > maxActionLogEntries { actionLog = Array(actionLog.prefix(maxActionLogEntries)) }
        updateEventBudgetSummary()
        queuePersistence()
    }

    private func noteScheduler(_ message: String) {
        let ts = Self.logFormatter.string(from: Date())
        schedulerNotes.insert("[\(ts)] \(message)", at: 0)
        if schedulerNotes.count > maxSchedulerNotesEntries { schedulerNotes = Array(schedulerNotes.prefix(maxSchedulerNotesEntries)) }
        updateEventBudgetSummary()
        queuePersistence()
    }

    private func mutate(path: String, payload: [String: Any], action: String, nodeHint: String? = nil) async -> String {
        if panicMode {
            self.error = "Panic mode active. Mutations blocked."
            return "panic-blocked"
        }
        if let deny = denyReason(route: action, nodeHint: nodeHint) {
            self.error = deny
            return "breaker-blocked"
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            var req = URLRequest(url: pathURL(path))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            let (respData, response) = try await session.data(for: req)
            try assertHTTP(response)
            let text = String(data: respData, encoding: .utf8) ?? ""
            lastAction = "\(action) ok"
            log("\(action) ok: \(text.prefix(140))")
            recordTimelineEvent(kind: .service, route: "api/\(action)", target: nodeHint, text: "ok")
            recordArtifactEvents(from: text, target: nodeHint)
            markRoute(action, ok: true, nodeHint: nodeHint)
            await refresh()
            return text
        } catch {
            let msg = "\(action) failed: \(error.localizedDescription)"
            self.error = msg
            log(msg)
            recordTimelineEvent(kind: .service, route: "api/\(action)", target: nodeHint, text: msg)
            markRoute(action, ok: false, nodeHint: nodeHint)
            return msg
        }
    }

    private func markRoute(_ route: String, ok: Bool, nodeHint: String? = nil) {
        var global = apiStatsByRoute[route] ?? APICallStats()
        if ok { global.success += 1 } else { global.failure += 1 }
        apiStatsByRoute[route] = global
        recordBreakerOutcome(route: route, ok: ok)

        if let nodeHint, !nodeHint.isEmpty {
            let key = "\(nodeHint)|\(route)"
            var scoped = apiStatsByNodeRoute[key] ?? APICallStats()
            if ok { scoped.success += 1 } else { scoped.failure += 1 }
            apiStatsByNodeRoute[key] = scoped
            recordBreakerOutcome(route: route, nodeHint: nodeHint, ok: ok)
        }
        recomputeDegradedMode()
        queuePersistence()
    }

    func setTelemetryHalfLifeHours(_ hours: Int) {
        telemetryHalfLifeHours = max(1, hours)
        UserDefaults.standard.set(telemetryHalfLifeHours, forKey: "manicai.telemetry.halfLifeHours")
        loadTelemetryMemory()
    }

    func clearTelemetryMemory() {
        persistTask?.cancel()
        recomputeTask?.cancel()
        apiStatsByRoute = [:]
        apiStatsByNodeRoute = [:]
        actionLog = []
        schedulerNotes = []
        promptHistory = []
        layerEdges = []
        eventBudgetSummary = ""
        performance = PerformanceSnapshot()
        highPressureMode = false
        highPressureReason = ""
        refreshSamplesMs = []
        droppedStateServiceEvents = 0
        UserDefaults.standard.removeObject(forKey: Self.routeStatsKey)
        UserDefaults.standard.removeObject(forKey: Self.nodeStatsKey)
        UserDefaults.standard.removeObject(forKey: Self.actionLogKey)
        UserDefaults.standard.removeObject(forKey: Self.schedulerNotesKey)
        UserDefaults.standard.removeObject(forKey: Self.promptHistoryMemKey)
        telemetryLoadedAt = Date()
        lastAction = "Telemetry memory cleared"
    }

    func resetBreakers() {
        routeBreakers = [:]
        nodeRouteBreakers = [:]
        recomputeDegradedMode()
        lastAction = "Breakers reset"
    }

    func ingestSyntheticOutcome(route: String, nodeHint: String? = nil, ok: Bool) {
        markRoute(route, ok: ok, nodeHint: nodeHint)
    }

    func effectiveRefreshCadence(baseSeconds: Double) -> Double {
        let pressureFactor = highPressureMode ? 1.8 : 1.0
        return max(2, baseSeconds * cadenceBackoffFactor * pressureFactor)
    }

    func exportPromptHistoryAndCadenceReport() {
        do {
            let urls = historyURLs()
            let encoder = JSONEncoder()
            var blob = ""
            for event in promptHistory.sorted(by: { $0.ts < $1.ts }) {
                let line = try String(data: encoder.encode(event), encoding: .utf8) ?? ""
                blob += line + "\n"
            }
            try ensureHistoryDirectory()
            try blob.write(to: urls.history, atomically: true, encoding: .utf8)
            let report = generateCadenceReport()
            try report.write(to: urls.report, atomically: true, encoding: .utf8)
            cadenceReport = report
            promptHistoryPath = urls.history.path
            cadenceReportPath = urls.report.path
            lastAction = "Wrote prompt history + cadence report"
            log("history export: \(urls.history.path), report: \(urls.report.path)")
        } catch {
            self.error = "History export failed: \(error.localizedDescription)"
            log("history export failed: \(error.localizedDescription)")
        }
    }

    func exportSessionProfileSnapshot() {
        do {
            try ensureHistoryDirectory()
            let profile = currentSessionProfileSnapshot()
            let urls = profileURLs()
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(profile)
            try data.write(to: urls.json, options: .atomic)
            let md = renderProfileMarkdown(profile)
            try md.write(to: urls.markdown, atomically: true, encoding: .utf8)
            profileSnapshotPath = urls.json.path
            profileSnapshotMarkdownPath = urls.markdown.path
            lastAction = "Session profile exported"
            log("profile export: \(urls.json.path)")
        } catch {
            self.error = "Profile export failed: \(error.localizedDescription)"
            log("profile export failed: \(error.localizedDescription)")
        }
    }

    func deletePromptEvents(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        promptHistory.removeAll { ids.contains($0.id) }
        cadenceReport = generateCadenceReport()
        queueRecomputeLayerEdges()
        queuePersistence()
        lastAction = "Deleted \(ids.count) prompt events"
    }

    func pastePromptClip(_ lines: [String], target: String?, route: String = "replay/paste") {
        let clean = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        for (i, line) in clean.enumerated() {
            let event = PromptEvent(
                id: UUID(),
                ts: now + Double(i) * 0.001,
                route: route,
                target: target,
                prompt: line
            )
            promptHistory.append(event)
        }
        trimEventMemory()
        cadenceReport = generateCadenceReport()
        queueRecomputeLayerEdges()
        queuePersistence()
        lastAction = "Pasted \(clean.count) clip lines into \(target ?? "-")"
    }

    func replayLayerEdge(_ edge: LayerEdgeMetric, target: String?) async -> String {
        let events = TimelineEngine.sortedEvents(promptHistory)
        guard events.count > 1 else { return "no history for edge replay" }
        var candidate: PromptEvent?
        var previous: PromptEvent?
        for (cur, prev) in zip(events.dropFirst(), events) {
            if prev.kind == edge.from && cur.kind == edge.to {
                candidate = cur
                previous = prev
            }
        }
        guard let ev = candidate else { return "no matching edge instance found" }
        let t = (target?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? target! : (ev.target ?? previous?.target ?? ""))
        if t.isEmpty { return "no target available for replay" }
        let msg = "[edge \(edge.from.rawValue)->\(edge.to.rawValue)] \(ev.prompt)"
        return await paneSend(target: t, text: msg, enter: true)
    }

    private func loadTelemetryMemory() {
        let now = Date()
        let halfLifeSec = TimeInterval(telemetryHalfLifeHours) * 3600

        if let data = UserDefaults.standard.data(forKey: Self.routeStatsKey),
           let decoded = try? decoder.decode([String: StoredAPICallStats].self, from: data) {
            let decayed = TelemetryMemory.applyDecay(to: decoded, now: now, halfLifeSec: halfLifeSec)
            apiStatsByRoute = decayed.mapValues { APICallStats(success: $0.success, failure: $0.failure) }
        }

        if let data = UserDefaults.standard.data(forKey: Self.nodeStatsKey),
           let decoded = try? decoder.decode([String: StoredAPICallStats].self, from: data) {
            let decayed = TelemetryMemory.applyDecay(to: decoded, now: now, halfLifeSec: halfLifeSec)
            apiStatsByNodeRoute = decayed.mapValues { APICallStats(success: $0.success, failure: $0.failure) }
        }

        if let data = UserDefaults.standard.data(forKey: Self.actionLogKey),
           let decoded = try? decoder.decode([String].self, from: data) {
            actionLog = Array(decoded.prefix(maxActionLogEntries))
        }
        if let data = UserDefaults.standard.data(forKey: Self.schedulerNotesKey),
           let decoded = try? decoder.decode([String].self, from: data) {
            schedulerNotes = Array(decoded.prefix(maxSchedulerNotesEntries))
        }
        if let data = UserDefaults.standard.data(forKey: Self.promptHistoryMemKey),
           let decoded = try? decoder.decode([PromptEvent].self, from: data) {
            promptHistory = Array(decoded.suffix(maxPersistedPromptEntries))
        }
        cadenceReport = generateCadenceReport()
        recomputeLayerEdges()
        trimEventMemory()
        updateEventBudgetSummary()
        telemetryLoadedAt = now
        queuePersistence()
    }

    private func persistTelemetryMemory() {
        let now = Date().timeIntervalSince1970
        let routeStored = apiStatsByRoute.mapValues { StoredAPICallStats(success: $0.success, failure: $0.failure, updatedAt: now) }
        let nodeStored = apiStatsByNodeRoute.mapValues { StoredAPICallStats(success: $0.success, failure: $0.failure, updatedAt: now) }
        if let data = try? encoder.encode(routeStored) {
            UserDefaults.standard.set(data, forKey: Self.routeStatsKey)
        }
        if let data = try? encoder.encode(nodeStored) {
            UserDefaults.standard.set(data, forKey: Self.nodeStatsKey)
        }
        if let data = try? encoder.encode(Array(actionLog.prefix(maxActionLogEntries))) {
            UserDefaults.standard.set(data, forKey: Self.actionLogKey)
        }
        if let data = try? encoder.encode(Array(schedulerNotes.prefix(maxSchedulerNotesEntries))) {
            UserDefaults.standard.set(data, forKey: Self.schedulerNotesKey)
        }
        if let data = try? encoder.encode(Array(promptHistory.suffix(maxPersistedPromptEntries))) {
            UserDefaults.standard.set(data, forKey: Self.promptHistoryMemKey)
        }
        performance.persistFlushes += 1
        performance.persistQueued = false
    }

    private func shouldScanCapabilities() -> Bool {
        guard let last = lastCapabilityScanAt else { return true }
        return Date().timeIntervalSince(last) > 30
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
        if degradedMode {
            score -= 15
            notes.append("Degraded mode active: \(degradedReason).")
            agitation += 10
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

    private func rankedTargets(route: String) -> [PaneInfo] {
        let cands = state?.takeoverCandidates ?? []
        return cands.sorted { a, b in
            let la = laneRank(lane(for: a.target))
            let lb = laneRank(lane(for: b.target))
            if la != lb { return la < lb }
            let fa = fluencyForTarget(a.target, route: route)
            let fb = fluencyForTarget(b.target, route: route)
            if fa != fb { return fa > fb }
            if a.throughputBps != b.throughputBps { return a.throughputBps > b.throughputBps }
            return a.target < b.target
        }
    }

    func buildCommutationPlan(route: String) -> [CommutationPlanStep] {
        let ordered = rankedTargets(route: route)
        let targets = Array(ordered.prefix(max(1, fanoutPerCycle)))
        return targets.compactMap { pane in
            if !isTargetEnabled(pane.target) { return nil }
            let fluency = fluencyForTarget(pane.target, route: route)
            let laneVal = lane(for: pane.target)
            let strategy = chooseStrategy(for: pane.target, route: route)
            let reason = strategy == .autopilot
                ? "lane=\(laneVal.rawValue) fluency=\(fluency)%"
                : "fallback: fluency=\(fluency)% < \(fallbackFluencyThreshold)%"
            return CommutationPlanStep(
                target: pane.target,
                lane: laneVal,
                fluency: fluency,
                throughputBps: pane.throughputBps,
                strategy: strategy,
                reason: reason
            )
        }
    }

    private func maybeRetuneLane(target: String, route: String) {
        guard autoTuneScheduler else { return }
        let stat = statsForTarget(target, route: route)
        guard stat.total >= 3 else { return }
        let fluency = stat.fluency
        let current = lane(for: target)
        if fluency < max(20, minFluencyForPrimary - 35), current != .quarantine {
            setLane(for: target, lane: .quarantine)
            noteScheduler("lane \(target): \(current.rawValue) -> Quarantine (fluency \(fluency)%)")
            return
        }
        if fluency >= minFluencyForPrimary && current != .primary {
            setLane(for: target, lane: .primary)
            noteScheduler("lane \(target): \(current.rawValue) -> Primary (fluency \(fluency)%)")
            return
        }
        if fluency >= 35 && fluency < minFluencyForPrimary && current == .quarantine {
            setLane(for: target, lane: .secondary)
            noteScheduler("lane \(target): Quarantine -> Secondary (fluency \(fluency)%)")
        }
    }

    private func chooseStrategy(for target: String, route: String) -> ExecutionStrategy {
        guard enableFallbackRouting else { return .autopilot }
        let fluency = fluencyForTarget(target, route: route)
        if denyReason(route: route, nodeHint: target) != nil {
            return .paneSmokeFallback
        }
        if fluency > 0 && fluency < fallbackFluencyThreshold {
            return .paneSmokeFallback
        }
        if !capabilities.autopilot || !capabilities.smoke {
            return .paneSmokeFallback
        }
        return .autopilot
    }

    private func denyReason(route: String, nodeHint: String?) -> String? {
        if let nodeHint, !nodeHint.isEmpty {
            let key = "\(nodeHint)|\(route)"
            if let b = nodeRouteBreakers[key], b.isOpen {
                return "Breaker open for \(key): \(b.lastTripReason)"
            }
        }
        if let b = routeBreakers[route], b.isOpen {
            return "Breaker open for \(route): \(b.lastTripReason)"
        }
        return nil
    }

    private func recordBreakerOutcome(route: String, nodeHint: String? = nil, ok: Bool) {
        if let nodeHint, !nodeHint.isEmpty {
            let key = "\(nodeHint)|\(route)"
            var b = nodeRouteBreakers[key] ?? BreakerState()
            appendOutcome(&b, ok: ok)
            maybeTrip(&b, name: key)
            nodeRouteBreakers[key] = b
            return
        }
        var b = routeBreakers[route] ?? BreakerState()
        appendOutcome(&b, ok: ok)
        maybeTrip(&b, name: route)
        routeBreakers[route] = b
    }

    private func appendOutcome(_ breaker: inout BreakerState, ok: Bool) {
        breaker.recent.append(ok)
        if breaker.recent.count > max(2, breakerConfig.sampleWindow) {
            breaker.recent.removeFirst(breaker.recent.count - breakerConfig.sampleWindow)
        }
    }

    private func maybeTrip(_ breaker: inout BreakerState, name: String) {
        let sampleCount = breaker.recent.count
        guard sampleCount >= max(2, breakerConfig.sampleWindow / 2) else { return }
        let failures = breaker.recent.filter { !$0 }.count
        let rate = Double(failures) / Double(sampleCount)
        guard failures >= breakerConfig.minFailures, rate >= breakerConfig.failureRateTrip else { return }
        breaker.openUntil = Date().addingTimeInterval(max(15, breakerConfig.openCooldownSec))
        breaker.lastTripReason = "failures=\(failures)/\(sampleCount) rate=\(String(format: "%.2f", rate))"
        noteScheduler("breaker trip \(name): \(breaker.lastTripReason)")
    }

    private func recomputeDegradedMode() {
        let openRouteCount = routeBreakers.values.filter { $0.isOpen }.count
        let openNodeRouteCount = nodeRouteBreakers.values.filter { $0.isOpen }.count
        let pressure = openRouteCount + Int(Double(openNodeRouteCount) / 2.0)
        cadenceBackoffFactor = min(4.0, max(1.0, 1.0 + Double(pressure) * 0.4))
        cadenceNote = pressure == 0 ? "normal" : "backoff x\(String(format: "%.1f", cadenceBackoffFactor))"
        if openRouteCount >= 2 || openNodeRouteCount >= 5 {
            degradedMode = true
            degradedReason = "breakers route=\(openRouteCount) nodeRoute=\(openNodeRouteCount)"
            return
        }
        if panicMode {
            degradedMode = true
            degradedReason = "panic"
            return
        }
        degradedMode = false
        degradedReason = ""
    }

    private func recordPromptEvent(route: String, target: String?, prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let kind = classifyPromptKind(trimmed)
        let event = PromptEvent(id: UUID(), ts: Date().timeIntervalSince1970, route: route, target: target, prompt: trimmed, kind: kind, summary: nil)
        appendEvent(event)
        cadenceReport = generateCadenceReport()
        queueRecomputeLayerEdges()
        queuePersistence()
    }

    private func recordTimelineEvent(kind: TimelineKind, route: String, target: String?, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ev = PromptEvent(
            id: UUID(),
            ts: Date().timeIntervalSince1970,
            route: route,
            target: target,
            prompt: trimmed,
            kind: kind,
            summary: trimmed
        )
        appendEvent(ev)
        cadenceReport = generateCadenceReport()
        queueRecomputeLayerEdges()
        queuePersistence()
    }

    private func classifyPromptKind(_ prompt: String) -> TimelineKind {
        let p = prompt.lowercased()
        if p.contains("ontology") || p.contains("conceptnode") || p.contains("infer") || p.contains("reflect") || p.contains("ground") || p.contains("attend") {
            return .ontology
        }
        if p.contains("openrouter") || p.contains("free model") || p.contains("duplex") || p.contains("provider") || p.contains("slop") {
            return .duplex
        }
        if p.contains("git commit") || p.contains("commit") || p.contains("branch") || p.contains("rebase") {
            return .git
        }
        if p.contains("file") || p.contains("patch") || p.contains("diff") || p.contains(".swift") || p.contains(".md") || p.contains("write ") {
            return .file
        }
        return .prompt
    }

    private func recordArtifactEvents(from text: String, target: String?) {
        let lower = text.lowercased()
        if lower.contains("commit ") || lower.contains("files changed") || lower.contains("create mode") || lower.contains("delete mode") {
            recordTimelineEvent(kind: .git, route: "artifact/git", target: target, text: summarizeGitArtifact(text))
        }

        let fileHints = detectFilePaths(in: text)
        for path in fileHints.prefix(8) {
            recordTimelineEvent(kind: .file, route: "artifact/file", target: target, text: path)
        }
    }

    private func summarizeGitArtifact(_ text: String) -> String {
        let lines = text.split(separator: "\n").map(String.init)
        if let firstCommit = lines.first(where: { $0.lowercased().contains("commit ") || $0.contains("[") && $0.contains("]") }) {
            return firstCommit
        }
        return "git artifact detected"
    }

    private func detectFilePaths(in text: String) -> [String] {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\"" || $0 == "'" }).map(String.init)
        let exts = [".swift", ".md", ".clj", ".edn", ".json", ".yaml", ".yml", ".toml", ".sh", ".py", ".ts", ".js", ".html", ".css", ".txt"]
        var out: [String] = []
        for tok in tokens {
            if tok.contains("/") || tok.contains("\\") || tok.contains(".") {
                if exts.contains(where: { tok.lowercased().hasSuffix($0) }) {
                    out.append(tok.trimmingCharacters(in: .punctuationCharacters))
                }
            }
        }
        return Array(Set(out)).sorted()
    }

    private func recomputeLayerEdges() {
        layerEdges = TimelineEngine.layerEdges(promptHistory)
        updateEventBudgetSummary()
        performance.recomputePasses += 1
        performance.recomputeQueued = false
    }

    private func appendEvent(_ ev: PromptEvent) {
        promptHistory.append(ev)
        trimEventMemory()
    }

    private func trimEventMemory() {
        if promptHistory.count > maxPromptHistoryEntries {
            promptHistory.removeFirst(promptHistory.count - maxPromptHistoryEntries)
        }
    }

    private func queuePersistence() {
        persistTask?.cancel()
        performance.persistQueued = true
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run {
                self?.persistTelemetryMemory()
            }
        }
    }

    private func queueRecomputeLayerEdges() {
        recomputeTask?.cancel()
        performance.recomputeQueued = true
        recomputeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                self?.recomputeLayerEdges()
            }
        }
    }

    private func updateEventBudgetSummary() {
        eventBudgetSummary = "events \(promptHistory.count)/\(maxPromptHistoryEntries) | logs \(actionLog.count)/\(maxActionLogEntries) | notes \(schedulerNotes.count)/\(maxSchedulerNotesEntries)"
        performance.droppedStateEvents = droppedStateServiceEvents
        let eventBytes = Double(promptHistory.count) * 900.0
        let logBytes = Double(actionLog.count + schedulerNotes.count) * 220.0
        performance.estimatedMemoryMB = (eventBytes + logBytes) / (1024 * 1024)
        recomputeHighPressureMode()
    }

    private func shouldRecordStateServiceEvent() -> Bool {
        guard let last = lastStateServiceEventAt else { return true }
        return Date().timeIntervalSince(last) >= 30
    }

    private func recordRefreshDurationMs(_ ms: Double) {
        performance.lastRefreshMs = ms
        refreshSamplesMs.append(ms)
        if refreshSamplesMs.count > 120 {
            refreshSamplesMs.removeFirst(refreshSamplesMs.count - 120)
        }
        let avg = refreshSamplesMs.reduce(0, +) / Double(max(1, refreshSamplesMs.count))
        performance.avgRefreshMs = avg
        performance.maxRefreshMs = max(performance.maxRefreshMs, ms)
        recomputeHighPressureMode()
    }

    private func recomputeHighPressureMode() {
        var reasons: [String] = []
        if promptHistory.count > Int(Double(maxPromptHistoryEntries) * 0.85) { reasons.append("event-buffer") }
        if performance.avgRefreshMs > 1200 { reasons.append("slow-refresh") }
        if performance.persistQueued && performance.recomputeQueued { reasons.append("queue-pressure") }
        if performance.estimatedMemoryMB > 8.0 { reasons.append("memory-estimate") }

        highPressureMode = !reasons.isEmpty
        highPressureReason = reasons.joined(separator: ",")
        performance.highPressureMode = highPressureMode
        performance.highPressureReason = highPressureReason
    }

    private func currentSessionProfileSnapshot() -> SessionProfileSnapshot {
        let counts = TimelineEngine.layerCounts(promptHistory)
        let cadence = TimelineEngine.cadenceStats(promptHistory)
        let layerCountsString = Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) })
        let openRoutes = routeBreakers.values.filter { $0.isOpen }.count
        let openNodeRoutes = nodeRouteBreakers.values.filter { $0.isOpen }.count
        let top = layerEdges.prefix(12).map {
            "\($0.from.rawValue)->\($0.to.rawValue) n=\($0.count) lat=\(String(format: "%.1f", $0.avgLatencySec)) q=\(String(format: "%.1f", $0.avgQuality))"
        }
        return SessionProfileSnapshot(
            exportedAt: Date().timeIntervalSince1970,
            totalEvents: promptHistory.count,
            layerCounts: layerCountsString,
            cadence: cadence,
            openRouteBreakers: openRoutes,
            openNodeRouteBreakers: openNodeRoutes,
            degradedMode: degradedMode,
            degradedReason: degradedReason,
            interactionHealthScore: interactionHealth.score,
            interactionHealthLabel: interactionHealth.label,
            topEdges: Array(top),
            notes: interactionHealth.notes
        )
    }

    private func renderProfileMarkdown(_ s: SessionProfileSnapshot) -> String {
        let dt = Date(timeIntervalSince1970: s.exportedAt)
        let counts = s.layerCounts.keys.sorted().map { "- \($0): \(s.layerCounts[$0] ?? 0)" }.joined(separator: "\n")
        let edges = s.topEdges.map { "- \($0)" }.joined(separator: "\n")
        let notes = s.notes.map { "- \($0)" }.joined(separator: "\n")
        return """
        # Session Profile Snapshot

        - Exported: \(dt.formatted(date: .abbreviated, time: .standard))
        - Total events: \(s.totalEvents)
        - Interaction health: \(s.interactionHealthLabel) (\(s.interactionHealthScore))
        - Degraded mode: \(s.degradedMode) \(s.degradedReason)
        - Breakers: routes=\(s.openRouteBreakers), node-routes=\(s.openNodeRouteBreakers)

        ## Layer Counts
        \(counts)

        ## Cadence
        - mean: \(String(format: "%.2f", s.cadence.meanSec))s
        - p50: \(String(format: "%.2f", s.cadence.p50Sec))s
        - p90: \(String(format: "%.2f", s.cadence.p90Sec))s
        - burst<60s: \(String(format: "%.2f", s.cadence.burstRatioPct))%
        - longest idle: \(String(format: "%.2f", s.cadence.longestIdleSec))s

        ## Top Edges
        \(edges.isEmpty ? "- none" : edges)

        ## Notes
        \(notes.isEmpty ? "- none" : notes)
        """
    }

    private func generateCadenceReport() -> String {
        let sorted = promptHistory.sorted(by: { $0.ts < $1.ts })
        guard sorted.count >= 2 else {
            return "Prompt cadence report: insufficient data (need >= 2 events)"
        }
        let intervals = zip(sorted.dropFirst(), sorted).map { max(0, $0.ts - $1.ts) }.sorted()
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let p50 = percentile(intervals, q: 0.50)
        let p90 = percentile(intervals, q: 0.90)
        let burst = intervals.filter { $0 < 10 }.count
        let longest = intervals.last ?? 0

        var byRoute: [String: [Double]] = [:]
        for (cur, prev) in zip(sorted.dropFirst(), sorted) {
            byRoute[cur.route, default: []].append(max(0, cur.ts - prev.ts))
        }
        let routeLines = byRoute.keys.sorted().map { route in
            let xs = byRoute[route] ?? []
            let avg = xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
            return "- \(route): n=\(xs.count) avg=\(fmt(avg))s p90=\(fmt(percentile(xs.sorted(), q: 0.90)))s"
        }.joined(separator: "\n")

        return """
        Prompt cadence report
        events=\(sorted.count)
        mean_interval=\(fmt(mean))s
        p50_interval=\(fmt(p50))s
        p90_interval=\(fmt(p90))s
        burst_ratio(<10s)=\(fmt(Double(burst) / Double(intervals.count) * 100))%
        longest_idle=\(fmt(longest))s

        Per-route cadence:
        \(routeLines)
        """
    }

    private func percentile(_ xs: [Double], q: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let clamped = min(1, max(0, q))
        let idx = Int((Double(xs.count - 1) * clamped).rounded())
        return xs[idx]
    }

    private func fmt(_ x: Double) -> String {
        String(format: "%.2f", x)
    }

    private func historyURLs() -> (history: URL, report: URL) {
        let dir = historyDirectoryURL()
        return (dir.appendingPathComponent("prompt-history.ndjson"), dir.appendingPathComponent("prompt-cadence-report.txt"))
    }

    private func profileURLs() -> (json: URL, markdown: URL) {
        let dir = historyDirectoryURL()
        return (dir.appendingPathComponent("session-profile.json"), dir.appendingPathComponent("session-profile.md"))
    }

    private func historyDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ManicAI", isDirectory: true)
    }

    private func ensureHistoryDirectory() throws {
        let dir = historyDirectoryURL()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func laneRank(_ lane: LanePriority) -> Int {
        switch lane {
        case .primary: return 0
        case .secondary: return 1
        case .quarantine: return 2
        }
    }
}
