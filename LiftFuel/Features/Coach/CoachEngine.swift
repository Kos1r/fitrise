import Foundation
import Observation
import SwiftData

/// Drives a coach conversation: builds the request, streams the reply, runs the
/// tool-use loop (log_meal / get_daily_summary) and persists everything as ChatMessages.
@MainActor
@Observable
final class CoachEngine {
    private(set) var isResponding = false
    /// Assistant text currently streaming in (not yet persisted).
    private(set) var streamingText = ""
    private(set) var lastError: ClaudeError?

    @ObservationIgnored private let service: ClaudeServicing
    @ObservationIgnored private var currentTask: Task<Void, Never>?

    init(service: ClaudeServicing) {
        self.service = service
    }

    // MARK: Public API

    func send(text: String, imageData: Data?, in context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageData != nil, !isResponding else { return }
        let message = ChatMessage(role: .user, text: trimmed, imageData: imageData, status: .sending)
        context.insert(message)
        context.saveQuietly()
        respond(to: message, in: context)
    }

    func retry(_ message: ChatMessage, in context: ModelContext) {
        guard !isResponding else { return }
        message.status = .sending
        message.errorDescription = nil
        message.createdAt = .now
        context.saveQuietly()
        respond(to: message, in: context)
    }

    func cancel() {
        currentTask?.cancel()
    }

    /// Removes the meal behind a confirmation card (one-tap undo).
    func removeMeal(for card: ChatMessage, in context: ModelContext) {
        guard let id = card.mealID, let meal = context.meal(id: id) else {
            card.mealRemoved = true
            context.saveQuietly()
            return
        }
        NutritionService.delete(meal, in: context)
        card.mealRemoved = true
        context.saveQuietly()
    }

    // MARK: Conversation loop

    private func respond(to userMessage: ChatMessage, in context: ModelContext) {
        isResponding = true
        streamingText = ""
        lastError = nil
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.runTurn(for: userMessage, in: context)
            self.isResponding = false
            self.streamingText = ""
            self.currentTask = nil
        }
    }

    private func runTurn(for userMessage: ChatMessage, in context: ModelContext) async {
        // The system prompt is built once per turn and kept identical across the tool loop,
        // so replayed thinking blocks stay valid.
        let system = CoachPrompt.system(context: context)
        var messages = CoachHistory.apiMessages(upTo: userMessage, in: context)

        do {
            for _ in 0..<AppConfig.maxToolIterations {
                let request = ClaudeRequest(system: system, messages: messages, tools: CoachTools.definitions)
                var finalMessage: ClaudeMessage?
                for try await event in service.stream(request) {
                    switch event {
                    case .textDelta(let text):
                        streamingText += text
                    case .completed(let message):
                        finalMessage = message
                    }
                }
                guard let reply = finalMessage else { throw ClaudeError.invalidResponse }

                if reply.isRefusal {
                    streamingText = ""
                    persistAssistantText(String(localized: "I can't help with that one, but I'm happy to help with food logging, macros and meal ideas."), in: context)
                    break
                }

                flushStreamingText(fallback: reply.text, in: context)

                let toolUses = reply.toolUses
                guard reply.stopReason == "tool_use", !toolUses.isEmpty else { break }

                messages.append(["role": "assistant", "content": .array(reply.content)])
                let results = toolUses.map { execute($0, in: context) }
                messages.append(["role": "user", "content": .array(results)])
            }
            userMessage.status = .sent
            userMessage.errorDescription = nil
        } catch {
            let mapped = ClaudeError.map(error)
            streamingText = ""
            lastError = mapped
            if mapped == .cancelled {
                userMessage.status = .sent
            } else {
                userMessage.status = .failed
                userMessage.errorDescription = mapped.errorDescription
            }
        }
        context.saveQuietly()
        WidgetSyncService.update(context: context)
    }

    private func flushStreamingText(fallback: String, in context: ModelContext) {
        let text = streamingText.isEmpty ? fallback : streamingText
        streamingText = ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        persistAssistantText(trimmed, in: context)
    }

    private func persistAssistantText(_ text: String, in context: ModelContext) {
        context.insert(ChatMessage(role: .assistant, text: text))
        context.saveQuietly()
    }

    // MARK: Tools

    private func execute(_ toolUse: ToolUse, in context: ModelContext) -> JSONValue {
        switch toolUse.name {
        case CoachTools.logMeal:
            return executeLogMeal(toolUse, in: context)
        case CoachTools.dailySummary:
            let summary = NutritionService.summary(on: .now, in: context)
            return ToolResult.success(id: toolUse.id, payload: ToolResult.summary(summary, meals: context.meals(on: .now)))
        default:
            return ToolResult.error(id: toolUse.id, message: "Unknown tool \(toolUse.name)")
        }
    }

    private func executeLogMeal(_ toolUse: ToolUse, in context: ModelContext) -> JSONValue {
        let input: LogMealInput
        do {
            input = try LogMealInput(json: toolUse.input)
        } catch {
            return ToolResult.error(id: toolUse.id, message: "Not logged — invalid input: \(error.localizedDescription). Fix the input and call log_meal again.")
        }
        guard input.confidence != .low else {
            return ToolResult.error(
                id: toolUse.id,
                message: "Not logged: confidence is low. Ask the user one short clarifying question (portion size or what the food is), then log it."
            )
        }

        let meal = NutritionService.logMeal(
            name: input.mealName,
            mealType: input.mealType,
            items: input.snapshots,
            confidence: input.confidence,
            source: .ai,
            in: context
        )
        let card = ChatMessage(role: .assistant, kind: .mealCard, text: input.mealName)
        card.mealID = meal.id
        context.insert(card)
        context.saveQuietly()

        let summary = NutritionService.summary(on: .now, in: context)
        let payload: JSONValue = [
            "status": "logged",
            "meal_totals": ToolResult.macros(input.totals),
            "today_eaten": ToolResult.macros(summary.eaten),
            "today_remaining": ToolResult.macros(summary.remaining)
        ]
        return ToolResult.success(id: toolUse.id, payload: payload)
    }
}

