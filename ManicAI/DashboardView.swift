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

    @StateObject private var client = PanelClient()
    @State private var autopilotPrompt = "run smoke checks, fix first blocker, rerun smoke, report concise status"
    @State private var opsMode: OpsMode = .verify

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
        .task { await client.refresh() }
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
                Button("Run takeover + smoke") {
                    Task {
                        switch opsMode {
                        case .verify:
                            await client.refresh()
                        case .plan:
                            await client.runAutopilot(
                                prompt: "diagnose blockers only, no writes, suggest minimal next action",
                                maxTargets: 1,
                                autoApprove: false
                            )
                        case .act:
                            await client.runAutopilot(prompt: autopilotPrompt, maxTargets: 2, autoApprove: true)
                        }
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
