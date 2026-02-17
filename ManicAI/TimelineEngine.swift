import Foundation

struct TimelineTrack: Identifiable {
    var id: String { name }
    let name: String
    let events: [PromptEvent]
}

enum TimelineEngine {
    static func sortedEvents(_ events: [PromptEvent]) -> [PromptEvent] {
        events.sorted(by: { $0.ts < $1.ts })
    }

    static func tracks(_ events: [PromptEvent]) -> [TimelineTrack] {
        let grouped = Dictionary(grouping: sortedEvents(events)) { $0.target ?? "-" }
        return grouped.keys.sorted().map { TimelineTrack(name: $0, events: grouped[$0] ?? []) }
    }

    static func events(forTrack track: String, allEvents: [PromptEvent]) -> [PromptEvent] {
        let sorted = sortedEvents(allEvents)
        guard track != "ALL" else { return sorted }
        return sorted.filter { ($0.target ?? "-") == track }
    }

    static func rangeEvents(_ events: [PromptEvent], start: Int, end: Int) -> [PromptEvent] {
        guard !events.isEmpty else { return [] }
        let lo = min(start, end)
        let hi = max(start, end)
        let clampedLo = min(max(0, lo), events.count - 1)
        let clampedHi = min(max(0, hi), events.count - 1)
        return Array(events[clampedLo...clampedHi])
    }

    static func cadenceDeltas(_ events: [PromptEvent]) -> [Double] {
        let sorted = sortedEvents(events)
        guard sorted.count > 1 else { return [] }
        return zip(sorted.dropFirst(), sorted).map { max(0, $0.ts - $1.ts) }
    }

    static func layerCounts(_ events: [PromptEvent]) -> [TimelineKind: Int] {
        var out: [TimelineKind: Int] = [:]
        for ev in events {
            out[ev.kind, default: 0] += 1
        }
        return out
    }

    static func cadenceStats(_ events: [PromptEvent]) -> CadenceStats {
        let deltas = cadenceDeltas(events).sorted()
        guard !deltas.isEmpty else {
            return CadenceStats(meanSec: 0, p50Sec: 0, p90Sec: 0, burstRatioPct: 0, longestIdleSec: 0)
        }
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        let p50 = percentile(deltas, q: 0.50)
        let p90 = percentile(deltas, q: 0.90)
        let burst = (Double(deltas.filter { $0 < 60 }.count) / Double(deltas.count)) * 100
        let longest = deltas.last ?? 0
        return CadenceStats(meanSec: mean, p50Sec: p50, p90Sec: p90, burstRatioPct: burst, longestIdleSec: longest)
    }

    static func layerEdges(_ events: [PromptEvent]) -> [LayerEdgeMetric] {
        let sorted = sortedEvents(events)
        guard sorted.count > 1 else { return [] }
        var acc: [String: (from: TimelineKind, to: TimelineKind, count: Int, latency: Double, quality: Double)] = [:]
        for (cur, prev) in zip(sorted.dropFirst(), sorted) {
            let from = prev.kind
            let to = cur.kind
            let latency = max(0, cur.ts - prev.ts)
            let q = edgeQuality(from: from, to: to, latencySec: latency)
            let key = "\(from.rawValue)->\(to.rawValue)"
            let old = acc[key] ?? (from, to, 0, 0, 0)
            acc[key] = (from, to, old.count + 1, old.latency + latency, old.quality + q)
        }
        return acc.values
            .map {
                LayerEdgeMetric(
                    from: $0.from,
                    to: $0.to,
                    count: $0.count,
                    avgLatencySec: $0.latency / Double($0.count),
                    avgQuality: $0.quality / Double($0.count)
                )
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.id < $1.id
            }
    }

    static func edgeQuality(from: TimelineKind, to: TimelineKind, latencySec: Double) -> Double {
        let expected: Set<String> = [
            "prompt->service",
            "duplex->service",
            "service->ontology",
            "service->git",
            "service->file",
            "ontology->service",
            "ontology->git",
            "ontology->file",
            "git->service",
            "file->service"
        ]
        let key = "\(from.rawValue)->\(to.rawValue)"
        var score = 60.0
        if expected.contains(key) { score += 25.0 }
        if latencySec < 30 { score += 10.0 }
        if latencySec > 300 { score -= 15.0 }
        return min(100, max(0, score))
    }

    private static func percentile(_ xs: [Double], q: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let clamped = min(1, max(0, q))
        let idx = Int((Double(xs.count - 1) * clamped).rounded())
        return xs[idx]
    }
}
