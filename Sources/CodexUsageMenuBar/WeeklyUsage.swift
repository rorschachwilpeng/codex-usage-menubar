import Foundation

struct WeeklyPillPresentation: Equatable, Sendable {
    let remaining: String
    let resetDate: String

    init(snapshot: UsageSnapshot?, timeZone: TimeZone = .current) {
        remaining = snapshot?.weeklyRemaining.map { "\($0)%" } ?? "--%"
        guard let reset = snapshot?.weeklyResetsAt else {
            resetDate = "--/--"
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d"
        resetDate = formatter.string(from: reset)
    }

    var menuBarText: String { "💰 \(remaining) ｜ 📅 \(resetDate)" }
}

enum WeeklyUsagePace: Equatable, Sendable {
    case collecting
    case fast
    case suitable
    case slow
}

struct WeeklyUsageForecast: Equatable, Sendable {
    let pace: WeeklyUsagePace
    let exhaustionDate: Date?
    let projectedRemainingAtReset: Int?
    let dailyRate: Int?

    init(snapshot: UsageSnapshot?, now: Date = Date()) {
        guard let snapshot,
              let remaining = snapshot.weeklyRemaining,
              let reset = snapshot.weeklyResetsAt,
              let durationMins = snapshot.weeklyWindowDurationMins,
              reset > now else {
            pace = .collecting
            exhaustionDate = nil
            projectedRemainingAtReset = nil
            dailyRate = nil
            return
        }

        let cycleStart = reset.addingTimeInterval(-TimeInterval(durationMins * 60))
        let elapsed = now.timeIntervalSince(cycleStart)
        let used = 100 - remaining
        guard elapsed >= 15 * 60, used > 0 else {
            pace = .collecting
            exhaustionDate = nil
            projectedRemainingAtReset = nil
            dailyRate = nil
            return
        }

        let rate = Double(used) / elapsed
        let remainingTime = reset.timeIntervalSince(now)
        let projected = Double(remaining) - rate * remainingTime
        let exhaustion = now.addingTimeInterval(Double(remaining) / rate)

        exhaustionDate = exhaustion < reset ? exhaustion : nil
        projectedRemainingAtReset = max(0, Int(projected.rounded()))
        dailyRate = Int((rate * 86_400).rounded())
        if exhaustion < reset {
            pace = .fast
        } else if projectedRemainingAtReset! <= 10 {
            pace = .suitable
        } else {
            pace = .slow
        }
    }
}

struct WeeklyUsageSample: Codable, Equatable, Sendable {
    let remaining: Int
    let resetAt: Date
    let observedAt: Date
}

struct DailyUsage: Equatable, Sendable {
    let day: Date
    let usedPercent: Int
}

struct WeeklyUsageHistory: Codable, Equatable, Sendable {
    private(set) var samples: [WeeklyUsageSample] = []

    mutating func record(remaining: Int, resetAt: Date, observedAt: Date) {
        if let last = samples.last,
           last.resetAt == resetAt,
           last.remaining == remaining {
            return
        }
        samples.append(WeeklyUsageSample(remaining: remaining, resetAt: resetAt, observedAt: observedAt))
        let oldest = observedAt.addingTimeInterval(-21 * 86_400)
        samples.removeAll { $0.observedAt < oldest }
    }

    func dailyUsage(resetAt: Date, timeZone: TimeZone) -> [DailyUsage] {
        let cycleSamples = samples
            .filter { $0.resetAt == resetAt }
            .sorted { $0.observedAt < $1.observedAt }
        guard cycleSamples.count > 1 else { return [] }

        var totals: [Date: Int] = [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        for (previous, current) in zip(cycleSamples, cycleSamples.dropFirst()) {
            let delta = previous.remaining - current.remaining
            guard delta > 0 else { continue }
            let day = calendar.startOfDay(for: current.observedAt)
            totals[day, default: 0] += delta
        }
        return totals
            .map { DailyUsage(day: $0.key, usedPercent: $0.value) }
            .sorted { $0.day < $1.day }
    }
}
