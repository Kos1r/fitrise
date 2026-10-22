// Translation between the Claude Messages API format (what the app speaks) and the
// Google Gemini generateContent API. Pure functions — unit-tested in test/gemini.test.js.
//
// Thought signatures: Gemini 3 models attach a `thoughtSignature` to function-call parts
// and require it back on the next request of the same turn. We carry it inside the
// Claude-format tool_use block as `gemini_signature`; the app replays tool_use blocks
// unchanged, so the signature round-trips without the app knowing about Gemini.

export const DEFAULT_GEMINI_MODEL = "gemini-3.8-flash";

/** Claude Messages request body → Gemini generateContent request body. */
export function toGeminiRequest(body) {
  const toolNamesById = new Map();
  const contents = [];

  for (const message of body.messages || []) {
    const role = message.role === "assistant" ? "model" : "user";
    const blocks = typeof message.content === "string" ? [{ type: "text", text: message.content }] : message.content || [];
    const parts = [];
    for (const block of blocks) {
      const part = toGeminiPart(block, toolNamesById);
      if (part) parts.push(part);
    }
    if (!parts.length) continue;
    const last = contents[contents.length - 1];
    if (last && last.role === role) {
      last.parts.push(...parts);
    } else {
      contents.push({ role, parts });
    }
  }

  const request = {
    contents,
    generationConfig: {
      maxOutputTokens: Math.min(Number(body.max_tokens) || 8000, 16000),
      thinkingConfig: { thinkingLevel: "low" },
    },
  };

  const system = systemText(body.system);
  if (system) request.systemInstruction = { parts: [{ text: system }] };

  const declarations = (body.tools || [])
    .filter((tool) => tool && typeof tool.name === "string" && tool.input_schema)
    .map(toFunctionDeclaration);
  if (declarations.length) {
    request.tools = [{ functionDeclarations: declarations }];
    request.toolConfig = { functionCallingConfig: { mode: "AUTO" } };
  }
  return request;
}

function systemText(system) {
  if (!system) return "";
  if (typeof system === "string") return system;
  if (Array.isArray(system)) return system.map((b) => (b && b.text) || "").join("\n\n");
  return "";
}

function toGeminiPart(block, toolNamesById) {
  if (!block || typeof block !== "object") return null;
  switch (block.type) {
    case "text":
      return block.text ? { text: block.text } : null;
    case "image":
      if (block.source && block.source.type === "base64") {
        return { inlineData: { mimeType: block.source.media_type || "image/jpeg", data: block.source.data } };
      }
      return null;
    case "tool_use": {
      toolNamesById.set(block.id, { name: block.name, callId: block.gemini_call_id });
      const functionCall = { name: block.name, args: block.input || {} };
      if (block.gemini_call_id) functionCall.id = block.gemini_call_id;
      const part = { functionCall };
      if (block.gemini_signature) part.thoughtSignature = block.gemini_signature;
      return part;
    }
    case "tool_result": {
      const call = toolNamesById.get(block.tool_use_id) || { name: "unknown_tool" };
      const text = resultText(block.content);
      let payload;
      try {
        payload = JSON.parse(text);
      } catch {
        payload = text;
      }
      const response = block.is_error ? { error: payload } : { result: payload };
      const functionResponse = { name: call.name, response };
      if (call.callId) functionResponse.id = call.callId;
      return { functionResponse };
    }
    default:
      // thinking, fallback and other Claude-only blocks have no Gemini equivalent.
      return null;
  }
}

function resultText(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) return content.map((c) => (c && c.text) || "").join("");
  return "";
}

/** Gemini's `parameters` accepts an OpenAPI subset: drop JSON-Schema-only keywords. */
export function toFunctionDeclaration(tool) {
  const declaration = { name: tool.name, description: tool.description || "" };
  const schema = cleanSchema(tool.input_schema);
  if (schema && schema.properties && Object.keys(schema.properties).length) {
    declaration.parameters = schema;
  }
  return declaration;
}

function cleanSchema(schema) {
  if (Array.isArray(schema)) return schema.map(cleanSchema);
  if (!schema || typeof schema !== "object") return schema;
  const out = {};
  for (const [key, value] of Object.entries(schema)) {
    if (key === "additionalProperties" || key === "$schema" || key === "strict") continue;
    out[key] = key === "properties" ? mapValues(value, cleanSchema) : cleanSchema(value);
  }
  return out;
}

function mapValues(object, fn) {
  const out = {};
  for (const [key, value] of Object.entries(object || {})) out[key] = fn(value);
  return out;
}

