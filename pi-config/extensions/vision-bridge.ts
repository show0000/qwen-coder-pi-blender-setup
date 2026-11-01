/**
 * vision-bridge — pi extension
 *
 * The coder model (Qwen3-Coder-Next) is text-only. Whenever any tool result contains an
 * image (e.g. Blender MCP get_viewport_screenshot, or `read` on a PNG), this extension sends
 * the image to the local VLM server (Qwen3.8-27B VL on :8081) and replaces the image block
 * with the VLM's text description. The coder never sees an image block, never needs to
 * switch models, and the session only accumulates a few hundred tokens of text per image.
 *
 * Config (env, or ~/.config/qwen-coder/env.sh):
 *   VISION_BASE_URL      default http://127.0.0.1:8081/v1
 *   VISION_MODEL_ID      default qwen3.8-27b-vl
 *   VISION_BRIDGE        "off" disables; "always" converts even for image-capable models
 *   VISION_BRIDGE_PROMPT override the default question
 *   VISION_MAX_TOKENS    default 600
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

type Block = { type: string; text?: string; data?: string; mimeType?: string; [k: string]: unknown };

function loadEnvFile(): Record<string, string> {
  const out: Record<string, string> = {};
  try {
    const txt = readFileSync(join(homedir(), ".config", "qwen-coder", "env.sh"), "utf8");
    for (const line of txt.split("\n")) {
      const m = line.match(/^\s*export\s+([A-Z0-9_]+)=["']?([^"'\n]*)["']?/);
      if (m) out[m[1]] = m[2];
    }
  } catch { /* no env file */ }
  return out;
}

const fileEnv = loadEnvFile();
const cfg = (k: string, d: string) => process.env[k] ?? fileEnv[k] ?? d;
const BASE = cfg("VISION_BASE_URL", `http://127.0.0.1:${cfg("VISION_PORT", "8081")}/v1`);
const MODEL = cfg("VISION_MODEL_ID", "qwen3.8-27b-vl");
const MODE = cfg("VISION_BRIDGE", "auto"); // auto | always | off
const MAXTOK = Number(cfg("VISION_MAX_TOKENS", "600"));
const DEFAULT_PROMPT = cfg(
  "VISION_BRIDGE_PROMPT",
  "You are the eyes for a text-only coding agent doing 3D modeling in Blender. Describe this image precisely and briefly: " +
  "objects visible, their relative placement and orientation, holes/cuts/features and which face they are on, " +
  "approximate proportions, and anything that looks wrong (overlap, gaps, flipped normals, wrong placement). " +
  "If it is not a 3D viewport, describe what it shows. Plain text, no markdown headers.",
);

async function describe(data: string, mimeType: string, question: string): Promise<string> {
  const body = {
    model: MODEL, max_tokens: MAXTOK, temperature: 0.2,
    messages: [{ role: "user", content: [
      { type: "text", text: question },
      { type: "image_url", image_url: { url: `data:${mimeType};base64,${data}` } },
    ] }],
  };
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 300_000);
  try {
    const r = await fetch(`${BASE}/chat/completions`, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), signal: ctrl.signal,
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const j = await r.json() as any;
    const c = j?.choices?.[0]?.message?.content;
    const text = typeof c === "string" ? c : Array.isArray(c) ? c.map((p: any) => p?.text ?? "").join("") : "";
    return text.trim() || "(empty response from vision model)";
  } finally { clearTimeout(t); }
}

async function serverUp(): Promise<boolean> {
  try {
    const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 1500);
    const r = await fetch(`${BASE}/models`, { signal: ctrl.signal }); clearTimeout(t);
    return r.ok;
  } catch { return false; }
}

export default function (pi: ExtensionAPI) {
  if (MODE === "off") return;

  pi.on("tool_result", async (event: any, ctx: any) => {
    const content: Block[] = Array.isArray(event.content) ? event.content : [];
    if (!content.some((b) => b?.type === "image")) return;

    // Skip when the active model can see images itself (unless forced)
    const modelInput: string[] | undefined = ctx?.model?.input ?? ctx?.modelRegistry?.current?.input;
    if (MODE !== "always" && Array.isArray(modelInput) && modelInput.includes("image")) return;

    const up = await serverUp();
    const question = typeof event.input?.question === "string" ? event.input.question : DEFAULT_PROMPT;
    const out: Block[] = [];
    let n = 0;
    for (const b of content) {
      if (b?.type !== "image" || !b.data) { out.push(b); continue; }
      n++;
      if (!up) {
        out.push({ type: "text", text: `[vision-bridge] image #${n} omitted: vision server not running at ${BASE}. Run \`qwen vision start\`, then call the tool again.` });
        continue;
      }
      try {
        const desc = await describe(b.data, b.mimeType || "image/png", question);
        out.push({ type: "text", text: `[vision-bridge] image #${n} described by ${MODEL}:\n${desc}` });
      } catch (e: any) {
        out.push({ type: "text", text: `[vision-bridge] image #${n} failed: ${e?.message ?? e}` });
      }
    }
    return { content: out };
  });
}
