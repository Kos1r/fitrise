import Foundation

/// A Messages API request. Built as JSON so the exact wire format is visible and testable.
struct ClaudeRequest: Sendable {
    var model: String = AppConfig.claudeModel
    var maxTokens: Int = AppConfig.maxTokens
    var system: String
    var messages: [JSONValue]
    var tools: [JSONValue]
    var stream: Bool = true
    var effort: String = AppConfig.effort

    var body: JSONValue {
        var object: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .number(Double(maxTokens)),
            "system": .string(system),
            "messages": .array(messages),
            "stream": .bool(stream),
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": .string(effort)],
            "fallbacks": "default"
        ]
        if !tools.isEmpty {
            object["tools"] = .array(tools)
        }
        return .object(object)
    }
}

/// A finished assistant turn. `content` holds every block exactly as received,
/// so it can be sent back unchanged inside a tool-use loop.
struct ClaudeMessage: Equatable, Sendable {
    var content: [JSONValue]
    var stopReason: String?

    var text: String {
        content
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined()
    }

    var toolUses: [ToolUse] {
        content.compactMap { block in
            guard block["type"]?.stringValue == "tool_use",
                  let id = block["id"]?.stringValue,
                  let name = block["name"]?.stringValue else { return nil }
            return ToolUse(id: id, name: name, input: block["input"] ?? .object([:]))
        }
    }

    var isRefusal: Bool { stopReason == "refusal" }
}

struct ToolUse: Equatable, Sendable {
    var id: String
    var name: String
    var input: JSONValue
}

enum ClaudeStreamEvent: Sendable {
    case textDelta(String)
    case completed(ClaudeMessage)
}

enum ClaudeError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case offline
    case timeout
    case rateLimited(retryAfter: Int?)
    case unauthorized
    case overloaded
    case server(status: Int, message: String)
    case invalidResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "The coach isn't connected yet. Add your proxy URL and app token in Settings › Coach connection.")
        case .offline:
            String(localized: "You're offline. Your message is saved — tap Retry when you're back online.")
        case .timeout:
            String(localized: "The coach took too long to answer. Tap Retry.")
        case .rateLimited(let retryAfter):
            if let retryAfter {
                String(localized: "Too many messages at once. Try again in \(retryAfter) s.")
            } else {
                String(localized: "Too many messages at once. Try again in a moment.")
            }
        case .unauthorized:
            String(localized: "The coach server rejected the app token. Check Settings › Coach connection.")
        case .overloaded:
            String(localized: "The coach is very busy right now. Tap Retry in a few seconds.")
        case .server(let status, let message):
            message.isEmpty
                ? String(localized: "The coach server returned an error (\(status)).")
                : String(localized: "Coach error (\(status)): \(message)")
        case .invalidResponse:
            String(localized: "The coach sent a response the app couldn't read. Tap Retry.")
        case .cancelled:
            String(localized: "Cancelled.")
        }
    }

    var isRetryable: Bool {
        switch self {
        case .notConfigured, .unauthorized, .cancelled: false
        default: true
        }
    }

    /// Maps an HTTP error response to a typed error.
    static func from(status: Int, body: Data, retryAfterHeader: String?) -> ClaudeError {
        let message = (try? JSONValue.parse(body))?["error"]?["message"]?.stringValue ?? ""
        switch status {
        case 401, 403: return .unauthorized
        case 408, 504: return .timeout
        case 429: return .rateLimited(retryAfter: retryAfterHeader.flatMap { Int($0) })
        case 503, 529: return .overloaded
        default: return .server(status: status, message: message)
        }
    }

    static func map(_ error: Error) -> ClaudeError {
        if let error = error as? ClaudeError { return error }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .offline
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            default:
                return .server(status: urlError.errorCode, message: urlError.localizedDescription)
            }
        }
        return .invalidResponse
    }
}
