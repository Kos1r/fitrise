// Lift & Fuel — Claude API proxy (Cloudflare Worker).
//
// The iOS app never holds the Anthropic API key. It calls this Worker with a shared
// app token; the Worker checks the token, rate-limits, validates the request and
// forwards it to the Messages API with the key stored as a Worker secret.
//
// Provider: PROVIDER = "gemini" (default, free tier) or "anthropic" (wrangler.toml [vars]).
// The app always speaks the Claude Messages format; for Gemini the Worker translates
// requests and streamed responses (see gemini.js).
//
// Secrets (set with `wrangler secret put`):
//   GEMINI_API_KEY     — Google AI Studio key (when PROVIDER = "gemini")
//   ANTHROPIC_API_KEY  — Anthropic API key (when PROVIDER = "anthropic")
//   APP_TOKEN          — long random string; also entered in the app (Settings › Coach connection)

import { DEFAULT_GEMINI_MODEL, GeminiStreamTranslator, eventsToMessage, mapGeminiError, sse, toGeminiRequest } from "./gemini.js";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const DEFAULT_VERSION = "2026-10-21";
const ALLOWED_MODELS = new Set(["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5"]);
const ALLOWED_BETAS = new Set(["server-side-fallback-2026-07-01"]);
const MAX_BODY_BYTES = 6 * 1024 * 1024; // photos are downscaled to ~1024 px in the app
const MAX_TOKENS_CAP = 16000;
const FALLBACK_LIMIT = { requests: 30, windowMs: 60_000 };

// Per-isolate fallback limiter, used only when no Rate Limiting binding is configured.
const memoryBuckets = new Map();

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }
    if (url.pathname !== "/v1/messages") {
      return error(404, "not_found", "Unknown path");
    }
    if (request.method !== "POST") {
      return error(405, "method_not_allowed", "Use POST");
    }
    const provider = (env.PROVIDER || "gemini").toLowerCase();
    const providerKey = provider === "anthropic" ? env.ANTHROPIC_API_KEY : env.GEMINI_API_KEY;
    if (!providerKey || !env.APP_TOKEN) {
      return error(500, "misconfigured", `Proxy secrets are not set (${provider === "anthropic" ? "ANTHROPIC_API_KEY" : "GEMINI_API_KEY"} and APP_TOKEN)`);
    }

    const token = request.headers.get("x-app-token") || "";
    if (!constantTimeEqual(token, env.APP_TOKEN)) {
      return error(401, "authentication_error", "Invalid app token");
    }

    const clientKey = `${await sha256(token)}:${request.headers.get("cf-connecting-ip") || "unknown"}`;
    const limited = await isRateLimited(env, clientKey);
    if (limited) {
      return error(429, "rate_limit_error", "Too many requests, slow down", { "retry-after": "30" });
    }

    const declaredLength = Number(request.headers.get("content-length") || 0);
    if (declaredLength > MAX_BODY_BYTES) {
      return error(413, "request_too_large", "Request body too large");
    }
    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) {
      return error(413, "request_too_large", "Request body too large");
    }

    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return error(400, "invalid_request_error", "Body must be JSON");
    }

    const validation = sanitize(body);
    if (validation.error) {
      return error(400, "invalid_request_error", validation.error);
    }

    if (provider !== "anthropic") {
      return forwardToGemini(body, env);
    }

    const betas = (request.headers.get("anthropic-beta") || "")
      .split(",")
      .map((b) => b.trim())
      .filter((b) => ALLOWED_BETAS.has(b));
    if (!betas.length && body.fallbacks !== undefined) {
      delete body.fallbacks; // never forward a beta field without its header
    }

    const headers = {
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": request.headers.get("anthropic-version") || DEFAULT_VERSION,
    };
    if (betas.length) headers["anthropic-beta"] = betas.join(",");

    let upstream;
    try {
      upstream = await fetch(ANTHROPIC_URL, { method: "POST", headers, body: JSON.stringify(body) });
    } catch {
      return error(502, "upstream_unreachable", "Could not reach the Claude API");
    }

    // Stream the response straight through (SSE when stream: true).
    const responseHeaders = new Headers();
    for (const name of ["content-type", "retry-after", "request-id", "anthropic-ratelimit-requests-remaining"]) {
      const value = upstream.headers.get(name);
      if (value) responseHeaders.set(name, value);
    }
    responseHeaders.set("cache-control", "no-store");
    return new Response(upstream.body, { status: upstream.status, headers: responseHeaders });
  },
};

