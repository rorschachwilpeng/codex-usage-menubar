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
        let json = #"{"rateLimits":{"primary":{"usedPercent":9,"windowDurationMins":300,"resetsAt":1783751549},"secondary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1784338349}}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: json)
        let snapshot = UsageSnapshot(response: response, updatedAt: Date(timeIntervalSince1970: 1))
        try expect(snapshot.primaryRemaining == 91, "primary remaining should be 91")
        try expect(snapshot.secondaryRemaining == 99, "secondary remaining should be 99")
        try expect(snapshot.menuBarTitle == "5h: 91% | week: 99%", "menu title should match")
        let presentation = UsagePillPresentation(
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 1_783_751_000),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        try expect(presentation.primaryPercent == "91%", "primary percentage should be formatted")
        try expect(presentation.secondaryPercent == "99%", "secondary percentage should be formatted")
        try expect(presentation.primaryReset == "14:32", "primary reset should use HH:mm")
        try expect(presentation.secondaryReset == "7/18", "weekly reset should use M/d")
        try expect(presentation.primaryIsUrgent, "primary reset within one hour should be urgent")
        try expect(!presentation.secondaryIsUrgent, "weekly reset outside one hour should not be urgent")

        let boundary = UsageSnapshot(response: RateLimitsResponse(rateLimits: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: -5, windowDurationMins: nil, resetsAt: nil),
            secondary: RateLimitWindow(usedPercent: 110, windowDurationMins: nil, resetsAt: nil)
        )), updatedAt: .distantPast)
        try expect(boundary.primaryRemaining == 100, "remaining should clamp to 100")
        try expect(boundary.secondaryRemaining == 0, "remaining should clamp to 0")

        let partial = UsageSnapshot(response: RateLimitsResponse(rateLimits: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 9, windowDurationMins: nil, resetsAt: nil),
            secondary: nil
        )), updatedAt: .distantPast)
        try expect(partial.menuBarTitle == "5h: 91% | week: --%", "missing window should use placeholder")
        let partialPresentation = UsagePillPresentation(
            snapshot: partial,
            now: .distantPast,
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        try expect(partialPresentation.primaryReset == "--:--", "missing primary reset should use placeholder")
        try expect(partialPresentation.secondaryPercent == "--%", "missing weekly percentage should use placeholder")
        try expect(partialPresentation.secondaryReset == "--/--", "missing weekly reset should use placeholder")
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
        let response = RateLimitsResponse(rateLimits: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 9, windowDurationMins: 300, resetsAt: nil),
            secondary: RateLimitWindow(usedPercent: 1, windowDurationMins: 10_080, resetsAt: nil)
        ))
        let reader = ScriptedReader(results: [.success(response), .failure(TestFailure.assertion("offline"))])
        let store = UsageStore(reader: reader, now: { Date(timeIntervalSince1970: 1) })

        await store.refresh()
        try expect(store.title == "5h: 91% | week: 99%", "store should expose live title")
        try expect(store.nextRefreshDelay == 30, "success should use 30-second refresh")

        await store.refresh()
        try expect(store.title == "5h: 91% | week: 99%", "failure should retain last good title")
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