/// Converts stored chat messages into Messages API history.
/// Prior turns are sent as plain text (no thinking blocks), which keeps history append-only
/// from the API's point of view; only the newest user message carries its photo.
@MainActor
enum CoachHistory {
    static func apiMessages(upTo current: ChatMessage, in context: ModelContext) -> [JSONValue] {
        let currentID = current.id
        let currentDate = current.createdAt
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.createdAt <= currentDate && $0.id != currentID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = AppConfig.historyMessageLimit
        let previous = ((try? context.fetch(descriptor)) ?? []).reversed()

        var turns: [(role: ChatRole, blocks: [JSONValue])] = []
        for message in previous where message.status == .sent {
            guard let text = historyText(for: message, in: context), !text.isEmpty else { continue }
            turns.append((message.role, [["type": "text", "text": .string(text)]]))
        }
        turns.append((.user, currentBlocks(for: current)))
        return merge(turns)
    }

    static func historyText(for message: ChatMessage, in context: ModelContext) -> String? {
        switch message.kind {
        case .text:
            if message.imageData != nil {
                return message.text.isEmpty ? "[sent a meal photo]" : "[sent a meal photo] \(message.text)"
            }
            return message.text
        case .mealCard:
            if message.mealRemoved {
                return "(The user removed the logged meal \"\(message.text)\" from the diary.)"
            }
            guard let id = message.mealID, let meal = context.meal(id: id) else { return nil }
            let totals = meal.totals
            return "(Logged \"\(meal.name)\": \(Int(totals.calories)) kcal, \(Int(totals.protein)) g protein.)"
        }
    }

    static func currentBlocks(for message: ChatMessage) -> [JSONValue] {
        var blocks: [JSONValue] = []
        if let data = message.imageData {
            blocks.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": .string(data.base64EncodedString())]
            ])
        }
        let text = message.text.isEmpty ? "Here's a photo of my meal." : message.text
        blocks.append(["type": "text", "text": .string(text)])
        return blocks
    }

    /// Merges consecutive same-role turns and guarantees the history starts with a user turn.
    static func merge(_ turns: [(role: ChatRole, blocks: [JSONValue])]) -> [JSONValue] {
        var merged: [(role: ChatRole, blocks: [JSONValue])] = []
        for turn in turns {
            if let last = merged.last, last.role == turn.role {
                merged[merged.count - 1].blocks.append(contentsOf: turn.blocks)
            } else {
                merged.append(turn)
            }
        }
        while let first = merged.first, first.role != .user {
            merged.removeFirst()
        }
        return merged.map { ["role": .string($0.role.rawValue), "content": .array($0.blocks)] }
    }
}
