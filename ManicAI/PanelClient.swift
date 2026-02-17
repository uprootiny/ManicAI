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
    private var lastAutopilotAt: Date?
    private var lastAutopilotAtByTarget: [String: Date] = [:]
    private var refreshQueued: Bool = false
    private var lastCapabilityScanAt: Date?
    private var consecutiveErrors: Int = 0
    private var previousCandidateCount: Int = 0
    private var previousSmokeStatus: String = "unknown"

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let session: URLSession
    private static let logFormatter = ISO8601DateFormatter()
    private static let routeStatsKey = "manicai.telemetry.routeStats.v1"
    private static let nodeStatsKey = "manicai.telemetry.nodeStats.v1"
    private static let actionLogKey = "manicai.telemetry.actionLog.v1"
    private static let schedulerNotesKey = "manicai.telemetry.schedulerNotes.v1"

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
        if let hl = UserDefaults.standard.object(forKey: "manicai.telemetry.halfLifeHours") as? Int {
            telemetryHalfLifeHours = max(1, hl)
        }
        loadTelemetryMemory()
    }

    func refresh() async {
        if isRefreshing {
            refreshQueued = true
            return
        }
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
        }
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
            log("autopilot ok: \(payload.prefix(120))")
            markRoute("autopilot/run", ok: true, nodeHint: nodeHint)
            await refresh()
        } catch {
            consecutiveErrors += 1
            self.error = "Autopilot failed: \(error.localizedDescription)"
            log("autopilot failed: \(error.localizedDescription)")
            markRoute("autopilot/run", ok: false, nodeHint: nodeHint)
        }
    }

    func runCommutedAutopilot(prompt: String, project: String?, autoApprove: Bool) async {
        if panicMode {
            self.error = "Panic mode active. Mutations blocked."
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
            log("smoke ok[\(selectedProject)]: \(text.prefix(120))")
            markRoute("smoke", ok: true)
            await refresh()
            return text
        } catch {
            consecutiveErrors += 1
            self.error = "Smoke failed: \(error.localizedDescription)"
            cycleJournal.insert("smoke-failed[\(selectedProject)]: \(error.localizedDescription)", at: 0)
            log("smoke failed[\(selectedProject)]: \(error.localizedDescription)")
            markRoute("smoke", ok: false)
            return "error"
        }
    }

    func queueAdd(prompt: String, project: String?, sessionID: String?) async -> String {
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
        let payload: [String: Any] = [
            "target": target,
            "text": text,
            "enter": enter
        ]
        return await mutate(path: "api/pane/send", payload: payload, action: "pane/send", nodeHint: target)
    }

    func nudge(sessionID: String, text: String) async -> String {
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
        if actionLog.count > 80 { actionLog = Array(actionLog.prefix(80)) }
        persistTelemetryMemory()
    }

    private func noteScheduler(_ message: String) {
        let ts = Self.logFormatter.string(from: Date())
        schedulerNotes.insert("[\(ts)] \(message)", at: 0)
        if schedulerNotes.count > 80 { schedulerNotes = Array(schedulerNotes.prefix(80)) }
        persistTelemetryMemory()
    }

    private func mutate(path: String, payload: [String: Any], action: String, nodeHint: String? = nil) async -> String {
        if panicMode {
            self.error = "Panic mode active. Mutations blocked."
            return "panic-blocked"
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
            markRoute(action, ok: true, nodeHint: nodeHint)
            await refresh()
            return text
        } catch {
            let msg = "\(action) failed: \(error.localizedDescription)"
            self.error = msg
            log(msg)
            markRoute(action, ok: false, nodeHint: nodeHint)
            return msg
        }
    }

    private func markRoute(_ route: String, ok: Bool, nodeHint: String? = nil) {
        var global = apiStatsByRoute[route] ?? APICallStats()
        if ok { global.success += 1 } else { global.failure += 1 }
        apiStatsByRoute[route] = global

        if let nodeHint, !nodeHint.isEmpty {
            let key = "\(nodeHint)|\(route)"
            var scoped = apiStatsByNodeRoute[key] ?? APICallStats()
            if ok { scoped.success += 1 } else { scoped.failure += 1 }
            apiStatsByNodeRoute[key] = scoped
        }
        persistTelemetryMemory()
    }

    func setTelemetryHalfLifeHours(_ hours: Int) {
        telemetryHalfLifeHours = max(1, hours)
        UserDefaults.standard.set(telemetryHalfLifeHours, forKey: "manicai.telemetry.halfLifeHours")
        loadTelemetryMemory()
    }

    func clearTelemetryMemory() {
        apiStatsByRoute = [:]
        apiStatsByNodeRoute = [:]
        actionLog = []
        schedulerNotes = []
        UserDefaults.standard.removeObject(forKey: Self.routeStatsKey)
        UserDefaults.standard.removeObject(forKey: Self.nodeStatsKey)
        UserDefaults.standard.removeObject(forKey: Self.actionLogKey)
        UserDefaults.standard.removeObject(forKey: Self.schedulerNotesKey)
        telemetryLoadedAt = Date()
        lastAction = "Telemetry memory cleared"
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
            actionLog = Array(decoded.prefix(80))
        }
        if let data = UserDefaults.standard.data(forKey: Self.schedulerNotesKey),
           let decoded = try? decoder.decode([String].self, from: data) {
            schedulerNotes = Array(decoded.prefix(80))
        }
        telemetryLoadedAt = now
        persistTelemetryMemory()
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
        if let data = try? encoder.encode(Array(actionLog.prefix(80))) {
            UserDefaults.standard.set(data, forKey: Self.actionLogKey)
        }
        if let data = try? encoder.encode(Array(schedulerNotes.prefix(80))) {
            UserDefaults.standard.set(data, forKey: Self.schedulerNotesKey)
        }
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
        if fluency > 0 && fluency < fallbackFluencyThreshold {
            return .paneSmokeFallback
        }
        if !capabilities.autopilot || !capabilities.smoke {
            return .paneSmokeFallback
        }
        return .autopilot
    }

    private func laneRank(_ lane: LanePriority) -> Int {
        switch lane {
        case .primary: return 0
        case .secondary: return 1
        case .quarantine: return 2
        }
    }
}
