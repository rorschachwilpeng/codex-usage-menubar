import Foundation

protocol RateLimitsReading: Sendable {
    func readRateLimits() async throws -> RateLimitsResponse
}

enum AppServerClientError: Error, Equatable, LocalizedError {
    case executableNotFound
    case processStopped
    case timeout
    case invalidResponse
    case rpc(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound: return "Codex executable not found"
        case .processStopped: return "Codex app-server stopped"
        case .timeout: return "Timed out while reading usage limits"
        case .invalidResponse: return "Codex returned an invalid response"
        case let .rpc(_, message): return message
        }
    }
}

struct RPCErrorPayload: Decodable, Equatable {
    let code: Int
    let message: String
}

struct RoutedRPCMessage: Equatable {
    let id: Int
    let error: RPCErrorPayload?
    let data: Data
}

struct RPCMessageRouter {
    private struct Header: Decodable {
        let id: Int?
        let error: RPCErrorPayload?
    }

    func consume(_ data: Data) throws -> RoutedRPCMessage? {
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              let id = header.id else {
            return nil
        }
        return RoutedRPCMessage(id: id, error: header.error, data: data)
    }
}

actor AppServerClient: RateLimitsReading {
    private struct RateLimitsRPCResponse: Decodable {
        let result: RateLimitsResponse?
        let error: RPCErrorPayload?
    }

    private let executableURL: URL
    private let router = RPCMessageRouter()
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var diagnostic = ""

    init(executableURL: URL? = nil) throws {
        if let executableURL {
            self.executableURL = executableURL
            return
        }

        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            environment["CODEX_EXECUTABLE"],
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            Self.executableOnPath(named: "codex", path: environment["PATH"])
        ].compactMap { $0 }
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw AppServerClientError.executableNotFound
        }
        self.executableURL = URL(fileURLWithPath: path)
    }

    func readRateLimits() async throws -> RateLimitsResponse {
        try await ensureStarted()
        let data = try await sendRequest(method: "account/rateLimits/read", params: NSNull())
        let response = try JSONDecoder().decode(RateLimitsRPCResponse.self, from: data)
        if let error = response.error {
            throw AppServerClientError.rpc(code: error.code, message: error.message)
        }
        guard let result = response.result else {
            throw AppServerClientError.invalidResponse
        }
        return result
    }

    func shutdown() {
        input?.closeFile()
        input = nil
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        failPending(with: AppServerClientError.processStopped)
    }

    func recentDiagnostic() -> String {
        diagnostic
    }

    private func ensureStarted() async throws {
        if process?.isRunning == true { return }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let client = self else { return }
            Task { await client.consumeOutput(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let client = self else { return }
            Task { await client.appendDiagnostic(data) }
        }
        process.terminationHandler = { [weak self] _ in
            guard let client = self else { return }
            Task { await client.processDidStop() }
        }

        try process.run()
        self.process = process
        input = stdinPipe.fileHandleForWriting

        _ = try await sendRequest(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "codex-usage-menubar",
                    "title": "Codex Usage Menu Bar",
                    "version": "1.0.0"
                ]
            ]
        )
        try writeJSON(["method": "initialized"])
    }

    private func sendRequest(method: String, params: Any) async throws -> Data {
        guard process?.isRunning == true else {
            throw AppServerClientError.processStopped
        }
        let id = nextRequestID
        nextRequestID += 1
        try writeJSON(["id": id, "method": method, "params": params])

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self.timeoutRequest(id)
            }
        }
    }

    private func writeJSON(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input?.write(contentsOf: data)
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            guard let message = try? router.consume(line) else { continue }
            guard let continuation = pending.removeValue(forKey: message.id) else { continue }
            if let error = message.error {
                continuation.resume(throwing: AppServerClientError.rpc(code: error.code, message: error.message))
            } else {
                continuation.resume(returning: message.data)
            }
        }
    }

    private func appendDiagnostic(_ data: Data) {
        diagnostic += String(decoding: data, as: UTF8.self)
        if diagnostic.count > 4_000 {
            diagnostic = String(diagnostic.suffix(4_000))
        }
    }

    private func timeoutRequest(_ id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: AppServerClientError.timeout)
    }

    private func processDidStop() {
        process = nil
        input = nil
        failPending(with: AppServerClientError.processStopped)
    }

    private func failPending(with error: Error) {
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    private static func executableOnPath(named name: String, path: String?) -> String? {
        path?.split(separator: ":")
            .map { String($0) + "/" + name }
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }
}