async function forwardToGemini(body, env) {
  const model = env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse`;
  let upstream;
  try {
    upstream = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
      body: JSON.stringify(toGeminiRequest(body)),
    });
  } catch {
    return error(502, "upstream_unreachable", "Could not reach the Gemini API");
  }
  if (!upstream.ok) {
    const mapped = mapGeminiError(upstream.status, await upstream.text());
    return json(mapped.body, mapped.status, mapped.status === 429 ? { "retry-after": "30" } : {});
  }

  const translator = new GeminiStreamTranslator(model);
  if (!body.stream) {
    const events = [];
    for await (const chunk of geminiChunks(upstream.body)) events.push(...translator.push(chunk));
    events.push(...translator.finish());
    return json(eventsToMessage(events));
  }

  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();
  (async () => {
    try {
      for await (const chunk of geminiChunks(upstream.body)) {
        const events = translator.push(chunk);
        if (events.length) await writer.write(encoder.encode(sse(events)));
      }
      await writer.write(encoder.encode(sse(translator.finish())));
    } catch {
      await writer.write(encoder.encode(sse([{ type: "error", error: { type: "api_error", message: "Gemini stream interrupted" } }])));
    } finally {
      await writer.close();
    }
  })();
  return new Response(readable, { status: 200, headers: { "content-type": "text/event-stream", "cache-control": "no-store" } });
}

/** Parses Gemini's SSE stream (`data: {...}` lines) into JSON chunks. */
export async function* geminiChunks(stream) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { value, done } = await reader.read();
    if (value) buffer += decoder.decode(value, { stream: true });
    let newline;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline).replace(/\r$/, "");
      buffer = buffer.slice(newline + 1);
      if (line.startsWith("data:")) {
        const data = line.slice(5).trim();
        if (data && data !== "[DONE]") {
          try {
            yield JSON.parse(data);
          } catch {
            // ignore malformed keep-alive lines
          }
        }
      }
    }
    if (done) break;
  }
  const rest = buffer.trim();
  if (rest.startsWith("data:")) {
    try {
      yield JSON.parse(rest.slice(5).trim());
    } catch {
      // ignore
    }
  }
}

/** Validates and clamps the request. Mutates `body`. */
export function sanitize(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return { error: "Body must be an object" };
  if (!ALLOWED_MODELS.has(body.model)) return { error: `Model not allowed: ${body.model}` };
  if (!Array.isArray(body.messages) || body.messages.length === 0) return { error: "messages must be a non-empty array" };
  if (body.messages.length > 60) return { error: "Too many messages" };
  const maxTokens = Number(body.max_tokens);
  if (!Number.isFinite(maxTokens) || maxTokens <= 0) return { error: "max_tokens must be a positive number" };
  body.max_tokens = Math.min(Math.floor(maxTokens), MAX_TOKENS_CAP);
  // The app never uses server tools; strip anything unexpected.
  if (Array.isArray(body.tools)) {
    body.tools = body.tools.filter((tool) => tool && typeof tool.name === "string" && tool.input_schema && !tool.type);
  }
  delete body.mcp_servers;
  delete body.container;
  return {};
}

export function constantTimeEqual(a, b) {
  const encoder = new TextEncoder();
  const x = encoder.encode(String(a));
  const y = encoder.encode(String(b));
  let diff = x.length ^ y.length;
  const length = Math.max(x.length, y.length);
  for (let i = 0; i < length; i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0 && x.length > 0;
}

async function isRateLimited(env, key) {
  if (env.RATE_LIMITER && typeof env.RATE_LIMITER.limit === "function") {
    const { success } = await env.RATE_LIMITER.limit({ key });
    return !success;
  }
  const now = Date.now();
  const bucket = memoryBuckets.get(key);
  if (!bucket || now - bucket.start > FALLBACK_LIMIT.windowMs) {
    memoryBuckets.set(key, { start: now, count: 1 });
    return false;
  }
  bucket.count += 1;
  return bucket.count > FALLBACK_LIMIT.requests;
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].slice(0, 8).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", ...extraHeaders },
  });
}

function error(status, type, message, extraHeaders = {}) {
  return json({ type: "error", error: { type, message } }, status, extraHeaders);
}
