import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import worker from "../src/index.js";
import { GeminiStreamTranslator, eventsToMessage, mapGeminiError, toFunctionDeclaration, toGeminiRequest } from "../src/gemini.js";

const env = { GEMINI_API_KEY: "gem-test", APP_TOKEN: "secret-token" }; // PROVIDER defaults to gemini
const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

const logMealTool = {
  name: "log_meal",
  description: "Log a meal",
  strict: true,
  input_schema: {
    type: "object",
    properties: {
      meal_name: { type: "string" },
      items: {
        type: "array",
        items: { type: "object", properties: { name: { type: "string" } }, required: ["name"], additionalProperties: false },
      },
    },
    required: ["meal_name", "items"],
    additionalProperties: false,
  },
};
const summaryTool = { name: "get_daily_summary", description: "Totals", input_schema: { type: "object", properties: {}, additionalProperties: false } };

test("request: system, roles, image and tools are translated", () => {
  const request = toGeminiRequest({
    model: "claude-sonnet-5-5",
    max_tokens: 8000,
    system: "You are the coach.",
    tools: [logMealTool, summaryTool],
    messages: [
      { role: "user", content: [{ type: "text", text: "earlier" }] },
      { role: "assistant", content: [{ type: "thinking", thinking: "", signature: "x" }, { type: "text", text: "ok" }] },
      { role: "user", content: [
        { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "QUJD" } },
        { type: "text", text: "my lunch" },
      ] },
    ],
  });
  assert.deepEqual(request.systemInstruction, { parts: [{ text: "You are the coach." }] });
  assert.deepEqual(request.contents.map((c) => c.role), ["user", "model", "user"]);
  assert.deepEqual(request.contents[1].parts, [{ text: "ok" }]); // thinking block dropped
  assert.deepEqual(request.contents[2].parts[0], { inlineData: { mimeType: "image/jpeg", data: "QUJD" } });
  assert.equal(request.generationConfig.thinkingConfig.thinkingLevel, "low");
  const [logMeal, summary] = request.tools[0].functionDeclarations;
  assert.equal(JSON.stringify(logMeal).includes("additionalProperties"), false);
  assert.deepEqual(logMeal.parameters.required, ["meal_name", "items"]);
  assert.equal(summary.parameters, undefined); // empty object schemas are omitted
});

test("request: tool_use with signature and tool_result round-trip", () => {
  const request = toGeminiRequest({
    max_tokens: 100,
    messages: [
      { role: "user", content: "2 eggs" },
      { role: "assistant", content: [{ type: "tool_use", id: "toolu_1", name: "log_meal", input: { meal_name: "Eggs" }, gemini_signature: "SIG", gemini_call_id: "call-9" }] },
      { role: "user", content: [{ type: "tool_result", tool_use_id: "toolu_1", content: "{\"status\":\"logged\"}" }] },
    ],
  });
  assert.deepEqual(request.contents[1].parts[0], { functionCall: { name: "log_meal", args: { meal_name: "Eggs" }, id: "call-9" }, thoughtSignature: "SIG" });
  assert.deepEqual(request.contents[2].parts[0], { functionResponse: { name: "log_meal", response: { result: { status: "logged" } }, id: "call-9" } });
});

test("request: error tool results are wrapped as error", () => {
  const request = toGeminiRequest({
    messages: [
      { role: "user", content: "hi" },
      { role: "assistant", content: [{ type: "tool_use", id: "t", name: "log_meal", input: {} }] },
      { role: "user", content: [{ type: "tool_result", tool_use_id: "t", content: "Not logged: confidence is low", is_error: true }] },
    ],
  });
  assert.deepEqual(request.contents[2].parts[0].functionResponse.response, { error: "Not logged: confidence is low" });
});

test("stream: text is streamed as Claude text deltas", () => {
  const t = new GeminiStreamTranslator("gemini-3.8-flash");
  const events = [
    ...t.push({ candidates: [{ content: { parts: [{ text: "Hello " }] } }] }),
    ...t.push({ candidates: [{ content: { parts: [{ text: "there" }] }, finishReason: "STOP" }] }),
    ...t.finish(),
  ];
  assert.deepEqual(events.map((e) => e.type), ["message_start", "content_block_start", "content_block_delta", "content_block_delta", "content_block_stop", "message_delta", "message_stop"]);
  const message = eventsToMessage(events);
  assert.equal(message.content[0].text, "Hello there");
  assert.equal(message.stop_reason, "end_turn");
});

