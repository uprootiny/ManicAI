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

    enum SystemProfile: String, CaseIterable, Identifiable {
        case llmDuplex = "LLM Duplex"
        case architected = "Architected"
        case hybrid = "Hybrid"
        var id: String { rawValue }
    }

    enum PatternScale: String, CaseIterable, Identifiable {
        case micro = "Micro"
        case meso = "Meso"
        case macro = "Macro"
        var id: String { rawValue }
    }

    enum AssistantStack: String, CaseIterable, Identifiable {
        case hyle = "Hyle Duplex"
        case coggy = "Coggy Ontology"
        case coupled = "Hyle + Coggy"
        var id: String { rawValue }
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
    @State private var systemProfile: SystemProfile = .hybrid
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
    @State private var timelineTrack = "ALL"
    @State private var timelineCursor = 0
    @State private var rangeStart = 0
    @State private var rangeEnd = 0
    @State private var clipBuffer = ""
    @State private var selectedPatternScale: PatternScale = .micro
    @State private var timelineWindow = 40
    @State private var replaySpeed: Double = 1.0
    @State private var replayTarget = ""
    @State private var replayTask: Task<Void, Never>?
    @State private var timelineKindFilter = "ALL"
    @State private var selectedProfileLayers: Set<String> = ["intent", "cadence", "blockers"]
    @State private var assistantStack: AssistantStack = .coupled

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
                if client.state == nil {
                    await client.probeAndSelectBestEndpoint()
                    endpointInput = client.baseURL.absoluteString
                }
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
                if replayTarget.isEmpty {
                    replayTarget = paneTarget
                }
                scriptedNudges = cadenceProfile.script
                scopeObjective = client.scope.objective
                scopeDone = client.scope.doneCriteria
                scopeIntent = client.scope.intentLatch
                startWatchLoopIfNeeded()
            }
            .onDisappear {
                watchTask?.cancel()
                replayTask?.cancel()
            }
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
            if client.degradedMode {
                Text("DEGRADED")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            if client.highPressureMode {
                Text("PRESSURE")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.yellow)
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
                    Text("\(Int(refreshCadenceSec))s -> \(Int(client.effectiveRefreshCadence(baseSeconds: refreshCadenceSec)))s")
                }
                Slider(value: $refreshCadenceSec, in: 2...30, step: 1)
                    .onChange(of: refreshCadenceSec) { _ in startWatchLoopIfNeeded() }
                Text("cadence mode: \(client.cadenceNote)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

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
                Toggle("Enable fallback routing (pane/send + smoke)", isOn: $client.enableFallbackRouting)
                HStack {
                    Text("Fallback fluency threshold")
                    Spacer()
                    Text("\(client.fallbackFluencyThreshold)%")
                }
                Slider(value: Binding(
                    get: { Double(client.fallbackFluencyThreshold) },
                    set: { client.fallbackFluencyThreshold = Int($0.rounded()) }
                ), in: 10...80, step: 1)

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
                Button("Preview Commutation Plan") {
                    client.commutationPreview = client.buildCommutationPlan(route: "autopilot/run")
                }
                .buttonStyle(.bordered)
            }
            GlassCard(title: "Sampler Palette") {
                Text("Sample promptsets, cadences, and paramsets")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Sample Prompt") { samplePromptFromHistory() }
                        .buttonStyle(.bordered)
                    Button("Sample Cadence") { applyRandomCadencePreset() }
                        .buttonStyle(.bordered)
                    Button("Sample Params") { applyRandomParamset() }
                        .buttonStyle(.borderedProminent)
                }
                Text("applied cadence: refresh=\(Int(refreshCadenceSec))s cooldown=\(Int(client.autopilotCooldownSec))s delay=\(Int(client.actionDelayMs))ms fanout=\(client.fanoutPerCycle)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Divider()
                Text("Pattern Library")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Picker("Scale", selection: $selectedPatternScale) {
                    ForEach(PatternScale.allCases) { scale in
                        Text(scale.rawValue).tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(patternLibrary.filter { $0.scale == selectedPatternScale }) { p in
                            SkeuoPatternTile(
                                title: p.name,
                                subtitle: p.subtitle,
                                accent: p.accent
                            ) {
                                applyPattern(p)
                            }
                            .frame(width: 180)
                        }
                    }
                }
            }
            GlassCard(title: "System Profile") {
                Picker("Profile", selection: $systemProfile) {
                    ForEach(SystemProfile.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                Text(profileGuidance)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Apply Diagnose Profile") {
                        autopilotPrompt = diagnosePromptForProfile(systemProfile)
                        cadenceProfile = systemProfile == .llmDuplex ? .stabilize : .deepwork
                        client.setTelemetryHalfLifeHours(systemProfile == .llmDuplex ? 12 : 36)
                    }
                    .buttonStyle(.bordered)
                    Button("Apply Drive Profile") {
                        autopilotPrompt = drivePromptForProfile(systemProfile)
                        cadenceProfile = systemProfile == .architected ? .throughput : .stabilize
                        client.enableFallbackRouting = systemProfile != .architected
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            GlassCard(title: "Assistant Stack") {
                Picker("Stack", selection: $assistantStack) {
                    ForEach(AssistantStack.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                Text(stackGuidance)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Apply Stack Template") {
                        applyStackTemplate(assistantStack)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Prime Loop Prompt") {
                        autopilotPrompt = stackPrimePrompt(assistantStack)
                    }
                    .buttonStyle(.bordered)
                }
            }
            GlassCard(title: "Telemetry Memory") {
                HStack {
                    Text("Half-life")
                    Spacer()
                    Text("\(client.telemetryHalfLifeHours)h")
                }
                Slider(value: Binding(
                    get: { Double(client.telemetryHalfLifeHours) },
                    set: { client.setTelemetryHalfLifeHours(Int($0.rounded())) }
                ), in: 4...96, step: 1)
                if let ts = client.telemetryLoadedAt {
                    Text("loaded: \(ts.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !client.eventBudgetSummary.isEmpty {
                    Text(client.eventBudgetSummary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button("Clear Telemetry Memory") {
                    client.clearTelemetryMemory()
                }
                .buttonStyle(.bordered)
                Button("Write Prompt History + Cadence Report") {
                    client.exportPromptHistoryAndCadenceReport()
                }
                .buttonStyle(.borderedProminent)
                if !client.promptHistoryPath.isEmpty {
                    Text("history: \(client.promptHistoryPath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !client.cadenceReportPath.isEmpty {
                    Text("report: \(client.cadenceReportPath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            GlassCard(title: "Performance Inspector") {
                let p = client.performance
                Text("refresh ms: last=\(String(format: "%.1f", p.lastRefreshMs)) avg=\(String(format: "%.1f", p.avgRefreshMs)) max=\(String(format: "%.1f", p.maxRefreshMs))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("flushes=\(p.persistFlushes) recomputes=\(p.recomputePasses) dropped_state_events=\(p.droppedStateEvents)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("queues: persist=\(p.persistQueued ? "busy" : "idle") recompute=\(p.recomputeQueued ? "busy" : "idle")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("est memory: \(String(format: "%.2f", p.estimatedMemoryMB)) MB")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                if p.highPressureMode {
                    Text("high-pressure: \(p.highPressureReason)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
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
            GlassCard(title: "Breakers") {
                if client.degradedMode {
                    Text("Degraded mode: \(client.degradedReason)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange)
                } else {
                    Text("No degraded condition active")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.green)
                }
                Text("open routes: \(client.routeBreakers.values.filter { $0.isOpen }.count) | open node-routes: \(client.nodeRouteBreakers.values.filter { $0.isOpen }.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reset Breakers") {
                        client.resetBreakers()
                    }
                    .buttonStyle(.bordered)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(client.routeBreakers.keys.sorted(), id: \.self) { key in
                            if let b = client.routeBreakers[key], b.isOpen {
                                Text("\(key): \(b.lastTripReason)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.yellow)
                            }
                        }
                        ForEach(Array(client.nodeRouteBreakers.keys.sorted().prefix(20)), id: \.self) { key in
                            if let b = client.nodeRouteBreakers[key], b.isOpen {
                                Text("\(key): \(b.lastTripReason)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
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
            GlassCard(title: "Commutation Plan Preview") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(client.commutationPreview) { step in
                            Text("\(step.target) | lane=\(step.lane.rawValue) | strat=\(step.strategy.rawValue) | fluency=\(step.fluency)% | thr=\(Int(step.throughputBps))B/s")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color.black.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(step.reason)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if client.commutationPreview.isEmpty {
                            Text("(no preview yet)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            GlassCard(title: "Session Profile") {
                Text(sessionProfileSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Button("Export Profile Snapshot") {
                        client.exportSessionProfileSnapshot()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Copy Primer") {
                        copyToClipboard(composeLayerPrimer(from: sessionProfileLayers))
                    }
                    .buttonStyle(.bordered)
                }
                if !client.profileSnapshotPath.isEmpty {
                    Text("profile json: \(client.profileSnapshotPath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !client.profileSnapshotMarkdownPath.isEmpty {
                    Text("profile md: \(client.profileSnapshotMarkdownPath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            GlassCard(title: "Materia Flow") {
                let m = materiaMetrics
                Text("prima_materia=\(m.duplexCount) duplex events | vessels=\(m.vesselCount) api interactions | crystals=\(m.crystalCount) git/file artifacts")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    flowBar("Supply", value: m.duplexCount, total: m.total, color: .mint)
                    flowBar("Vessel", value: m.vesselCount, total: m.total, color: .cyan)
                    flowBar("Crystallize", value: m.crystalCount, total: m.total, color: .orange)
                }
                Text("pipeline: filter -> arrange -> weave -> smoke-verify")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GlassCard(title: "Layer Graph") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(client.layerEdges.prefix(24))) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(e.from.rawValue) -> \(e.to.rawValue) | n=\(e.count) | lat=\(String(format: "%.1f", e.avgLatencySec))s | q=\(String(format: "%.1f", e.avgQuality))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.mint)
                                HStack {
                                    flowBar("quality", value: Int(e.avgQuality.rounded()), total: 100, color: .cyan)
                                        .frame(maxWidth: 220)
                                    Spacer()
                                    Button("Replay Edge") {
                                        Task {
                                            actionOutput = await client.replayLayerEdge(e, target: replayTarget.isEmpty ? paneTarget : replayTarget)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if client.layerEdges.isEmpty {
                            Text("(no layer edges yet)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            GlassCard(title: "Profile Layers") {
                let layers = sessionProfileLayers
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(layers, id: \.key) { layer in
                            HStack(alignment: .top, spacing: 6) {
                                Toggle("", isOn: Binding(
                                    get: { selectedProfileLayers.contains(layer.key) },
                                    set: { on in
                                        if on { selectedProfileLayers.insert(layer.key) } else { selectedProfileLayers.remove(layer.key) }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(layer.key)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.mint)
                                    Text(layer.value)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                HStack {
                    Button("Compose Loop Primer") {
                        autopilotPrompt = composeLayerPrimer(from: layers)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Select All") {
                        selectedProfileLayers = Set(layers.map(\.key))
                    }
                    .buttonStyle(.bordered)
                }
            }
            GlassCard(title: "Prompt Timeline") {
                let tracks = timelineTrackKeys
                Picker("Track", selection: $timelineTrack) {
                    ForEach(tracks, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                .pickerStyle(.menu)
                Picker("Kind", selection: $timelineKindFilter) {
                    ForEach(["ALL"] + TimelineKind.allCases.map(\.rawValue), id: \.self) { k in
                        Text(k).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                let events = timelineEventsForSelectedTrack
                if !events.isEmpty {
                    let maxIdx = max(0, events.count - 1)
                    let cursorSliderUpper = max(1, maxIdx)
                    HStack {
                        Button("Prev") { timelineCursor = max(0, timelineCursor - 1) }
                            .buttonStyle(.bordered)
                        Button("Next") { timelineCursor = min(maxIdx, timelineCursor + 1) }
                            .buttonStyle(.bordered)
                        Text("cursor \(timelineCursor + 1)/\(events.count)")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    HStack {
                        Button(replayTask == nil ? "Play" : "Stop") {
                            toggleReplay(events: events)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(client.highPressureMode && replayTask == nil)
                        Button("Step") {
                            replayOneStep(events: events)
                        }
                        .buttonStyle(.bordered)
                        Text("speed x\(String(format: "%.1f", replaySpeed))")
                            .font(.system(size: 10, design: .monospaced))
                        Slider(value: $replaySpeed, in: 0.25...3.0, step: 0.25)
                        TextField("Replay target", text: $replayTarget)
                            .textFieldStyle(.roundedBorder)
                    }
                    Slider(value: Binding(
                        get: { Double(min(timelineCursor, maxIdx)) },
                        set: { timelineCursor = min(maxIdx, Int($0.rounded())) }
                    ), in: 0...Double(cursorSliderUpper), step: 1)
                    HStack {
                        Text("window \(timelineWindow)")
                        Slider(value: Binding(
                            get: { Double(timelineWindow) },
                            set: { timelineWindow = Int($0.rounded()) }
                        ), in: 10...120, step: 1)
                    }
                    HStack {
                        Text("range")
                        Spacer()
                        Stepper("start \(rangeStart + 1)", value: Binding(
                            get: { min(rangeStart, maxIdx) },
                            set: { rangeStart = min(max(0, $0), maxIdx) }
                        ), in: 0...maxIdx)
                        Stepper("end \(rangeEnd + 1)", value: Binding(
                            get: { min(rangeEnd, maxIdx) },
                            set: { rangeEnd = min(max(0, $0), maxIdx) }
                        ), in: 0...maxIdx)
                    }
                    HStack {
                        Button("Copy Range") {
                            let lines = selectedRangeEvents(in: events).map(\.prompt)
                            clipBuffer = lines.joined(separator: "\n")
                            copyToClipboard(clipBuffer)
                        }
                        .buttonStyle(.bordered)
                        Button("Cut Range") {
                            let ids = Set(selectedRangeEvents(in: events).map(\.id))
                            let lines = selectedRangeEvents(in: events).map(\.prompt)
                            clipBuffer = lines.joined(separator: "\n")
                            client.deletePromptEvents(ids: ids)
                            timelineCursor = 0
                        }
                        .buttonStyle(.bordered)
                        Button("Paste Clip To Track") {
                            let target = timelineTrack == "ALL" ? nil : timelineTrack
                            client.pastePromptClip(clipBuffer.split(separator: "\n").map(String.init), target: target)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    TextEditor(text: $clipBuffer)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(height: 56)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Text(client.cadenceReport)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(trackRows, id: \.key) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.key)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.mint)
                                ForEach(row.value.suffix(20)) { ev in
                                    Text("\(timeString(ev.ts)) \(ev.route)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .padding(4)
                                        .background(Color.black.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            .padding(6)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(windowedTimelineEvents(from: events).reversed().enumerated()), id: \.offset) { idx, ev in
                            let prev = priorEvent(forReversedIndex: idx, in: events)
                            let delta = prev == nil ? "-" : "\(Int(max(0, ev.ts - (prev?.ts ?? ev.ts))))s"
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(timeString(ev.ts)) | +\(delta) | \(ev.route) | \(ev.target ?? "-") | \(ev.kind.rawValue)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(kindColor(ev.kind))
                                Text(ev.prompt)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if events.isEmpty {
                            Text("(no prompt events yet)")
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

    private var timelineEventsForSelectedTrack: [PromptEvent] {
        let events = TimelineEngine.events(forTrack: timelineTrack, allEvents: client.promptHistory)
        guard timelineKindFilter != "ALL" else { return events }
        return events.filter { $0.kind.rawValue == timelineKindFilter }
    }

    private var timelineTrackKeys: [String] {
        ["ALL"] + TimelineEngine.tracks(client.promptHistory).map(\.name)
    }

    private var trackRows: [(key: String, value: [PromptEvent])] {
        TimelineEngine.tracks(client.promptHistory).map { ($0.name, $0.events) }
    }

    private var sessionProfileSummary: String {
        let total = client.promptHistory.count
        let cadence = TimelineEngine.cadenceDeltas(client.promptHistory)
        let mean = cadence.isEmpty ? 0 : cadence.reduce(0, +) / Double(cadence.count)
        let promptN = client.promptHistory.filter { $0.kind == .prompt }.count
        let duplexN = client.promptHistory.filter { $0.kind == .duplex }.count
        let ontN = client.promptHistory.filter { $0.kind == .ontology }.count
        let gitN = client.promptHistory.filter { $0.kind == .git }.count
        let fileN = client.promptHistory.filter { $0.kind == .file }.count
        let serviceN = client.promptHistory.filter { $0.kind == .service }.count
        let openBreakers = client.routeBreakers.values.filter { $0.isOpen }.count + client.nodeRouteBreakers.values.filter { $0.isOpen }.count
        return """
        total_events=\(total)
        mean_cadence=\(String(format: "%.1f", mean))s
        layers: prompt=\(promptN) duplex=\(duplexN) ontology=\(ontN) git=\(gitN) file=\(fileN) service=\(serviceN)
        health=\(client.interactionHealth.label) score=\(client.interactionHealth.score)
        breakers_open=\(openBreakers) degraded=\(client.degradedMode)
        cadence_mode=\(client.cadenceNote)
        """
    }

    private var sessionProfileLayers: [(key: String, value: String)] {
        let cadence = TimelineEngine.cadenceDeltas(client.promptHistory)
        let mean = cadence.isEmpty ? 0 : cadence.reduce(0, +) / Double(cadence.count)
        let burst = cadence.isEmpty ? 0 : (Double(cadence.filter { $0 < 60 }.count) / Double(cadence.count)) * 100
        let blockers = client.interactionHealth.notes.joined(separator: " ")
        return [
            ("intent", "latched=\(client.intentLatched) checksum=\(client.latchedIntentChecksum.isEmpty ? "-" : client.latchedIntentChecksum)"),
            ("cadence", "mean=\(String(format: "%.1f", mean))s burst<60s=\(String(format: "%.1f", burst))% mode=\(client.cadenceNote)"),
            ("blockers", blockers.isEmpty ? "none" : blockers),
            ("automation", "fanout=\(client.fanoutPerCycle) fallback=\(client.enableFallbackRouting) autotune=\(client.autoTuneScheduler)"),
            ("trace", "events=\(client.promptHistory.count) queue=\(client.state?.queue.count ?? 0) smoke=\(client.state?.smoke.status ?? "unknown")")
        ]
    }

    private var materiaMetrics: (duplexCount: Int, vesselCount: Int, crystalCount: Int, total: Int) {
        let total = max(1, client.promptHistory.count)
        let duplex = client.promptHistory.filter { $0.kind == .prompt || $0.kind == .duplex }.count
        let vessel = client.promptHistory.filter { $0.kind == .service }.count
        let crystal = client.promptHistory.filter { $0.kind == .git || $0.kind == .file || $0.kind == .ontology }.count
        return (duplex, vessel, crystal, total)
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

    private var profileGuidance: String {
        switch systemProfile {
        case .llmDuplex:
            return "Prioritize drift detection, repetition collapse, and short feedback loops."
        case .architected:
            return "Prioritize API contract health, stage isolation, and deterministic smoke gates."
        case .hybrid:
            return "Balance conversation drift controls with strict runbook/smoke execution."
        }
    }

    private func diagnosePromptForProfile(_ p: SystemProfile) -> String {
        switch p {
        case .llmDuplex:
            return "classify drift loops, repeated intents, and approval stalls; propose one bounded correction"
        case .architected:
            return "validate contracts and failing stages only; identify first deterministic blocker"
        case .hybrid:
            return "diagnose both drift and failing smoke gates; rank by user attention cost"
        }
    }

    private func drivePromptForProfile(_ p: SystemProfile) -> String {
        switch p {
        case .llmDuplex:
            return "inject concise corrective prompt, run smoke checks, report delta and halt"
        case .architected:
            return "fix first failing smoke step, rerun smoke, emit patch-ready summary"
        case .hybrid:
            return "run smoke checks, fix first blocker, rerun smoke, summarize blocker delta"
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
                let eff = client.effectiveRefreshCadence(baseSeconds: refreshCadenceSec)
                let ns = UInt64(max(2, Int(eff.rounded())) * 1_000_000_000)
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

    private func priorEvent(forReversedIndex idx: Int, in events: [PromptEvent]) -> PromptEvent? {
        let arr = Array(events.suffix(60).reversed())
        guard idx + 1 < arr.count else { return nil }
        return arr[idx + 1]
    }

    private func windowedTimelineEvents(from events: [PromptEvent]) -> [PromptEvent] {
        guard !events.isEmpty else { return [] }
        let c = min(max(0, timelineCursor), events.count - 1)
        let half = max(1, timelineWindow / 2)
        let lo = max(0, c - half)
        let hi = min(events.count - 1, c + half)
        return Array(events[lo...hi])
    }

    private func selectedRangeEvents(in events: [PromptEvent]) -> [PromptEvent] {
        TimelineEngine.rangeEvents(events, start: rangeStart, end: rangeEnd)
    }

    private func timeString(_ ts: TimeInterval) -> String {
        let d = Date(timeIntervalSince1970: ts)
        return d.formatted(date: .omitted, time: .standard)
    }

    private func replayOneStep(events: [PromptEvent]) {
        guard !events.isEmpty else { return }
        let idx = min(max(0, timelineCursor), events.count - 1)
        let ev = events[idx]
        let target = replayTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (ev.target ?? paneTarget) : replayTarget
        Task {
            actionOutput = await client.paneSend(target: target, text: ev.prompt, enter: true)
        }
        if idx < events.count - 1 {
            timelineCursor = idx + 1
        }
    }

    private func toggleReplay(events: [PromptEvent]) {
        if let task = replayTask {
            task.cancel()
            replayTask = nil
            return
        }
        replayTask = Task {
            while !Task.isCancelled {
                if events.isEmpty { break }
                let idx = min(max(0, timelineCursor), events.count - 1)
                let ev = events[idx]
                let target = replayTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (ev.target ?? paneTarget) : replayTarget
                actionOutput = await client.paneSend(target: target, text: ev.prompt, enter: true)
                if idx >= events.count - 1 { break }
                timelineCursor = idx + 1
                let base = idx + 1 < events.count ? max(0.2, events[idx + 1].ts - ev.ts) : 1.0
                let wait = max(0.15, base / max(0.25, replaySpeed))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            replayTask = nil
        }
    }

    private func samplePromptFromHistory() {
        let candidates = client.promptHistory.suffix(80).map(\.prompt).filter { !$0.isEmpty }
        if let pick = candidates.randomElement() {
            autopilotPrompt = pick
        }
    }

    private func applyRandomCadencePreset() {
        let presets: [(Double, Double, Double, Int)] = [
            (4, 6, 700, 3),
            (8, 14, 1500, 1),
            (12, 20, 2200, 1),
            (6, 10, 1100, 2)
        ]
        guard let p = presets.randomElement() else { return }
        refreshCadenceSec = p.0
        client.autopilotCooldownSec = p.1
        client.actionDelayMs = p.2
        client.fanoutPerCycle = p.3
        startWatchLoopIfNeeded()
    }

    private func applyRandomParamset() {
        let fallbacks = [30, 40, 50, 60]
        let primaries = [55, 65, 75, 85]
        if let f = fallbacks.randomElement() {
            client.fallbackFluencyThreshold = f
        }
        if let p = primaries.randomElement() {
            client.minFluencyForPrimary = p
        }
        client.enableFallbackRouting = Bool.random()
        client.autoTuneScheduler = Bool.random()
    }

    private var patternLibrary: [PatternPreset] {
        [
            PatternPreset(name: "Pulse Clamp", subtitle: "fast verify bursts", scale: .micro, accent: .mint, prompt: "classify blockers only, no writes", refresh: 4, cooldown: 6, delay: 700, fanout: 2, fallback: 35, primary: 70),
            PatternPreset(name: "Nudge Probe", subtitle: "single-lane probe", scale: .micro, accent: .cyan, prompt: "inject concise corrective nudge and report delta", refresh: 6, cooldown: 8, delay: 900, fanout: 1, fallback: 40, primary: 65),
            PatternPreset(name: "Stability Sweep", subtitle: "repair first blocker", scale: .meso, accent: .yellow, prompt: "run smoke checks, fix first blocker, rerun smoke, report concise status", refresh: 8, cooldown: 14, delay: 1500, fanout: 2, fallback: 45, primary: 65),
            PatternPreset(name: "Route Hardening", subtitle: "contract-first pass", scale: .meso, accent: .orange, prompt: "validate contracts and failing stages only; identify first deterministic blocker", refresh: 10, cooldown: 16, delay: 1700, fanout: 1, fallback: 30, primary: 75),
            PatternPreset(name: "Deep Salvage", subtitle: "long-form containment", scale: .macro, accent: .red, prompt: "stabilize noisy loops, run one bounded smoke-guided repair cycle", refresh: 14, cooldown: 22, delay: 2300, fanout: 1, fallback: 50, primary: 60),
            PatternPreset(name: "Throughput Grid", subtitle: "high-yield shipping", scale: .macro, accent: .purple, prompt: "fix first failing smoke step, rerun smoke, emit patch-ready summary", refresh: 5, cooldown: 7, delay: 800, fanout: 3, fallback: 35, primary: 80)
        ]
    }

    private func applyPattern(_ p: PatternPreset) {
        autopilotPrompt = p.prompt
        refreshCadenceSec = p.refresh
        client.autopilotCooldownSec = p.cooldown
        client.actionDelayMs = p.delay
        client.fanoutPerCycle = p.fanout
        client.fallbackFluencyThreshold = p.fallback
        client.minFluencyForPrimary = p.primary
        startWatchLoopIfNeeded()
    }

    private func composeLayerPrimer(from layers: [(key: String, value: String)]) -> String {
        let selected = layers.filter { selectedProfileLayers.contains($0.key) }
        let body = selected.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return """
        Reapply profile layers to current inference loop:
        \(body)
        Execute one bounded cycle: diagnose -> one action -> smoke -> concise delta.
        """
    }

    private var stackGuidance: String {
        switch assistantStack {
        case .hyle:
            return "Shape duplex stream into concise API-ready actions; optimize cadence and guardrails."
        case .coggy:
            return "Route prompts through ontology grounding (attend/infer/reflect) before execution."
        case .coupled:
            return "Use Hyle as vessel and Coggy as crystallizer: shape -> ground -> smoke -> delta."
        }
    }

    private func stackPrimePrompt(_ s: AssistantStack) -> String {
        switch s {
        case .hyle:
            return "hyle mode: compress duplex slop into bounded actions, run smoke, report concise deltas"
        case .coggy:
            return "coggy mode: parse concepts, ground ontology links, infer blocker, propose one deterministic fix"
        case .coupled:
            return "coupled mode: shape duplex feed (hyle), ground through ontology (coggy), execute one smoke-verified repair cycle"
        }
    }

    private func applyStackTemplate(_ s: AssistantStack) {
        autopilotPrompt = stackPrimePrompt(s)
        switch s {
        case .hyle:
            refreshCadenceSec = 5
            client.autopilotCooldownSec = 7
            client.actionDelayMs = 900
            client.fanoutPerCycle = 3
            client.enableFallbackRouting = true
            client.fallbackFluencyThreshold = 40
        case .coggy:
            refreshCadenceSec = 10
            client.autopilotCooldownSec = 16
            client.actionDelayMs = 1800
            client.fanoutPerCycle = 1
            client.enableFallbackRouting = false
            client.fallbackFluencyThreshold = 30
        case .coupled:
            refreshCadenceSec = 7
            client.autopilotCooldownSec = 11
            client.actionDelayMs = 1300
            client.fanoutPerCycle = 2
            client.enableFallbackRouting = true
            client.fallbackFluencyThreshold = 45
        }
        startWatchLoopIfNeeded()
    }

    private func kindColor(_ kind: TimelineKind) -> Color {
        switch kind {
        case .prompt: return .mint
        case .duplex: return .blue
        case .ontology: return .purple
        case .git: return .orange
        case .file: return .yellow
        case .service: return .cyan
        }
    }

    private func flowBar(_ label: String, value: Int, total: Int, color: Color) -> some View {
        let frac = max(0.0, min(1.0, Double(value) / Double(max(1, total))))
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 10, design: .monospaced))
                Spacer()
                Text("\(value)").font(.system(size: 10, design: .monospaced))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [color.opacity(0.8), color.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct PatternPreset: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let scale: DashboardView.PatternScale
    let accent: Color
    let prompt: String
    let refresh: Double
    let cooldown: Double
    let delay: Double
    let fanout: Int
    let fallback: Int
    let primary: Int
}

private struct SkeuoPatternTile: View {
    let title: String
    let subtitle: String
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [accent.opacity(0.7), accent.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
        }
        .buttonStyle(.plain)
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
