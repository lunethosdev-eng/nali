// Secure ACRCloud Humming Recognition proxy for Nali.
// Secrets are server-side only; never put ACRCloud access_secret in the app.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, "Content-Type": "application/json" },
});

async function hmacSha1(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  return btoa(String.fromCharCode(...sig));
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const host = Deno.env.get("ACRCLOUD_HOST");
  const accessKey = Deno.env.get("ACRCLOUD_ACCESS_KEY");
  const accessSecret = Deno.env.get("ACRCLOUD_ACCESS_SECRET");
  if (!supabaseUrl || !anonKey || !host || !accessKey || !accessSecret) {
    return json({ error: "Server not configured: set ACRCloud secrets" }, 503);
  }

  // Require a valid signed-in Supabase user (JWT verified here as an extra guard).
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Sign in required" }, 401);
  const sb = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: auth } } });
  const { data: userData, error: authError } = await sb.auth.getUser();
  if (authError || !userData.user) return json({ error: "Invalid session" }, 401);

  let input: { audio_base64?: string; mime_type?: string };
  try { input = await req.json(); } catch { return json({ error: "JSON body required" }, 400); }
  const encoded = input.audio_base64 ?? "";
  if (!encoded || encoded.length > 6_500_000) return json({ error: "Audio required (max ~4.8 MB audio)" }, 413);
  const bytes = Uint8Array.from(atob(encoded.replace(/^data:[^,]+,/, "")), c => c.charCodeAt(0));
  if (bytes.length < 8_000 || bytes.length > 4_800_000) return json({ error: "Audio clip must be 8 KB–4.8 MB" }, 400);

  const endpoint = "/v1/identify";
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const stringToSign = ["POST", endpoint, accessKey, "audio", "1", timestamp].join("\n");
  const signature = await hmacSha1(accessSecret, stringToSign);
  const form = new FormData();
  form.set("sample", new Blob([bytes], { type: input.mime_type || "audio/webm" }), "sample.webm");
  form.set("sample_bytes", String(bytes.length));
  form.set("access_key", accessKey);
  form.set("data_type", "audio");
  form.set("signature_version", "1");
  form.set("signature", signature);
  form.set("timestamp", timestamp);

  try {
    const response = await fetch(`https://${host.replace(/^https?:\/\//, "")}${endpoint}`, {
      method: "POST", body: form, signal: AbortSignal.timeout(18_000),
    });
    const result = await response.json();
    if (!response.ok) return json({ error: "ACRCloud request failed", status: response.status }, 502);
    // Return only matching metadata; don't leak request credentials/signature.
    const status = result?.status ?? {};
    const matches = result?.metadata?.humming ?? result?.metadata?.music ?? [];
    const first = matches[0] ?? null;
    return json({
      status_code: status.code ?? "unknown",
      status_message: status.msg ?? "",
      match: first ? {
        title: first.title ?? "",
        artists: (first.artists ?? []).map((a: { name?: string }) => a.name ?? ""),
        album: first.album?.name ?? "",
        release_date: first.release_date ?? "",
        score: first.score ?? null,
        play_offset_ms: first.play_offset_ms ?? null,
        external_ids: first.external_ids ?? {},
      } : null,
    });
  } catch {
    return json({ error: "Recognition provider timeout or network error" }, 504);
  }
});
