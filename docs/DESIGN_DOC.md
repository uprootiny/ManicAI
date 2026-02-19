# ManicAI Design Doc

## 1) Product Intent

ManicAI is a macOS operator console for taming noisy human+AI project loops.

Primary outcome:
- convert chaotic multi-session AI activity into bounded, verifiable progress with minimal operator attention cost.

In one sentence:
- observe many agent sessions, classify blockers, execute one bounded intervention, run smoke checks, report concise delta.

## 2) Design Problem

Current UX has drifted into feature accretion:
- too many controls with weak hierarchy
- unclear mode/state transitions
- visual style inconsistency across cards
- limited affordance clarity for high-risk actions
- weak signal on what to do next

Design objective:
- produce a coherent operator workflow where the next correct action is obvious at every stage.

## 3) Users and Jobs

Primary user:
- one technical operator overseeing many active or idle agent sessions.

Core jobs:
- quickly identify the best takeover target
- unblock stalled agents safely
- keep loops within scope and cadence
- verify outcomes via smoke tests and route health
- ship artifact-backed progress

## 4) Non-Goals

- full autonomous orchestration without human guardrails
- replacing IDE or terminal workflows
- maximizing action volume over action quality
- adding ornamental UI effects that reduce operability

## 5) Constraints

### 5.1 Technical
- macOS-first SwiftUI app (+ legacy AppKit compatibility target)
- remote-first control plane (`/api/state`, `/api/autopilot/run`, `/api/smoke`, etc.)
- potentially high session counts and event throughput
- bounded memory/CPU behavior is mandatory

### 5.2 Safety
- explicit mode boundaries (`Verify`, `Plan`, `Act`)
- panic/degraded breakers must remain visible and actionable
- no silent mutation actions in verify mode

### 5.3 Operational
- network failures and partial route availability are common
- UI must remain useful during degraded connectivity
- all high-value actions must leave concise breadcrumbs

## 6) UX Principles

1. Signal over spectacle.
- surface blockers, confidence, and next action before decorative content.

2. One-turn clarity.
- each state should answer: what is wrong, what can I safely do now, what changed.

3. Bounded action loops.
- one intervention cycle at a time: classify -> act -> smoke -> delta.

4. Progressive disclosure.
- advanced controls stay available but collapsed behind clear operator intent.

5. Stable visual grammar.
- same semantic color/shape rules across all cards and lanes.

## 7) Information Architecture

Top-level surfaces:
- **Command Bar / Header**: mode, health, pressure, panic/degraded states
- **Access + Scope**: endpoint selection, intent latch, objective, done criteria
- **Execution**: queue/autopilot/nudge actions and commutation controls
- **Observability**: takeover candidates, liveness, throughput, route fluency
- **Diagnostics**: breakers, pressure, cadence, telemetry, smoke status
- **Timeline (DAW-like)**: prompt/service/git/file/ontology events with replay

Default view priority (top to bottom):
1. Safety state + mode
2. Blocker summary + recommended next action
3. Action controls
4. Timeline and deep diagnostics

## 8) Interaction Model

## 8.1 Modes
- `Verify`: read-only diagnosis
- `Plan`: simulate/prepare interventions
- `Act`: execute bounded mutations

Mode changes must:
- be explicit
- log to action timeline
- adjust enabled controls immediately

## 8.2 Core loop
1. Refresh/recon
2. Select target (or auto-select best)
3. Classify blocker
4. Run one intervention
5. Trigger smoke
6. Show delta
7. Stop or repeat (bounded)

## 8.3 Control semantics
- destructive/high-risk controls require stronger affordance (color + copy)
- disabled controls must explain why (mode, pressure, breaker, missing capability)
- any auto behavior must expose current policy (cadence/backoff/fanout)

## 9) Visual System

## 9.1 Tone
- precise, operational, calm under load
- avoid novelty UI patterns that obscure state

## 9.2 Design tokens (initial)
- semantic colors:
  - success, warning, danger, info, muted
- semantic badges:
  - `PANIC`, `DEGRADED`, `PRESSURE`, `SYNCING`
- typography:
  - monospaced for telemetry/logs
  - high-legibility sans for labels/headings

## 9.3 Component standards
- Card: consistent heading, status strip, action row, compact metadata
- Badge: all-caps, fixed vertical rhythm, semantic color only
- Buttons:
  - primary: one per panel max
  - secondary: bounded utility actions
  - destructive: isolated and color-coded
- Tables/lists:
  - sortable by throughput/fluency/idle time
  - row actions visible but not noisy

## 10) Timeline UX (DAW-style)

Must represent:
- prompts
- service/API calls
- git artifacts
- file modifications
- ontology/duplex shaping events

Required interactions:
- scrub, step, replay, range select, copy/cut/paste clips
- filter by track and event kind
- preserve operator context while replay runs

Guardrails:
- replay should throttle under pressure state
- timeline controls should never crash on sparse/empty ranges

## 11) Performance + Reliability Targets

- refresh loop remains responsive under high pane/session counts
- bounded in-memory event retention
- debounced persistence/recompute paths
- explicit high-pressure mode when thresholds are crossed
- degraded-mode fallback remains actionable

## 12) Accessibility and Ergonomics

- keyboard-first control for frequent actions
- minimum contrast compliance for status badges
- avoid tiny hit targets in dense panels
- compact mode for small laptop screens

## 13) Content and Language

All operator copy should be:
- short
- specific
- action-oriented

Prefer:
- "blocked by approval gate; choose approve/skip"
Over:
- "system experiencing uncertainty"

## 14) Acceptance Criteria (Design)

A build is design-acceptable when:
- a new operator can complete one full classify->act->smoke loop in under 2 minutes
- current mode/safety state is always visually obvious
- next recommended action is visible without scrolling
- timeline replay + range operations remain stable under sparse and heavy histories
- no contradictory visual semantics across panels

## 15) Near-Term Design Milestones

M1: IA cleanup
- reorganize panels into Safety / Execution / Diagnostics / Timeline
- collapse low-frequency controls

M2: Interaction hardening
- explicit disabled-state reasons on all gated controls
- consistent action feedback to timeline + delta summary

M3: Visual unification
- adopt tokenized color/spacing/typography system
- normalize card/button/badge patterns

M4: Operator efficiency
- keyboard command palette for top 8 actions
- one-click "run bounded loop" macro with visible policy

## 16) Open Questions

- Should `Act` mode require a per-session temporary arm/disarm toggle?
- Should `PRESSURE` auto-force `Plan` mode after threshold duration?
- Which timeline tracks should be default-visible for first-run operators?
