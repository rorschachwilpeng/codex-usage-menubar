import Foundation

enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): return message
        }
    }
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw TestFailure.assertion(message) }
}

@main
struct TestRunner {
    static func main() async throws {
        try testUsageModels()
        try testRouter()
        try await testUsageStore()
        print("All tests passed")

        if CommandLine.arguments.contains("--smoke") {
            let client = try AppServerClient()
            let response = try await client.readRateLimits()
            let snapshot = UsageSnapshot(response: response, updatedAt: Date())
            print("Smoke: \(snapshot.menuBarTitle)")
            await client.shutdown()
        }
    }

    private static func testUsageModels() throws {
        let json = #"{"rateLimits":{"primary":{"usedPercent":8,"windowDurationMins":10080,"resetsAt":1784338349}}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: json)
        let snapshot = UsageSnapshot(response: response, updatedAt: Date(timeIntervalSince1970: 1))
        try expect(snapshot.weeklyRemaining == 92, "single primary window should be treated as the weekly limit")
        try expect(snapshot.weeklyWindowDurationMins == 10_080, "weekly duration should be retained")
        let presentation = WeeklyPillPresentation(
            snapshot: snapshot,
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        try expect(presentation.remaining == "92%", "weekly percentage should be formatted")
        try expect(presentation.resetDate == "7/18", "menu bar reset should only use month and day")
        try expect(presentation.menuBarText == "💰 92% ｜ 📅 7/18", "menu bar copy should use the compact weekly layout")

        let boundary = UsageSnapshot(response: RateLimitsResponse(rateLimits: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 110, windowDurationMins: nil, resetsAt: nil),
            secondary: nil
        )), updatedAt: .distantPast)
        try expect(boundary.weeklyRemaining == 0, "remaining should clamp to 0")

        let partial = UsageSnapshot(response: RateLimitsResponse(rateLimits: RateLimitSnapshot(
            primary: nil,
            secondary: nil
        )), updatedAt: .distantPast)
        let partialPresentation = WeeklyPillPresentation(
            snapshot: partial,
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        try expect(partialPresentation.remaining == "--%", "missing weekly percentage should use placeholder")
        try expect(partialPresentation.resetDate == "--/--", "missing weekly reset should use placeholder")

        let forecastNow = Date(timeIntervalSince1970: 1_800_000_000)
        let forecastReset = forecastNow.addingTimeInterval(2 * 86_400)
        let fastSnapshot = UsageSnapshot(response: RateLimitsResponse(rateLimits: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 80, windowDurationMins: 10_080, resetsAt: Int64(forecastReset.timeIntervalSince1970)),
            secondary: nil
        )), updatedAt: forecastNow)
        let fastForecast = WeeklyUsageForecast(snapshot: fastSnapshot, now: forecastNow)
        try expect(fastForecast.pace == .fast, "forecast should flag usage that runs out before reset")
        try expect(fastForecast.exhaustionDate != nil, "fast forecast should include an exhaustion date")

        let slowSnapshot = UsageSnapshot(response: RateLimitsResponse(rateLimits: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 60, windowDurationMins: 10_080, resetsAt: Int64(forecastReset.timeIntervalSince1970)),
            secondary: nil
        )), updatedAt: forecastNow)
        let slowForecast = WeeklyUsageForecast(snapshot: slowSnapshot, now: forecastNow)
        try expect(slowForecast.pace == .slow, "forecast should flag a material remaining balance at reset")
        try expect(slowForecast.projectedRemainingAtReset == 16, "forecast should project the remaining weekly balance")

        var history = WeeklyUsageHistory()
        let dayOne = Date(timeIntervalSince1970: 1_800_000_000)
        let dayTwo = dayOne.addingTimeInterval(86_400)
        history.record(remaining: 94, resetAt: forecastReset, observedAt: dayOne)
        history.record(remaining: 88, resetAt: forecastReset, observedAt: dayOne.addingTimeInterval(3_600))
        history.record(remaining: 86, resetAt: forecastReset, observedAt: dayTwo.addingTimeInterval(3_600))
        let dailyUsage = history.dailyUsage(resetAt: forecastReset, timeZone: TimeZone(secondsFromGMT: 0)!)
        try expect(dailyUsage.count == 2, "history should create one bucket per observed calendar day")
        try expect(dailyUsage[0].usedPercent == 6, "history should total same-day usage deltas")
        try expect(dailyUsage[1].usedPercent == 2, "history should put later usage in the next day")
    }

    private static func testRouter() throws {
        let router = RPCMessageRouter()
        let notification = #"{"method":"account/rateLimits/updated","params":{"rateLimits":{}}}"#
        try expect(try router.consume(Data(notification.utf8)) == nil, "notification should be ignored")

        let response = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":9},"secondary":{"usedPercent":1}}}}"#
        let routed = try router.consume(Data(response.utf8))
        try expect(routed?.id == 2, "response ID should be routed")

        let error = #"{"id":3,"error":{"code":-32000,"message":"not logged in"}}"#
        let routedError = try router.consume(Data(error.utf8))
        try expect(routedError?.error == RPCErrorPayload(code: -32000, message: "not logged in"), "RPC error should be preserved")
        try expect(try router.consume(Data("not-json".utf8)) == nil, "malformed JSON should be ignored")
    }

    @MainActor
    private static func testUsageStore() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageMenuBarTests-\(UUID().uuidString)")
        let historyURL = temporaryDirectory.appendingPathComponent("weekly-usage-history.json")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let reset = Date(timeIntervalSince1970: 1_800_604_800)
        let response = RateLimitsResponse(rateLimits: RateLimitSnapshot(
            primary: RateLimitWindow(
                usedPercent: 9,
                windowDurationMins: 10_080,
                resetsAt: Int64(reset.timeIntervalSince1970)
            ),
            secondary: nil
        ))
        let reader = ScriptedReader(results: [.success(response), .failure(TestFailure.assertion("offline"))])
        let store = UsageStore(
            reader: reader,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            historyURL: historyURL
        )

        await store.refresh()
        try expect(store.title == "💰 91% ｜ 📅 1/22", "store should expose the compact weekly title")
        try expect(store.nextRefreshDelay == 30, "success should use 30-second refresh")
        try expect(FileManager.default.fileExists(atPath: historyURL.path), "store should persist the first weekly sample")

        await store.refresh()
        try expect(store.title == "💰 91% ｜ 📅 1/22", "failure should retain last good title")
        try expect(store.isStale, "failure should mark data stale")
        try expect(store.nextRefreshDelay == 30, "first failure should retry after 30 seconds")

        store.markSleeping()
        let callsBeforeSleep = await reader.callCount
        await store.refresh()
        let callsAfterSleep = await reader.callCount
        try expect(callsAfterSleep == callsBeforeSleep, "sleep should suppress refresh")
        store.markAwake()
    }
}

actor ScriptedReader: RateLimitsReading {
    private var results: [Result<RateLimitsResponse, Error>]
    private(set) var callCount = 0

    init(results: [Result<RateLimitsResponse, Error>]) {
        self.results = results
    }

    func readRateLimits() async throws -> RateLimitsResponse {
        callCount += 1
        return try results.removeFirst().get()
    }
}
