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
    private var lastAutopilotAt: Date?

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
            lastAction = "Refreshed \(baseURL.host ?? "unknown")"
        } catch {
            self.error = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func runAutopilot(prompt: String, maxTargets: Int = 2, autoApprove: Bool = true, project: String? = nil) async {
        UserDefaults.standard.set(autopilotCooldownSec, forKey: "manicai.autopilotCooldownSec")
        UserDefaults.standard.set(actionDelayMs, forKey: "manicai.actionDelayMs")
        UserDefaults.standard.set(fanoutPerCycle, forKey: "manicai.fanoutPerCycle")
        if let last = lastAutopilotAt {
            let gap = Date().timeIntervalSince(last)
            if gap < autopilotCooldownSec {
                let remain = Int((autopilotCooldownSec - gap).rounded(.up))
                self.error = "Autopilot throttled: wait \(remain)s"
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
            lastAction = "Autopilot OK (\(selectedProject ?? "no-project")) \(payload.prefix(180))"
            await refresh()
        } catch {
            self.error = "Autopilot failed: \(error.localizedDescription)"
        }
    }

    func runCommutedAutopilot(prompt: String, project: String?, autoApprove: Bool) async {
        let targets = Array((state?.takeoverCandidates ?? []).prefix(max(1, fanoutPerCycle)))
        if targets.isEmpty {
            await runAutopilot(prompt: prompt, maxTargets: 1, autoApprove: autoApprove, project: project)
            return
        }

        var cycleResults: [String] = []
        for pane in targets {
            await runAutopilot(prompt: prompt, maxTargets: 1, autoApprove: autoApprove, project: project)
            cycleResults.append(pane.target)
            let ns = UInt64(max(0, actionDelayMs) * 1_000_000)
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
}
