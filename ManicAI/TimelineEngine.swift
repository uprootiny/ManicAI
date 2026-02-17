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
}
