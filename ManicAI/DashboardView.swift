import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct DashboardView: View {
    enum OpsMode: String, CaseIterable, Identifiable {
        case verify = "Verify"
        case plan = "Plan"
        case act = "Act"
        var id: String { rawValue }
    }

    enum CadenceProfile: String, CaseIterable, Identifiable {
        case stabilize = "Stabilize"
        case throughput = "Throughput"
        case deepwork = "Deep Work"
        var id: String { rawValue }

        var refreshSec: Double {
            switch self {
            case .stabilize: return 8
            case .throughput: return 4
            case .deepwork: return 14
            }
        }
        var cooldownSec: Double {
            switch self {
            case .stabilize: return 14
            case .throughput: return 6
            case .deepwork: return 24
            }
        }
        var actionDelayMs: Double {
            switch self {
            case .stabilize: return 1500
            case .throughput: return 700
            case .deepwork: return 2200
            }
        }
        var fanout: Int {
            switch self {
            case .stabilize: return 1
            case .throughput: return 3
            case .deepwork: return 1
            }
        }
        var script: String {
            switch self {
            case .stabilize:
                return """
                classify blockers only, no writes, suggest minimal next action
                run smoke checks, fix first blocker, rerun smoke, report concise status
                summarize delta and stop unless blocker count decreased
                """
            case .throughput:
                return """
                run smoke checks, fix first blocker, rerun smoke, report concise status
                move to next ready target and repeat guarded cycle
                emit compact status board with done/blocked items
                """
            case .deepwork:
                return """
                isolate one primary session and freeze all noisy loops
                run smoke checks, fix first blocker, rerun smoke, report concise status
                produce one commit-ready patch plan with acceptance criteria
                """
            }
        }
    }

    @StateObject private var client = PanelClient()
    @State private var autopilotPrompt = "run smoke checks, fix first blocker, rerun smoke, report concise status"
    @State private var opsMode: OpsMode = .verify
    @State private var endpointInput = ""
    @State private var selectedPreset = "http://173.212.203.211:8788"
    @State private var selectedProject = ""
    @State private var watchEnabled = true
    @State private var refreshCadenceSec: Double = 7
    @State private var useCommutation = true
    @State private var watchTask: Task<Void, Never>?
    @State private var cadenceProfile: CadenceProfile = .stabilize
    @State private var scriptedNudges = ""
    @State private var scriptPauseSec: Double = 12

    var body: some View {
        VStack(spacing: 12) {
            header
            HStack(alignment: .top, spacing: 12) {
                leftColumn
                centerColumn
                rightColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .background(
            RadialGradient(colors: [Color(red: 0.07, green: 0.14, blue: 0.27), Color(red: 0.02, green: 0.03, blue: 0.06)], center: .topLeading, startRadius: 60, endRadius: 1100)
                .ignoresSafeArea()
        )
        .task {
            endpointInput = client.baseURL.absoluteString
            await client.refresh()
            if selectedProject.isEmpty {
                selectedProject = client.state?.projects.first?.path ?? ""
            }
            scriptedNudges = cadenceProfile.script
            startWatchLoopIfNeeded()
        }
        .onDisappear { watchTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Text("H Y P E R   P R O D U C T I V I T Y   P A N E L")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
            Spacer()
            Text(statusLine)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.gray)
            Button("Refresh") {
                Task { await client.refresh() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 12) {
            GlassCard(title: "Access") {
                HStack {
                    TextField("Endpoint URL", text: $endpointInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Use") {
                        client.setBaseURL(endpointInput)
                        Task { await client.refresh() }
                    }
                    .buttonStyle(.bordered)
                }

                Picker("Preset", selection: $selectedPreset) {
                    ForEach(client.endpointPresets, id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                }
                .onChange(of: selectedPreset) { newValue in
                    endpointInput = newValue
                    client.choosePreset(newValue)
                    Task { await client.refresh() }
                }

                Button("Recon Scan + Auto Select") {
                    Task { await client.probeAndSelectBestEndpoint() }
                }
                .buttonStyle(.borderedProminent)

                Picker("Mode", selection: $opsMode) {
                    ForEach(OpsMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(modeHelp)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                LabeledContent("Panel URL", value: client.baseURL.absoluteString)
                if let s = client.state {
                    LabeledContent("Sessions", value: "\(s.sessions.count)")
                    LabeledContent("Panes", value: "\(s.panes.count)")
                    LabeledContent("Candidates", value: "\(s.takeoverCandidates.count)")
                    LabeledContent("Smoke", value: s.smoke.status)
                    LabeledContent("Queue", value: "\(s.queue.count)")
                }
                if let action = client.lastAction {
                    Text(action).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                if let error = client.error {
                    Text(error).foregroundStyle(.red)
                }
            }

            GlassCard(title: "Autopilot") {
                TextEditor(text: $autopilotPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 88)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                TextField("Project path for autopilot", text: $selectedProject)
                    .textFieldStyle(.roundedBorder)
                Toggle("Use commutation (round-robin + delay)", isOn: $useCommutation)
                Button("Run takeover + smoke") {
                    Task {
                        switch opsMode {
                        case .verify:
                            await client.refresh()
                        case .plan:
                            await client.runAutopilot(
                                prompt: "diagnose blockers only, no writes, suggest minimal next action",
                                maxTargets: 1,
                                autoApprove: false,
                                project: selectedProject.isEmpty ? nil : selectedProject
                            )
                        case .act:
                            if useCommutation {
                                await client.runCommutedAutopilot(
                                    prompt: autopilotPrompt,
                                    project: selectedProject.isEmpty ? nil : selectedProject,
                                    autoApprove: true
                                )
                            } else {
                                await client.runAutopilot(
                                    prompt: autopilotPrompt,
                                    maxTargets: max(1, client.fanoutPerCycle),
                                    autoApprove: true,
                                    project: selectedProject.isEmpty ? nil : selectedProject
                                )
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            GlassCard(title: "Commutation + Throttle") {
                Picker("Cadence", selection: $cadenceProfile) {
                    ForEach(CadenceProfile.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .onChange(of: cadenceProfile) { profile in
                    refreshCadenceSec = profile.refreshSec
                    client.autopilotCooldownSec = profile.cooldownSec
                    client.actionDelayMs = profile.actionDelayMs
                    client.fanoutPerCycle = profile.fanout
                    scriptedNudges = profile.script
                    startWatchLoopIfNeeded()
                }
                Toggle("Background watch refresh", isOn: $watchEnabled)
                    .onChange(of: watchEnabled) { _ in startWatchLoopIfNeeded() }
                HStack {
                    Text("Refresh cadence")
                    Spacer()
                    Text("\(Int(refreshCadenceSec))s")
                }
                Slider(value: $refreshCadenceSec, in: 2...30, step: 1)
                    .onChange(of: refreshCadenceSec) { _ in startWatchLoopIfNeeded() }

                HStack {
                    Text("Autopilot cooldown")
                    Spacer()
                    Text("\(Int(client.autopilotCooldownSec))s")
                }
                Slider(value: $client.autopilotCooldownSec, in: 3...60, step: 1)

                HStack {
                    Text("Inter-action delay")
                    Spacer()
                    Text("\(Int(client.actionDelayMs))ms")
                }
                Slider(value: $client.actionDelayMs, in: 200...5000, step: 100)

                HStack {
                    Text("Fanout per cycle")
                    Spacer()
                    Stepper("\(client.fanoutPerCycle)", value: $client.fanoutPerCycle, in: 1...8)
                        .labelsHidden()
                }

                Text("Scripted nudges (one step per line)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextEditor(text: $scriptedNudges)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 90)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text("Step pause")
                    Spacer()
                    Text("\(Int(scriptPauseSec))s")
                }
                Slider(value: $scriptPauseSec, in: 4...60, step: 1)

                Button("Run scripted nudges") {
                    let sequence = scriptedNudges
                        .split(separator: "\n")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    Task {
                        await client.runScriptedNudges(
                            sequence: sequence,
                            project: selectedProject.isEmpty ? nil : selectedProject,
                            autoApprove: opsMode == .act,
                            pauseSec: scriptPauseSec
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: 360)
    }

    private var centerColumn: some View {
        GlassCard(title: "Takeover Targets") {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(client.state?.takeoverCandidates ?? []) { pane in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pane.target)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                            Text("\(pane.command) | \(pane.liveness) | idle=\(pane.idleSec)s | thr=\(Int(pane.throughputBps)) B/s")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(pane.capture.split(separator: "\n").suffix(4).joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.black.opacity(0.24))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 12) {
            GlassCard(title: "Demo Projects") {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(DemoCatalog.projects) { demo in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(demo.name)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.yellow)
                                Text(demo.summary)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text("mac: \(demo.macSpinup)")
                                    .font(.system(size: 11, design: .monospaced))
                                Text("linux: \(demo.linuxSpinup)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("Use Prompt") {
                                        autopilotPrompt = demo.defaultPrompt
                                    }
                                    .buttonStyle(.bordered)
                                    Button("Copy Linux Runbook") {
                                        copyToClipboard("\(demo.linuxSpinup)\n\(demo.diagnostics)\n\(demo.smoke)")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("OpenRouter free models:")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Text(DemoCatalog.freeModelCatalogHint)
                                .font(.system(size: 11, design: .monospaced))
                            Text("Provider diagnostics:")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Text(DemoCatalog.providerDiagnosticsHint)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            GlassCard(title: "Pane Grid") {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(client.state?.panes ?? []) { pane in
                            HStack {
                                Text(pane.target)
                                    .font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Text(pane.command)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            GlassCard(title: "Surface Recon") {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(client.probes) { probe in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(probe.baseURL.absoluteString)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                Text("state=\(probe.stateReachable ? "ok" : "fail") health=\(probe.healthy ? "ok" : "fail") sessions=\(probe.sessions) candidates=\(probe.candidates) smoke=\(probe.smokeStatus)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if let e = probe.error {
                                    Text(e)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 360)
    }

    private var statusLine: String {
        guard let vibe = client.state?.vibe else { return "pipeline: unknown" }
        return "pipeline: \(vibe.pipelineStatus) | build: \(vibe.buildLatency) | dev: \(vibe.developerState)"
    }

    private var modeHelp: String {
        switch opsMode {
        case .verify:
            return "OnyX-inspired verify pass: inspect only, no interventions."
        case .plan:
            return "Plan pass: classify blockers and suggest safe next move."
        case .act:
            return "Act pass: guarded autopilot + smoke feedback loop."
        }
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
    }

    private func startWatchLoopIfNeeded() {
        watchTask?.cancel()
        guard watchEnabled else { return }
        watchTask = Task {
            while !Task.isCancelled {
                await client.refresh()
                let ns = UInt64(max(2, Int(refreshCadenceSec)) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }
}

private struct GlassCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.mint)
                .textCase(.uppercase)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
