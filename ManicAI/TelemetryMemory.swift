import Foundation

struct StoredAPICallStats: Codable {
    let success: Int
    let failure: Int
    let updatedAt: TimeInterval
}

enum TelemetryMemory {
    static func applyDecay(
        to stats: [String: StoredAPICallStats],
        now: Date = Date(),
        halfLifeSec: TimeInterval
    ) -> [String: StoredAPICallStats] {
        guard halfLifeSec > 0 else { return stats }
        var out: [String: StoredAPICallStats] = [:]
        for (key, value) in stats {
            let elapsed = max(0, now.timeIntervalSince1970 - value.updatedAt)
            let factor = pow(0.5, elapsed / halfLifeSec)
            let decayedSuccess = Int((Double(value.success) * factor).rounded())
            let decayedFailure = Int((Double(value.failure) * factor).rounded())
            if decayedSuccess > 0 || decayedFailure > 0 {
                out[key] = StoredAPICallStats(
                    success: decayedSuccess,
                    failure: decayedFailure,
                    updatedAt: now.timeIntervalSince1970
                )
            }
        }
        return out
    }
}