test("stream: function calls become tool_use with the signature attached", () => {
  const t = new GeminiStreamTranslator("gemini-3.8-flash");
  const events = [
    ...t.push({ candidates: [{ content: { parts: [{ thought: true, text: "thinking..." }, { text: "Logging." }] } }] }),
    ...t.push({ candidates: [{ content: { parts: [{ functionCall: { name: "log_meal", args: { meal_name: "Oats" } }, thoughtSignature: "SIG1" }] }, finishReason: "STOP" }] }),
    ...t.finish(),
  ];
  const message = eventsToMessage(events);
  assert.equal(message.stop_reason, "tool_use");
  assert.equal(message.content.length, 2);
  assert.equal(message.content[0].text, "Logging.");
  const tool = message.content[1];
  assert.equal(tool.type, "tool_use");
  assert.equal(tool.name, "log_meal");
  assert.deepEqual(tool.input, { meal_name: "Oats" });
  assert.equal(tool.gemini_signature, "SIG1");
  assert.match(tool.id, /^toolu_gemini_/);
});

test("stream: safety blocks map to refusal, MAX_TOKENS to max_tokens", () => {
  const blocked = new GeminiStreamTranslator("m");
  blocked.push({ promptFeedback: { blockReason: "SAFETY" } });
  assert.equal(blocked.finish().find((e) => e.type === "message_delta").delta.stop_reason, "refusal");
  const long = new GeminiStreamTranslator("m");
  long.push({ candidates: [{ content: { parts: [{ text: "a" }] }, finishReason: "MAX_TOKENS" }] });
  assert.equal(long.finish().find((e) => e.type === "message_delta").delta.stop_reason, "max_tokens");
});

test("errors: quota and bad key are mapped", () => {
  assert.equal(mapGeminiError(429, '{"error":{"message":"Quota exceeded"}}').status, 429);
  const badKey = mapGeminiError(403, '{"error":{"message":"API key not valid"}}');
  assert.equal(badKey.status, 502); // not the app's fault — don't show "check your app token"
  assert.match(badKey.body.error.message, /API key not valid/);
});

test("function declarations drop JSON-Schema-only keys", () => {
  assert.equal(JSON.stringify(toFunctionDeclaration(logMealTool)).includes("strict"), false);
});

test("worker: end-to-end streaming through the Gemini path", async () => {
  let captured;
  globalThis.fetch = async (url, init) => {
    captured = { url, init };
    const body =
      'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Got it"}]}}]}\r\n\r\n' +
      'data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"get_daily_summary","args":{}},"thoughtSignature":"S"}]},"finishReason":"STOP"}]}\r\n\r\n';
    return new Response(body, { status: 200, headers: { "content-type": "text/event-stream" } });
  };
  const res = await worker.fetch(
    new Request("https://proxy.example/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-app-token": "secret-token" },
      body: JSON.stringify({ model: "claude-sonnet-5-5", max_tokens: 8000, stream: true, system: "s", tools: [summaryTool], messages: [{ role: "user", content: "what's left?" }] }),
    }),
    env,
  );
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "text/event-stream");
  assert.match(captured.url, /models\/gemini-3\.8-flash:streamGenerateContent\?alt=sse$/);
  assert.equal(captured.init.headers["x-goog-api-key"], "gem-test");
  const text = await res.text();
  assert.match(text, /event: message_start/);
  assert.match(text, /"text_delta","text":"Got it"/);
  assert.match(text, /"type":"tool_use".*"name":"get_daily_summary".*"gemini_signature":"S"/);
  assert.match(text, /"stop_reason":"tool_use"/);
  assert.match(text, /event: message_stop/);
});

test("worker: Gemini quota error is returned as a 429 with retry-after", async () => {
  globalThis.fetch = async () => new Response('{"error":{"code":429,"message":"Resource exhausted"}}', { status: 429 });
  const res = await worker.fetch(
    new Request("https://proxy.example/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-app-token": "secret-token" },
      body: JSON.stringify({ model: "claude-sonnet-5-5", max_tokens: 100, stream: true, messages: [{ role: "user", content: "hi" }] }),
    }),
    env,
  );
  assert.equal(res.status, 429);
  assert.equal(res.headers.get("retry-after"), "30");
});

test("worker: missing GEMINI_API_KEY is reported", async () => {
  const res = await worker.fetch(
    new Request("https://proxy.example/v1/messages", { method: "POST", headers: { "x-app-token": "secret-token" }, body: "{}" }),
    { APP_TOKEN: "secret-token" },
  );
  assert.equal(res.status, 500);
  assert.match((await res.json()).error.message, /GEMINI_API_KEY/);
});
