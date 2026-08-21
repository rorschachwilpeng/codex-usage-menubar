import Foundation

struct RateLimitWindow: Codable, Equatable, Sendable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?
}

struct RateLimitSnapshot: Codable, Equatable, Sendable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

struct RateLimitsResponse: Codable, Equatable, Sendable {
    let rateLimits: RateLimitSnapshot
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    let primaryRemaining: Int?
    let secondaryRemaining: Int?
    let primaryResetsAt: Date?
    let secondaryResetsAt: Date?
    let primaryWindowDurationMins: Int?
    let secondaryWindowDurationMins: Int?
    let updatedAt: Date

    init(response: RateLimitsResponse, updatedAt: Date) {
        primaryRemaining = Self.remaining(from: response.rateLimits.primary)
        secondaryRemaining = Self.remaining(from: response.rateLimits.secondary)
        primaryResetsAt = Self.resetDate(from: response.rateLimits.primary)
        secondaryResetsAt = Self.resetDate(from: response.rateLimits.secondary)
        primaryWindowDurationMins = response.rateLimits.primary?.windowDurationMins
        secondaryWindowDurationMins = response.rateLimits.secondary?.windowDurationMins
        self.updatedAt = updatedAt
    }

    // Newer Codex versions expose the weekly window as `primary`; older versions used `secondary`.
    var weeklyRemaining: Int? { secondaryRemaining ?? primaryRemaining }
    var weeklyResetsAt: Date? { secondaryResetsAt ?? primaryResetsAt }
    var weeklyWindowDurationMins: Int? { secondaryWindowDurationMins ?? primaryWindowDurationMins ?? 10_080 }

    var menuBarTitle: String {
        WeeklyPillPresentation(snapshot: self).menuBarText
    }

    private static func remaining(from window: RateLimitWindow?) -> Int? {
        window.map { max(0, min(100, 100 - $0.usedPercent)) }
    }

    private static func resetDate(from window: RateLimitWindow?) -> Date? {
        window?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

struct UsagePillPresentation: Equatable, Sendable {
    let primaryPercent: String
    let primaryReset: String
    let primaryIsUrgent: Bool
    let secondaryPercent: String
    let secondaryReset: String
    let secondaryIsUrgent: Bool

    init(
        snapshot: UsageSnapshot?,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) {
        primaryPercent = Self.percent(snapshot?.primaryRemaining)
        primaryReset = Self.format(snapshot?.primaryResetsAt, pattern: "HH:mm", placeholder: "--:--", timeZone: timeZone)
        primaryIsUrgent = Self.isUrgent(snapshot?.primaryResetsAt, now: now)
        secondaryPercent = Self.percent(snapshot?.secondaryRemaining)
        secondaryReset = Self.format(snapshot?.secondaryResetsAt, pattern: "M/d", placeholder: "--/--", timeZone: timeZone)
        secondaryIsUrgent = Self.isUrgent(snapshot?.secondaryResetsAt, now: now)
    }

    private static func percent(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "--%"
    }

    private static func format(_ date: Date?, pattern: String, placeholder: String, timeZone: TimeZone) -> String {
        guard let date else { return placeholder }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func isUrgent(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        let interval = date.timeIntervalSince(now)
        return interval > 0 && interval < 3_600
    }
}
