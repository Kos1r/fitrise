import XCTest
@testable import LiftFuel

final class ClaudeParsingTests: XCTestCase {
    // MARK: Non-streaming response

    func testParsesToolUseResponse() throws {
        let json = """
        {"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-5-5",
         "content":[
           {"type":"thinking","thinking":"","signature":"sig123"},
           {"type":"text","text":"Logging that now."},
           {"type":"tool_use","id":"toolu_1","name":"log_meal","input":{
             "meal_name":"Eggs on toast","meal_type":"breakfast","confidence":"high",
             "items":[{"name":"Egg","quantity_description":"2 large","grams_estimate":100,"calories":143,"protein_g":12.6,"carbs_g":0.7,"fat_g":9.5,"fiber_g":0}]
           }}
         ],
         "stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":20}}
        """
        let message = try ClaudeResponseParser.parse(Data(json.utf8))
        XCTAssertEqual(message.stopReason, "tool_use")
        XCTAssertEqual(message.text, "Logging that now.")
        XCTAssertEqual(message.content.count, 3)
        XCTAssertEqual(message.content[0]["signature"]?.stringValue, "sig123")
        let toolUse = try XCTUnwrap(message.toolUses.first)
        XCTAssertEqual(toolUse.name, CoachTools.logMeal)

        let input = try LogMealInput(json: toolUse.input)
        XCTAssertEqual(input.mealName, "Eggs on toast")
        XCTAssertEqual(input.mealType, .breakfast)
        XCTAssertEqual(input.confidence, .high)
        XCTAssertEqual(input.items.count, 1)
        XCTAssertEqual(input.items[0].protein, 12.6, accuracy: 0.001)
        XCTAssertEqual(input.totals.calories, 143)
    }

