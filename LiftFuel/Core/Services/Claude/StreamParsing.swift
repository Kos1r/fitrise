import Foundation

/// Minimal Server-Sent Events line parser. Anthropic sends one `data:` line per event,
/// so every data line is dispatched immediately (this also works with line readers
/// that drop blank separator lines).
struct SSEParser: Sendable {
    struct Event: Equatable, Sendable {
        var name: String?
        var data: String
    }

    private var currentName: String?

    mutating func consume(line rawLine: String) -> Event? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            currentName = nil
            return nil
        }
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            currentName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data:") {
            var data = String(line.dropFirst(5))
            if data.hasPrefix(" ") { data.removeFirst() }
            let event = Event(name: currentName, data: data)
            currentName = nil
            return event
        }
        return nil
    }
}

/// Rebuilds the assistant message from stream events, preserving every block
/// (including thinking blocks with their signatures) so it can be replayed unchanged.
struct StreamAccumulator: Sendable {
    private struct BlockBuilder: Sendable {
        var base: [String: JSONValue]
        var text = ""
        var thinking = ""
        var signature: String?
        var partialJSON = ""
    }

    private var blocks: [Int: BlockBuilder] = [:]
    private(set) var stopReason: String?
    private(set) var didStart = false

    /// Processes one event's JSON payload. Returns user-visible text to append, if any.
    mutating func process(eventData: String) throws -> String? {
        guard let json = try? JSONValue.parse(eventData), let type = json["type"]?.stringValue else {
            return nil
        }
        switch type {
        case "message_start":
            didStart = true
            return nil

        case "content_block_start":
            guard let index = json["index"]?.doubleValue.map(Int.init),
                  let block = json["content_block"]?.objectValue else { return nil }
            blocks[index] = BlockBuilder(base: block)
            return nil

        case "content_block_delta":
            guard let index = json["index"]?.doubleValue.map(Int.init),
                  let delta = json["delta"],
                  var builder = blocks[index] else { return nil }
            var visible: String?
            switch delta["type"]?.stringValue {
            case "text_delta":
                let text = delta["text"]?.stringValue ?? ""
                builder.text += text
                visible = text
            case "thinking_delta":
                builder.thinking += delta["thinking"]?.stringValue ?? ""
            case "signature_delta":
                builder.signature = delta["signature"]?.stringValue
            case "input_json_delta":
                builder.partialJSON += delta["partial_json"]?.stringValue ?? ""
            default:
                break
            }
            blocks[index] = builder
            return visible

        case "message_delta":
            if let reason = json["delta"]?["stop_reason"]?.stringValue {
                stopReason = reason
            }
            return nil

        case "error":
            let errorType = json["error"]?["type"]?.stringValue ?? ""
            let message = json["error"]?["message"]?.stringValue ?? ""
            switch errorType {
            case "overloaded_error": throw ClaudeError.overloaded
            case "rate_limit_error": throw ClaudeError.rateLimited(retryAfter: nil)
            default: throw ClaudeError.server(status: 500, message: message)
            }

        default:
            // ping, message_stop, content_block_stop and future event types.
            return nil
        }
    }

    func finalMessage() throws -> ClaudeMessage {
        guard didStart else { throw ClaudeError.invalidResponse }
        let content: [JSONValue] = blocks.keys.sorted().compactMap { index in
            guard let builder = blocks[index] else { return nil }
            var block = builder.base
            switch block["type"]?.stringValue {
            case "text":
                block["text"] = .string((block["text"]?.stringValue ?? "") + builder.text)
            case "thinking":
                block["thinking"] = .string((block["thinking"]?.stringValue ?? "") + builder.thinking)
                if let signature = builder.signature {
                    block["signature"] = .string(signature)
                }
            case "tool_use":
                if !builder.partialJSON.isEmpty {
                    block["input"] = (try? JSONValue.parse(builder.partialJSON)) ?? .object([:])
                } else if block["input"] == nil {
                    block["input"] = .object([:])
                }
            default:
                break
            }
            return .object(block)
        }
        return ClaudeMessage(content: content, stopReason: stopReason)
    }
}

/// Parses a non-streaming Messages API response body.
enum ClaudeResponseParser {
    static func parse(_ data: Data) throws -> ClaudeMessage {
        guard let json = try? JSONValue.parse(data), json["type"]?.stringValue == "message",
              let content = json["content"]?.arrayValue else {
            throw ClaudeError.invalidResponse
        }
        return ClaudeMessage(content: content, stopReason: json["stop_reason"]?.stringValue)
    }
}
