import Foundation

enum UsageStatus: Equatable {
    case loading
    case fresh
    case stale(String)
    case loginRequired
}

@MainActor
final class UsageStore {
    private let reader: any RateLimitsReading
    private let now: () -> Date
    private let cacheURL: URL?
    private let historyURL: URL?
    private(set) var snapshot: UsageSnapshot?
    private(set) var history: WeeklyUsageHistory
    private(set) var status: UsageStatus = .loading
    private(set) var failureCount = 0
    private(set) var isSleeping = false

    init(
        reader: any RateLimitsReading,
        now: @escaping () -> Date = Date.init,
        cacheURL: URL? = nil,
        historyURL: URL? = nil
    ) {
        self.reader = reader
        self.now = now
        self.cacheURL = cacheURL
        self.historyURL = historyURL
        snapshot = Self.loadCache(from: cacheURL)
        history = Self.loadHistory(from: historyURL)
        if snapshot != nil { status = .stale("Waiting to refresh") }
    }

    var title: String {
        snapshot?.menuBarTitle ?? "Usage --"
    }

    var isStale: Bool {
        if case .stale = status { return true }
        return false
    }

    var nextRefreshDelay: TimeInterval {
        guard failureCount > 0 else { return 30 }
        let exponent = min(max(failureCount - 1, 0), 4)
        return min(300, 30 * pow(2, Double(exponent)))
    }

    func refresh() async {
        guard !isSleeping else { return }
        do {
            let response = try await reader.readRateLimits()
            let newSnapshot = UsageSnapshot(response: response, updatedAt: now())
            snapshot = newSnapshot
            if let remaining = newSnapshot.weeklyRemaining, let reset = newSnapshot.weeklyResetsAt {
                history.record(remaining: remaining, resetAt: reset, observedAt: newSnapshot.updatedAt)
                saveHistory()
            }
            status = .fresh
            failureCount = 0
            saveCache(newSnapshot)
        } catch {
            failureCount += 1
            let message = error.localizedDescription
            let normalized = message.lowercased()
            if normalized.contains("login") || normalized.contains("auth") || normalized.contains("登录") {
                status = .loginRequired
            } else {
                status = .stale(message)
            }
        }
    }

    func markSleeping() {
        isSleeping = true
    }

    func markAwake() {
        isSleeping = false
    }

    private func saveCache(_ snapshot: UsageSnapshot) {
        guard let cacheURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: cacheURL, options: .atomic)
        } catch {
            // Cache failure must never block live usage updates.
        }
    }

    private static func loadCache(from url: URL?) -> UsageSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    private func saveHistory() {
        guard let historyURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: historyURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(history).write(to: historyURL, options: .atomic)
        } catch {
            // History is an enhancement and must not block usage refreshes.
        }
    }

    private static func loadHistory(from url: URL?) -> WeeklyUsageHistory {
        guard let url, let data = try? Data(contentsOf: url) else { return WeeklyUsageHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WeeklyUsageHistory.self, from: data)) ?? WeeklyUsageHistory()
    }
}
