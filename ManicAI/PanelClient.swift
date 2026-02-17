import Foundation

@MainActor
final class PanelClient: ObservableObject {
    @Published var state: PanelState?
    @Published var error: String?

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    var baseURL: URL {
        didSet { UserDefaults.standard.set(baseURL.absoluteString, forKey: "manicai.baseURL") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "manicai.baseURL")
        self.baseURL = URL(string: saved ?? "http://127.0.0.1:8788")!
    }

    func refresh() async {
        do {
            let url = baseURL.appending(path: "api/state")
            let (data, _) = try await URLSession.shared.data(from: url)
            state = try decoder.decode(PanelState.self, from: data)
            error = nil
        } catch {
            self.error = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func runAutopilot(prompt: String, maxTargets: Int = 2, autoApprove: Bool = true) async {
        do {
            let url = baseURL.appending(path: "api/autopilot/run")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AutopilotRequest(prompt: prompt, maxTargets: maxTargets, autoApprove: autoApprove))
            _ = try await URLSession.shared.data(for: req)
            await refresh()
        } catch {
            self.error = "Autopilot failed: \(error.localizedDescription)"
        }
    }
}
