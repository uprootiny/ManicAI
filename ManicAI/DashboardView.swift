import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct DashboardView: View {
    @Environment(\.openURL) private var openURL
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
    @State private var scopeObjective = ""
    @State private var scopeDone = ""
    @State private var scopeIntent = ""
    @State private var targetFilter = ""
    @State private var queuePrompt = ""
    @State private var queueSessionID = ""
    @State private var nudgeSessionID = ""
    @State private var nudgeText = ""
    @State private var paneTarget = ""
    @State private var paneText = ""
    @State private var spawnName = ""
    @State private var spawnCommand = "hyle --free"
    @State private var snapshotName = "remote-tmux"
    @State private var snapshotText = ""
    @State private var actionOutput = ""

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 1320
            VStack(spacing: 12) {
                header
                if compact {
                    ScrollView {
                        VStack(spacing: 12) {
                            leftColumn(compact: true)
                            centerColumn
                            rightColumn(compact: true)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        leftColumn(compact: false)
                        centerColumn
                        rightColumn(compact: false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
                if queueSessionID.isEmpty {
                    queueSessionID = client.state?.sessions.first?.id ?? ""
                }
                if nudgeSessionID.isEmpty {
                    nudgeSessionID = queueSessionID
                }
                if paneTarget.isEmpty {
                    paneTarget = client.state?.takeoverCandidates.first?.target ?? ""
                }
                scriptedNudges = cadenceProfile.script
                scopeObjective = client.scope.objective
                scopeDone = client.scope.doneCriteria
                scopeIntent = client.scope.intentLatch
                startWatchLoopIfNeeded()
            }
            .onDisappear { watchTask?.cancel() }
        }
    }

    private var header: some View {
        HStack {
            Text("H Y P E R   P R O D U C T I V I T Y   P A N E L")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
            Spacer()
            if client.isRefreshing {
                Text("syncing")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.mint)
            }
            Text(statusLine)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.gray)
            Text("health \(client.interactionHealth.score) \(client.interactionHealth.label)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(client.interactionHealth.score >= 80 ? .green : (client.interactionHealth.score >= 60 ? .yellow : .red))
            Text("agitation \(client.agitationScore)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(client.agitationScore < 35 ? .green : (client.agitationScore < 65 ? .yellow : .red))
            if client.panicMode {
                Text("PANIC")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red)
            }
            Button("Refresh") {
                Task { await client.refresh() }
            }
            .buttonStyle(.bordered)
            .disabled(client.isRefreshing)
        }
    }

    private func leftColumn(compact: Bool) -> some View {
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
                .disabled(client.isRefreshing)

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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        quickPromptButton("smoke+fix", "run smoke checks, fix first blocker, rerun smoke, report concise status")
                        quickPromptButton("classify blockers", "classify blockers only, no writes, suggest minimal next action")
                        quickPromptButton("stabilize", "stabilize noisy loops, run one bounded smoke-guided repair cycle")
                    }
                    .padding(.vertical, 2)
                }
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
                .disabled(client.panicMode)
                .disabled(!(client.capabilities.autopilot && client.capabilities.smoke))
                if !autopilotReady {
                    Text(autopilotDisabledReason)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
            }
            GlassCard(title: "Scope Contract") {
                TextField("Objective", text: $scopeObjective)
                    .textFieldStyle(.roundedBorder)
                TextField("Done criteria", text: $scopeDone)
                    .textFieldStyle(.roundedBorder)
                TextField("Intent latch (single interaction intent)", text: $scopeIntent)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Max cycles")
                    Spacer()
                    Stepper("\(client.scope.maxCycles)", value: $client.scope.maxCycles, in: 1...12)
                        .labelsHidden()
                }
                HStack {
                    Text("Attention budget")
                    Spacer()
                    Stepper("\(client.scope.attentionBudgetActions)", value: $client.scope.attentionBudgetActions, in: 1...20)
                        .labelsHidden()
                }
                Toggle("Require intent latch", isOn: $client.scope.requireIntentLatch)
                Toggle("Require smoke pass to stop", isOn: $client.scope.requireSmokePassToStop)
                Toggle("Freeze on drift", isOn: $client.scope.freezeOnDrift)

                HStack {
                    Button("Apply Contract") {
                        client.scope.objective = scopeObjective
                        client.scope.doneCriteria = scopeDone
                        client.scope.intentLatch = scopeIntent
                        client.lastAction = "Scope contract updated"
                    }
                    .buttonStyle(.bordered)
                    Button(client.intentLatched ? "Relatch Intent" : "Latch Intent") {
                        client.latchIntent(scopeIntent)
                    }
                    .buttonStyle(.bordered)
                    Button("Clear Latch") {
                        client.clearIntentLatch()
                    }
                    .buttonStyle(.bordered)
                    Button("Healthy Cycle") {
                        Task {
                            await client.runHealthyCycle(
                                prompt: autopilotPrompt,
                                project: selectedProject.isEmpty ? nil : selectedProject,
                                autoApprove: opsMode == .act
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack {
                    Text("Cycles used: \(client.completedCycles)/\(client.scope.maxCycles)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("actions \(client.actionsInCurrentScope)/\(client.scope.attentionBudgetActions)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Ledger") {
                        client.resetCycleLedger()
                    }
                    .buttonStyle(.bordered)
                }

                Text("intent checksum: \(client.latchedIntentChecksum.isEmpty ? "-" : client.latchedIntentChecksum) | latched: \(client.intentLatched ? "yes" : "no")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(client.intentLatched ? .green : .yellow)

                if !client.interactionHealth.notes.isEmpty {
                    Text(client.interactionHealth.notes.joined(separator: " "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
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
                Toggle("Auto-tune lanes by node fluency", isOn: $client.autoTuneScheduler)
                HStack {
                    Text("Primary lane fluency threshold")
                    Spacer()
                    Text("\(client.minFluencyForPrimary)%")
                }
                Slider(value: Binding(
                    get: { Double(client.minFluencyForPrimary) },
                    set: { client.minFluencyForPrimary = Int($0.rounded()) }
                ), in: 40...95, step: 1)

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
                .disabled(client.panicMode)
            }
            GlassCard(title: "Panic + Lanes") {
                if client.panicMode {
                    Text("Read-only containment active: \(client.panicReason)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                } else {
                    Text("Mutations enabled")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.green)
                }
                HStack {
                    Button("Freeze All (Panic)") {
                        client.engagePanic(reason: "manual panic button")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    Button("Resume") {
                        client.clearPanic()
                    }
                    .buttonStyle(.bordered)
                }
            }
            GlassCard(title: "API Capabilities") {
                VStack(alignment: .leading, spacing: 4) {
                    capabilityLine("state", client.capabilities.state)
                    capabilityLine("autopilot", client.capabilities.autopilot)
                    capabilityLine("smoke", client.capabilities.smoke)
                    capabilityLine("pane/send", client.capabilities.paneSend)
                    capabilityLine("queue/add", client.capabilities.queue)
                    capabilityLine("queue/run", client.capabilities.queueRun)
                    capabilityLine("spawn", client.capabilities.spawn)
                    capabilityLine("nudge", client.capabilities.nudge)
                    capabilityLine("snapshot/ingest", client.capabilities.snapshotIngest)
                }
            }
            GlassCard(title: "API Validation") {
                let missing = ControlSpecs.missingCriticalRoutes(capabilities: client.capabilities)
                Text(missing.isEmpty ? "Critical routes ready" : "Missing critical: \(missing.joined(separator: ", "))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(missing.isEmpty ? .green : .yellow)
                ForEach(ControlSpecs.routes) { route in
                    Text("\(route.method) \(route.path)\(route.critical ? " *" : "")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: compact ? .infinity : 360)
    }

    private var centerColumn: some View {
        VStack(spacing: 12) {
            GlassCard(title: "Takeover Targets") {
                TextField("Filter by target/command/auth", text: $targetFilter)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredCandidates) { pane in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(pane.target)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.green)
                                Text("\(pane.command) | \(pane.liveness) | idle=\(pane.idleSec)s | thr=\(Int(pane.throughputBps)) B/s | fluency=\(client.fluencyForTarget(pane.target, route: "autopilot/run"))%")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(pane.capture.split(separator: "\n").suffix(4).joined(separator: "\n"))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.black.opacity(0.24))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                HStack {
                                    Picker("Lane", selection: Binding(
                                        get: { client.lane(for: pane.target) },
                                        set: { client.setLane(for: pane.target, lane: $0) }
                                    )) {
                                        ForEach(LanePriority.allCases) { lane in
                                            Text(lane.rawValue).tag(lane)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                HStack {
                                    let throttle = client.throttleForTarget(pane.target)
                                    Stepper("cooldown \(Int(throttle.cooldownSec ?? client.autopilotCooldownSec))s", onIncrement: {
                                        let current = throttle.cooldownSec ?? client.autopilotCooldownSec
                                        client.setThrottle(for: pane.target, cooldownSec: min(120, current + 1), delayMs: throttle.delayMs)
                                    }, onDecrement: {
                                        let current = throttle.cooldownSec ?? client.autopilotCooldownSec
                                        client.setThrottle(for: pane.target, cooldownSec: max(1, current - 1), delayMs: throttle.delayMs)
                                    })
                                    .font(.system(size: 10, design: .monospaced))
                                }
                                HStack {
                                    let throttle = client.throttleForTarget(pane.target)
                                    Stepper("delay \(Int(throttle.delayMs ?? client.actionDelayMs))ms", onIncrement: {
                                        let current = throttle.delayMs ?? client.actionDelayMs
                                        client.setThrottle(for: pane.target, cooldownSec: throttle.cooldownSec, delayMs: min(10000, current + 100))
                                    }, onDecrement: {
                                        let current = throttle.delayMs ?? client.actionDelayMs
                                        client.setThrottle(for: pane.target, cooldownSec: throttle.cooldownSec, delayMs: max(100, current - 100))
                                    })
                                    .font(.system(size: 10, design: .monospaced))
                                }
                                Toggle("Enabled", isOn: Binding(
                                    get: { client.isTargetEnabled(pane.target) },
                                    set: { client.setTargetEnabled(pane.target, enabled: $0) }
                                ))
                                .font(.system(size: 10, design: .monospaced))
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        if filteredCandidates.isEmpty {
                            Text("No targets match current filter.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            GlassCard(title: "Cycle Journal") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        Text("delta: \(client.lastDelta)")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        ForEach(Array(client.cycleJournal.prefix(20).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color.black.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if client.cycleJournal.isEmpty {
                            Text("(no cycle events)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func rightColumn(compact: Bool) -> some View {
        VStack(spacing: 12) {
            GlassCard(title: "Direct Controls") {
                TextField("Queue prompt", text: $queuePrompt)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Project path", text: $selectedProject)
                        .textFieldStyle(.roundedBorder)
                    TextField("Session id", text: $queueSessionID)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button("Queue Add") {
                        Task {
                            actionOutput = await client.queueAdd(
                                prompt: queuePrompt,
                                project: selectedProject.isEmpty ? nil : selectedProject,
                                sessionID: queueSessionID.isEmpty ? nil : queueSessionID
                            )
                            queuePrompt = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!client.capabilities.queue || queuePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.panicMode)

                    Button("Queue Run") {
                        Task {
                            actionOutput = await client.queueRun(
                                project: selectedProject.isEmpty ? nil : selectedProject,
                                sessionID: queueSessionID.isEmpty ? nil : queueSessionID
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!client.capabilities.queueRun || client.panicMode)
                }

                Divider()
                HStack {
                    TextField("Nudge session id", text: $nudgeSessionID)
                        .textFieldStyle(.roundedBorder)
                    TextField("Nudge text", text: $nudgeText)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Send Nudge") {
                    Task {
                        actionOutput = await client.nudge(sessionID: nudgeSessionID, text: nudgeText)
                        nudgeText = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!client.capabilities.nudge || nudgeSessionID.isEmpty || nudgeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.panicMode)

                Divider()
                HStack {
                    TextField("Pane target", text: $paneTarget)
                        .textFieldStyle(.roundedBorder)
                    TextField("Pane text", text: $paneText)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Send Pane") {
                    Task {
                        actionOutput = await client.paneSend(target: paneTarget, text: paneText, enter: true)
                        paneText = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!client.capabilities.paneSend || paneTarget.isEmpty || paneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.panicMode)

                Divider()
                HStack {
                    TextField("Spawn session name", text: $spawnName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Command", text: $spawnCommand)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Spawn Session") {
                    Task {
                        let generated = spawnName.isEmpty ? "agent-\(Int(Date().timeIntervalSince1970))" : spawnName
                        actionOutput = await client.spawn(
                            sessionName: generated,
                            project: selectedProject.isEmpty ? nil : selectedProject,
                            command: spawnCommand
                        )
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!client.capabilities.spawn || spawnCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.panicMode)

                Divider()
                TextField("Snapshot name", text: $snapshotName)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $snapshotText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 68)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("Ingest Snapshot") {
                    Task {
                        actionOutput = await client.snapshotIngest(name: snapshotName, text: snapshotText)
                        snapshotText = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!client.capabilities.snapshotIngest || snapshotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || snapshotText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.panicMode)

                if !actionOutput.isEmpty {
                    Text(actionOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

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
            GlassCard(title: "GitHub Project Links") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(client.state?.projects ?? []) { project in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.path)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                if let url = ProjectRegistry.githubURL(for: project.path) {
                                    Text(url.absoluteString)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Button("Open Repo") { openURL(url) }
                                            .buttonStyle(.bordered)
                                        Button("Copy URL") { copyToClipboard(url.absoluteString) }
                                            .buttonStyle(.bordered)
                                    }
                                } else {
                                    Text("No repo mapping")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
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
            GlassCard(title: "Node API Fluency") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(topNodeFluencyKeys, id: \.self) { key in
                            if let stat = client.apiStatsByNodeRoute[key] {
                                Text("\(key) -> \(stat.fluency)% (\(stat.success)/\(stat.total))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .background(Color.black.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        if topNodeFluencyKeys.isEmpty {
                            Text("(no node-level API stats yet)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            GlassCard(title: "Scheduler Notes") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(client.schedulerNotes.prefix(24).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color.black.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if client.schedulerNotes.isEmpty {
                            Text("(no scheduler decisions yet)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
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
            GlassCard(title: "Action Log") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(client.actionLog.prefix(30).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color.black.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if client.actionLog.isEmpty {
                            Text("(no actions logged yet)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: compact ? .infinity : 360)
    }

    private var statusLine: String {
        guard let vibe = client.state?.vibe else { return "pipeline: unknown" }
        return "pipeline: \(vibe.pipelineStatus) | build: \(vibe.buildLatency) | dev: \(vibe.developerState)"
    }

    private var filteredCandidates: [PaneInfo] {
        let all = client.state?.takeoverCandidates ?? []
        let q = targetFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { pane in
            pane.target.lowercased().contains(q) ||
            pane.command.lowercased().contains(q) ||
            pane.authRituals.joined(separator: ",").lowercased().contains(q)
        }
    }

    private var autopilotReady: Bool {
        !client.panicMode && client.capabilities.autopilot && client.capabilities.smoke
    }

    private var topNodeFluencyKeys: [String] {
        client.apiStatsByNodeRoute
            .sorted { lhs, rhs in
                if lhs.value.fluency != rhs.value.fluency { return lhs.value.fluency > rhs.value.fluency }
                return lhs.key < rhs.key
            }
            .map(\.key)
            .prefix(24)
            .map { $0 }
    }

    private var autopilotDisabledReason: String {
        if client.panicMode {
            return "Panic freeze is active. Resume to allow actions."
        }
        if !client.capabilities.autopilot || !client.capabilities.smoke {
            return "Remote API is missing required endpoints (/api/autopilot/run and /api/smoke)."
        }
        return ""
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

    private func capabilityLine(_ name: String, _ ok: Bool) -> some View {
        HStack {
            Text(name).font(.system(size: 10, design: .monospaced))
            Spacer()
            Text(ok ? "ok" : "missing")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ok ? .green : .yellow)
        }
    }

    private func quickPromptButton(_ label: String, _ prompt: String) -> some View {
        Button(label) {
            autopilotPrompt = prompt
        }
        .buttonStyle(.bordered)
        .font(.system(size: 10, design: .monospaced))
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
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    }
}
