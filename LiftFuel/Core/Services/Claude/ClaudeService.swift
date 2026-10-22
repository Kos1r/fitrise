import Foundation

/// Network layer for the coach. Protocol-based so the UI, previews and tests can use a mock.
protocol ClaudeServicing: Sendable {
    func stream(_ request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error>
}

final class ClaudeService: ClaudeServicing {
    private let session: URLSession
    private let endpointProvider: @Sendable () -> ClaudeEndpoint?

    init(session: URLSession = .shared, endpointProvider: @escaping @Sendable () -> ClaudeEndpoint? = { CoachConnection.endpoint() }) {
        self.session = session
        self.endpointProvider = endpointProvider
    }

    func stream(_ request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let session = self.session
        let endpointProvider = self.endpointProvider
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let endpoint = endpointProvider() else { throw ClaudeError.notConfigured }
                    var urlRequest = URLRequest(url: endpoint.url, timeoutInterval: AppConfig.requestTimeout)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "accept")
                    urlRequest.setValue(AppConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
                    urlRequest.setValue(AppConfig.anthropicBeta, forHTTPHeaderField: "anthropic-beta")
                    for (field, value) in endpoint.headers {
                        urlRequest.setValue(value, forHTTPHeaderField: field)
                    }
                    urlRequest.httpBody = request.body.serialized()

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 32_000 { break }
                        }
                        throw ClaudeError.from(
                            status: http.statusCode,
                            body: body,
                            retryAfterHeader: http.value(forHTTPHeaderField: "retry-after")
                        )
                    }

                    var parser = SSEParser()
                    var accumulator = StreamAccumulator()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let event = parser.consume(line: line) else { continue }
                        if let text = try accumulator.process(eventData: event.data), !text.isEmpty {
                            continuation.yield(.textDelta(text))
                        }
                    }
                    continuation.yield(.completed(try accumulator.finalMessage()))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ClaudeError.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Offline stand-in used by previews, UI tests and when no network is wanted.
/// It "estimates" a meal from the text so the full logging flow can be exercised.
struct MockClaudeService: ClaudeServicing {
    var delay: Duration = .milliseconds(30)

    func stream(_ request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let delay = self.delay
        let hasToolResult = request.messages.last?["content"]?.arrayValue?.contains { $0["type"]?.stringValue == "tool_result" } ?? false
        let lastUserText = request.messages.last?["content"]?.arrayValue?
            .compactMap { $0["text"]?.stringValue }.joined(separator: " ") ?? ""
        return AsyncThrowingStream { continuation in
            let task = Task {
                if hasToolResult {
                    let reply = "Logged! That puts you closer to today's targets — keep the protein coming at dinner."
                    for word in reply.split(separator: " ") {
                        try? await Task.sleep(for: delay)
                        continuation.yield(.textDelta(String(word) + " "))
                    }
                    continuation.yield(.completed(ClaudeMessage(content: [["type": "text", "text": .string(reply)]], stopReason: "end_turn")))
                } else if lastUserText.lowercased().contains("left") || lastUserText.lowercased().contains("need") {
                    let toolUse: JSONValue = ["type": "tool_use", "id": "toolu_mock_summary", "name": "get_daily_summary", "input": [:]]
                    continuation.yield(.completed(ClaudeMessage(content: [toolUse], stopReason: "tool_use")))
                } else {
                    let toolUse = (try? JSONValue.parse(Self.mockMealToolUse)) ?? .object([:])
                    try? await Task.sleep(for: delay * 10)
                    continuation.yield(.completed(ClaudeMessage(content: [toolUse], stopReason: "tool_use")))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension MockClaudeService {
    static let mockMealToolUse = """
    {"type":"tool_use","id":"toolu_mock_meal","name":"log_meal","input":{
      "meal_name":"Eggs on toast","meal_type":"breakfast","confidence":"high","items":[
        {"name":"Scrambled eggs","quantity_description":"2 large eggs","grams_estimate":110,"calories":180,"protein_g":13,"carbs_g":2,"fat_g":13,"fiber_g":0},
        {"name":"Toast with butter","quantity_description":"2 slices","grams_estimate":70,"calories":230,"protein_g":6,"carbs_g":28,"fat_g":10,"fiber_g":2},
        {"name":"Banana","quantity_description":"1 medium","grams_estimate":118,"calories":105,"protein_g":1.3,"carbs_g":27,"fat_g":0.4,"fiber_g":3.1}
      ]}}
    """
}