    func testRejectsNonMessage() {
        XCTAssertThrowsError(try ClaudeResponseParser.parse(Data(#"{"type":"error","error":{"type":"overloaded_error"}}"#.utf8)))
    }

    // MARK: log_meal validation

    func testLogMealRequiresItems() {
        let json: JSONValue = ["meal_name": "Nothing", "items": .array([]), "meal_type": "snack", "confidence": "high"]
        XCTAssertThrowsError(try LogMealInput(json: json)) { error in
            XCTAssertEqual(error as? LogMealInput.ParseError, .noItems)
        }
    }

    func testLogMealRejectsNegativeValues() throws {
        let json = try JSONValue.parse(#"{"meal_name":"Bad","meal_type":"lunch","confidence":"high","items":[{"name":"x","quantity_description":"","grams_estimate":10,"calories":-5,"protein_g":1,"carbs_g":1,"fat_g":1,"fiber_g":0}]}"#)
        XCTAssertThrowsError(try LogMealInput(json: json))
    }

    func testLogMealIsLenientOnNumericStringsAndMissingOptionals() throws {
        let json = try JSONValue.parse(#"{"meal_name":"Banana","meal_type":"SNACK","items":[{"name":"Banana","calories":"105","protein_g":1.3,"carbs_g":27,"fat_g":0.4}]}"#)
        let input = try LogMealInput(json: json)
        XCTAssertEqual(input.mealType, .snack)
        XCTAssertEqual(input.confidence, .medium) // missing → medium
        XCTAssertEqual(input.items[0].calories, 105)
        XCTAssertEqual(input.items[0].fiber, 0)
    }

    func testLowConfidenceIsParsed() throws {
        let json = try JSONValue.parse(#"{"meal_name":"Rice bowl","meal_type":"dinner","confidence":"low","items":[{"name":"Rice","quantity_description":"?","grams_estimate":200,"calories":260,"protein_g":5,"carbs_g":57,"fat_g":0.5,"fiber_g":0.6}]}"#)
        XCTAssertEqual(try LogMealInput(json: json).confidence, .low)
    }

    // MARK: Streaming

    private func accumulate(_ sse: String) throws -> (text: String, message: ClaudeMessage) {
        var parser = SSEParser()
        var accumulator = StreamAccumulator()
        var text = ""
        for line in sse.components(separatedBy: "\n") {
            if let event = parser.consume(line: line), let delta = try accumulator.process(eventData: event.data) {
                text += delta
            }
        }
        return (text, try accumulator.finalMessage())
    }

    func testStreamingTextAndToolUse() throws {
        let sse = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[]}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Estimating"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Got it, "}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"logging."}}

        event: content_block_start
        data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_9","name":"get_daily_summary","input":{}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":""}}

        event: ping
        data: {"type":"ping"}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":30}}

        event: message_stop
        data: {"type":"message_stop"}
        """
        let (text, message) = try accumulate(sse)
        XCTAssertEqual(text, "Got it, logging.")
        XCTAssertEqual(message.stopReason, "tool_use")
        XCTAssertEqual(message.content.count, 3)
        // Thinking block preserved with its signature so it can be replayed unchanged.
        XCTAssertEqual(message.content[0]["type"]?.stringValue, "thinking")
        XCTAssertEqual(message.content[0]["thinking"]?.stringValue, "Estimating")
        XCTAssertEqual(message.content[0]["signature"]?.stringValue, "abc")
        XCTAssertEqual(message.toolUses.first?.name, "get_daily_summary")
        XCTAssertEqual(message.toolUses.first?.input, .object([:]))
    }

    func testStreamingToolInputJSONIsAssembled() throws {
        let sse = """
        data: {"type":"message_start","message":{"id":"m"}}
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"log_meal","input":{}}}
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"meal_name\\": \\"Oats\\", \\"meal_type\\": \\"breakfast\\","}}
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":" \\"confidence\\": \\"high\\", \\"items\\": [{\\"name\\": \\"Oats\\", \\"quantity_description\\": \\"80 g\\", \\"grams_estimate\\": 80, \\"calories\\": 300, \\"protein_g\\": 11, \\"carbs_g\\": 51, \\"fat_g\\": 5, \\"fiber_g\\": 8}]}"}}
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}
        """
        let (_, message) = try accumulate(sse)
        let input = try LogMealInput(json: try XCTUnwrap(message.toolUses.first).input)
        XCTAssertEqual(input.mealName, "Oats")
        XCTAssertEqual(input.items.first?.fiber, 8)
    }

    func testStreamingErrorEventThrows() {
        var accumulator = StreamAccumulator()
        XCTAssertThrowsError(try accumulator.process(eventData: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)) { error in
            XCTAssertEqual(error as? ClaudeError, .overloaded)
        }
    }

    func testEmptyStreamIsInvalid() {
        XCTAssertThrowsError(try StreamAccumulator().finalMessage())
    }

    func testRefusalStopReason() throws {
        let (_, message) = try accumulate("""
        data: {"type":"message_start","message":{"id":"m"}}
        data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}
        """)
        XCTAssertTrue(message.isRefusal)
    }

    // MARK: Request & errors

    func testRequestBody() throws {
        let request = ClaudeRequest(system: "sys", messages: [["role": "user", "content": "hi"]], tools: CoachTools.definitions)
        let body = request.body
        XCTAssertEqual(body["model"]?.stringValue, "claude-sonnet-5-5")
        XCTAssertEqual(body["stream"]?.boolValue, true)
        XCTAssertEqual(body["thinking"]?["type"]?.stringValue, "adaptive")
        XCTAssertNil(body["temperature"]) // sampling params are rejected by the API
        XCTAssertNil(body["tool_choice"]) // forced tool use is rejected on this model
        let names = body["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue }
        XCTAssertEqual(names, ["log_meal", "get_daily_summary"])
        // log_meal schema parsed correctly from its JSON definition.
        let schema = body["tools"]?[0]?["input_schema"]
        XCTAssertEqual(schema?["required"]?.arrayValue?.count, 4)
        // Whole numbers serialize as integers.
        let serialized = String(decoding: body.serialized(sortedKeys: true), as: UTF8.self)
        XCTAssertTrue(serialized.contains("\"max_tokens\":8000"))
    }

    func testHTTPErrorMapping() {
        XCTAssertEqual(ClaudeError.from(status: 429, body: Data(), retryAfterHeader: "12"), .rateLimited(retryAfter: 12))
        XCTAssertEqual(ClaudeError.from(status: 401, body: Data(), retryAfterHeader: nil), .unauthorized)
        XCTAssertEqual(ClaudeError.from(status: 529, body: Data(), retryAfterHeader: nil), .overloaded)
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}"#.utf8)
        XCTAssertEqual(ClaudeError.from(status: 400, body: body, retryAfterHeader: nil), .server(status: 400, message: "bad"))
        XCTAssertEqual(ClaudeError.map(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(ClaudeError.map(URLError(.timedOut)), .timeout)
        XCTAssertFalse(ClaudeError.unauthorized.isRetryable)
        XCTAssertTrue(ClaudeError.offline.isRetryable)
    }

    func testSSEParserHandlesCRLFAndComments() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume(line: ": keep-alive"))
        XCTAssertNil(parser.consume(line: "event: ping\r"))
        XCTAssertEqual(parser.consume(line: "data: {\"type\":\"ping\"}\r"), SSEParser.Event(name: "ping", data: "{\"type\":\"ping\"}"))
    }

    func testContextBlockHasRealNumbers() {
        let targets = NutritionCalculator.Targets(calories: 3040, protein: 150, carbs: 457, fat: 68, fiber: 43, waterMl: 2650)
        let summary = DailyNutritionSummary(
            date: .now,
            eaten: MacroTotals(calories: 1840, protein: 112, carbs: 220, fat: 60, fiber: 20),
            targets: targets,
            waterMl: 1500,
            mealCount: 2
        )
        let text = CoachPrompt.makeContext(
            now: Date(timeIntervalSince1970: 1_792_670_400),
            timeZone: TimeZone(identifier: "Europe/Ljubljana") ?? .gmt,
            profile: NutritionCalculator.Input(gender: .male, age: 19, heightCm: 180, weightKg: 75, activity: .moderate, goal: .leanBulk),
            summary: summary,
            meals: [],
            today: .rest,
            trainedToday: false,
            upcoming: [(Date(timeIntervalSince1970: 1_792_756_800), .pull)]
        )
        XCTAssertTrue(text.contains("3040 kcal"))
        XCTAssertTrue(text.contains("Remaining today: 1200 kcal, protein 38 g"))
        XCTAssertTrue(text.contains("today Rest day"))
        XCTAssertTrue(text.contains("Pull"))
        XCTAssertTrue(text.contains("none logged yet"))
    }
}
