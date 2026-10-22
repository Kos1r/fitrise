import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import worker, { constantTimeEqual, sanitize } from "../src/index.js";

const env = { PROVIDER: "anthropic", ANTHROPIC_API_KEY: "sk-test", APP_TOKEN: "secret-token" };
const realFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = realFetch;
});

function post(body, headers = {}) {
  return new Request("https://proxy.example/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-app-token": "secret-token", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const validBody = {
  model: "claude-sonnet-5-5",
  max_tokens: 99999,
  messages: [{ role: "user", content: "hi" }],
  fallbacks: "default",
};

test("health check", async () => {
  const res = await worker.fetch(new Request("https://proxy.example/health"), env);
  assert.equal(res.status, 200);
});

test("rejects a wrong app token", async () => {
  const res = await worker.fetch(post(validBody, { "x-app-token": "nope" }), env);
  assert.equal(res.status, 401);
});

test("rejects a model that isn't allow-listed", async () => {
  const res = await worker.fetch(post({ ...validBody, model: "some-other-model" }), env);
  assert.equal(res.status, 400);
});

test("forwards with the secret key, clamps max_tokens and filters betas", async () => {
  let captured;
  globalThis.fetch = async (url, init) => {
    captured = { url, init };
    return new Response("event: message_stop\ndata: {}\n\n", { status: 200, headers: { "content-type": "text/event-stream" } });
  };
  const res = await worker.fetch(
    post(validBody, { "anthropic-version": "2026-10-21", "anthropic-beta": "server-side-fallback-2026-07-01, evil-beta" }),
    env,
  );
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "text/event-stream");
  assert.equal(captured.url, "https://api.anthropic.com/v1/messages");
  assert.equal(captured.init.headers["x-api-key"], "sk-test");
  assert.equal(captured.init.headers["anthropic-beta"], "server-side-fallback-2026-07-01");
  const forwarded = JSON.parse(captured.init.body);
  assert.equal(forwarded.max_tokens, 16000);
  assert.equal(forwarded.fallbacks, "default");
});

test("drops fallbacks when the beta header is missing", async () => {
  let forwarded;
  globalThis.fetch = async (_url, init) => {
    forwarded = JSON.parse(init.body);
    return new Response("{}", { status: 200 });
  };
  await worker.fetch(post(validBody), env);
  assert.equal(forwarded.fallbacks, undefined);
});

test("sanitize strips server tools", () => {
  const body = {
    ...validBody,
    tools: [{ name: "log_meal", input_schema: { type: "object" } }, { type: "web_search_20260209", name: "web_search" }],
  };
  assert.deepEqual(sanitize(body), {});
  assert.equal(body.tools.length, 1);
});

test("constantTimeEqual", () => {
  assert.equal(constantTimeEqual("abc", "abc"), true);
  assert.equal(constantTimeEqual("abc", "abd"), false);
  assert.equal(constantTimeEqual("", ""), false);
});
