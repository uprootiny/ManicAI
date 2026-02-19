# Recentering Prompts

ManicAI now includes a built-in "Recentering Interrupts" library in the Sampler panel.

## Integrated prompts
- Gentle Tap
- Ground Reality Anchor
- Anti-Hallucination Lock
- Over-Engineering Interrupt
- Loop Escape
- Diff Minimizer
- Framework Delusion Breaker
- Hard Reset

## Auto-selection signals
The app infers a suggested prompt from live takeover captures + action log patterns.

Current heuristic highlights:
- `framework` / `migration` -> Framework Delusion Breaker
- `unknown command` / `no structured trace` / high agitation -> Hard Reset
- repeated retry language (`proceed`, `retry`, `again`) -> Loop Escape
- missing-symbol signals (`undefined`, `not found`) -> Anti-Hallucination Lock
- file churn signals (`new file`, `create mode`, `wrote`) -> Over-Engineering Interrupt
- no smoke/test mentions -> Ground Reality Anchor

Fallback: Gentle Tap.

## Operator actions
From the Sampler panel:
- Auto-select from live captures
- Use as autopilot prompt
- Queue to pane text