const REFUSAL_REASONS = new Set(["SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "IMAGE_SAFETY"]);

/**
 * Converts streamed Gemini responses into Claude Messages stream events.
 * Feed each parsed Gemini chunk to `push`, then call `finish`.
 */
export class GeminiStreamTranslator {
  constructor(model) {
    this.model = model;
    this.index = -1;
    this.openType = null;
    this.sawToolUse = false;
    this.started = false;
    this.finishReason = null;
    this.blocked = false;
    this.outputTokens = 0;
    this.callCounter = 0;
  }

  start() {
    this.started = true;
    return [{
      type: "message_start",
      message: { id: `msg_gemini_${Date.now()}`, type: "message", role: "assistant", model: this.model, content: [], stop_reason: null, usage: { input_tokens: 0, output_tokens: 0 } },
    }];
  }

  push(chunk) {
    const events = this.started ? [] : this.start();
    if (chunk && chunk.promptFeedback && chunk.promptFeedback.blockReason) {
      this.blocked = true;
    }
    if (chunk && chunk.usageMetadata && chunk.usageMetadata.candidatesTokenCount) {
      this.outputTokens = chunk.usageMetadata.candidatesTokenCount;
    }
    const candidate = chunk && chunk.candidates && chunk.candidates[0];
    if (!candidate) return events;
    for (const part of (candidate.content && candidate.content.parts) || []) {
      if (part.thought) continue; // thought summaries are not shown
      if (part.functionCall) {
        events.push(...this.close());
        this.index += 1;
        this.sawToolUse = true;
        this.callCounter += 1;
        const block = {
          type: "tool_use",
          id: `toolu_gemini_${Date.now().toString(36)}_${this.callCounter}`,
          name: part.functionCall.name,
          input: {},
        };
        if (part.thoughtSignature) block.gemini_signature = part.thoughtSignature;
        if (part.functionCall.id) block.gemini_call_id = part.functionCall.id;
        events.push({ type: "content_block_start", index: this.index, content_block: block });
        events.push({
          type: "content_block_delta",
          index: this.index,
          delta: { type: "input_json_delta", partial_json: JSON.stringify(part.functionCall.args || {}) },
        });
        events.push({ type: "content_block_stop", index: this.index });
      } else if (typeof part.text === "string" && part.text.length) {
        if (this.openType !== "text") {
          events.push(...this.close());
          this.index += 1;
          this.openType = "text";
          events.push({ type: "content_block_start", index: this.index, content_block: { type: "text", text: "" } });
        }
        events.push({ type: "content_block_delta", index: this.index, delta: { type: "text_delta", text: part.text } });
      }
    }
    if (candidate.finishReason) this.finishReason = candidate.finishReason;
    return events;
  }

  close() {
    if (this.openType === null) return [];
    const event = { type: "content_block_stop", index: this.index };
    this.openType = null;
    return [event];
  }

  stopReason() {
    if (this.blocked || REFUSAL_REASONS.has(this.finishReason)) return "refusal";
    if (this.finishReason === "MAX_TOKENS") return "max_tokens";
    if (this.sawToolUse) return "tool_use";
    return "end_turn";
  }

  finish() {
    const events = this.started ? [] : this.start();
    events.push(...this.close());
    events.push({ type: "message_delta", delta: { stop_reason: this.stopReason(), stop_sequence: null }, usage: { output_tokens: this.outputTokens } });
    events.push({ type: "message_stop" });
    return events;
  }
}

/** Formats Claude stream events as Server-Sent Events text. */
export function sse(events) {
  return events.map((e) => `event: ${e.type}\ndata: ${JSON.stringify(e)}\n\n`).join("");
}

/** Builds a non-streaming Claude message from the translated events. */
export function eventsToMessage(events) {
  const content = [];
  let stopReason = "end_turn";
  let model = DEFAULT_GEMINI_MODEL;
  const partial = new Map();
  for (const e of events) {
    if (e.type === "message_start") model = e.message.model;
    if (e.type === "content_block_start") content[e.index] = { ...e.content_block };
    if (e.type === "content_block_delta") {
      const block = content[e.index];
      if (e.delta.type === "text_delta") block.text = (block.text || "") + e.delta.text;
      if (e.delta.type === "input_json_delta") partial.set(e.index, (partial.get(e.index) || "") + e.delta.partial_json);
    }
    if (e.type === "message_delta") stopReason = e.delta.stop_reason;
  }
  for (const [index, json] of partial) {
    try {
      content[index].input = JSON.parse(json);
    } catch {
      content[index].input = {};
    }
  }
  return { id: `msg_gemini_${Date.now()}`, type: "message", role: "assistant", model, content: content.filter(Boolean), stop_reason: stopReason, usage: { input_tokens: 0, output_tokens: 0 } };
}

/** Maps a Gemini HTTP error to a Claude-style error body + status. */
export function mapGeminiError(status, bodyText) {
  let message = "";
  try {
    message = JSON.parse(bodyText).error.message || "";
  } catch {
    message = bodyText.slice(0, 300);
  }
  const type = status === 429 ? "rate_limit_error" : status === 401 || status === 403 ? "authentication_error" : status === 400 ? "invalid_request_error" : "api_error";
  // A bad Gemini key is a server misconfiguration, not the app's token being wrong.
  const mappedStatus = status === 401 || status === 403 ? 502 : status === 503 ? 529 : status;
  return { status: mappedStatus, body: { type: "error", error: { type, message: `Gemini: ${message}` } } };
}
