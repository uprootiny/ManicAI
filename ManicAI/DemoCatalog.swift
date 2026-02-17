import Foundation

struct DemoProject: Identifiable {
    let id: String
    let name: String
    let summary: String
    let macSpinup: String
    let linuxSpinup: String
    let diagnostics: String
    let smoke: String
    let defaultPrompt: String
}

enum DemoCatalog {
    static let projects: [DemoProject] = [
        DemoProject(
            id: "hyle",
            name: "hyle",
            summary: "Rust-native autonomous coding assistant with smoke-friendly CLI.",
            macSpinup: "cargo run --bin hyle -- --free",
            linuxSpinup: "cd /home/uprootiny/dec27/hyle && cargo run --bin hyle -- --free",
            diagnostics: "hyle doctor && hyle sessions --list",
            smoke: "make smoke",
            defaultPrompt: "run smoke checks, fix first blocker, rerun smoke, report concise status"
        ),
        DemoProject(
            id: "coggy",
            name: "coggy",
            summary: "Multi-role cognitive substrate with role panes and grounding traces.",
            macSpinup: "cd ~/coggy && ./coggy start",
            linuxSpinup: "cd /home/uprootiny/coggy && ./coggy start",
            diagnostics: "cd /home/uprootiny/coggy && ./coggy doctor --json && curl -s http://127.0.0.1:8421/api/openrouter/status | jq",
            smoke: "cd /home/uprootiny/coggy && ./coggy smoke",
            defaultPrompt: "run smoke checks, fix first blocker, rerun smoke, report concise status"
        ),
        DemoProject(
            id: "hyperpanel",
            name: "hyperpanel",
            summary: "Operator web shell for takeover candidates, blockers, and autopilot loops.",
            macSpinup: "make hyperpanel",
            linuxSpinup: "cd /home/uprootiny/dec27/hyle && make hyperpanel",
            diagnostics: "curl -s http://127.0.0.1:8788/api/state | jq '{sessions:(.sessions|length),candidates:(.takeover_candidates|length),smoke:.smoke.status}'",
            smoke: "curl -s -X POST http://127.0.0.1:8788/api/autopilot/run -H 'content-type: application/json' --data '{\"prompt\":\"run smoke checks, fix first blocker, rerun smoke, report concise status\",\"max_targets\":2,\"auto_approve\":true}'",
            defaultPrompt: "run smoke checks, fix first blocker, rerun smoke, report concise status"
        ),
        DemoProject(
            id: "manicai",
            name: "ManicAI",
            summary: "Styled macOS control app over hyperpanel state/autopilot APIs.",
            macSpinup: "cd apps/ManicAI && xcodegen generate && open ManicAI.xcodeproj",
            linuxSpinup: "Build via GitHub Actions matrix (macos-26 + macos-15-intel)",
            diagnostics: "Verify base URL -> /api/state and candidate pane rendering in UI",
            smoke: "Run CI workflow: Build ManicAI macOS app",
            defaultPrompt: "refresh panel state, surface top blockers, and propose next deterministic intervention"
        ),
        DemoProject(
            id: "corpora",
            name: "corpora",
            summary: "Corpus-grounded project lane for retrieval, indexing, and source quality checks.",
            macSpinup: "cd ~/corpora && make dev  # if present",
            linuxSpinup: "find /home/uprootiny -maxdepth 5 -type d -name corpora; cd <corpora-path> && make smoke || make test",
            diagnostics: "rg -n 'TODO|FIXME' . && git status --short",
            smoke: "make smoke || ./scripts/smoke_feedback.sh || make test",
            defaultPrompt: "run smoke checks, fix first blocker, rerun smoke, report concise status"
        ),
        DemoProject(
            id: "demesne",
            name: "demesne",
            summary: "Operations/domain orchestration lane with structured runbooks and policy checks.",
            macSpinup: "cd ~/demesne && make dev  # if present",
            linuxSpinup: "find /home/uprootiny -maxdepth 5 -type d -name demesne; cd <demesne-path> && make smoke || make test",
            diagnostics: "git rev-parse --abbrev-ref HEAD && git status --porcelain=v1 | wc -l",
            smoke: "make smoke || ./scripts/smoke_feedback.sh || make test",
            defaultPrompt: "run smoke checks, fix first blocker, rerun smoke, report concise status"
        ),
        DemoProject(
            id: "webdash",
            name: "webdash",
            summary: "Dashboard-first project lane for observability UI, telemetry, and operator workflows.",
            macSpinup: "cd ~/webdash && npm run dev  # if present",
            linuxSpinup: "find /home/uprootiny -maxdepth 5 -type d -name webdash; cd <webdash-path> && npm test || make smoke",
            diagnostics: "curl -s http://127.0.0.1:8788/api/state | jq '{sessions:(.sessions|length),candidates:(.takeover_candidates|length)}'",
            smoke: "npm test || make smoke || ./scripts/smoke_feedback.sh",
            defaultPrompt: "run smoke checks, fix first blocker, rerun smoke, report concise status"
        )
    ]

    static let freeModelCatalogHint = "./scripts/playtests/openrouter_free_catalog.py --out-dir ."
    static let providerDiagnosticsHint = "cd /home/uprootiny/coggy && ./coggy doctor --json && curl -s http://127.0.0.1:8421/api/openrouter/models | jq"
}
