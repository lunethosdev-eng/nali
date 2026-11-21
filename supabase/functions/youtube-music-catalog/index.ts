import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const API_KEY = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "public, max-age=30" },
});

type Song = { id: string; title: string; artist: string; album: string; cover_url: string; audio_url: null; duration: number; provider: string; source: string; youtube_id: string; downloadable: false };

function thumbnailOf(node: unknown): string | null {
  if (Array.isArray(node)) {
    for (let i = node.length - 1; i >= 0; i--) { const found = thumbnailOf(node[i]); if (found) return found; }
    return null;
  }
  if (node && typeof node === "object") {
    const obj = node as Record<string, unknown>;
    const thumbs = obj.thumbnails;
    if (Array.isArray(thumbs)) {
      for (let i = thumbs.length - 1; i >= 0; i--) {
        const url = (thumbs[i] as Record<string, unknown> | null)?.url;
        if (typeof url === "string" && url.startsWith("https://")) return url.replaceAll("\\u0026", "&");
      }
    }
    for (const value of Object.values(obj)) { const found = thumbnailOf(value); if (found) return found; }
  }
  return null;
}

function collect(node: unknown, out: Song[], seen: Set<string>, limit: number) {
  if (out.length >= limit || node == null) return;
  if (Array.isArray(node)) { for (const child of node) collect(child, out, seen, limit); return; }
  if (typeof node !== "object") return;
  const obj = node as Record<string, unknown>;
  const item = (obj.musicResponsiveListItemRenderer ?? obj.musicTwoRowItemRenderer) as Record<string, unknown> | undefined;
  if (item) {
    const raw = JSON.stringify(item);
    const id = raw.match(/"videoId"\s*:\s*"([A-Za-z0-9_-]{11})"/)?.[1];
    if (id && !seen.has(id)) {
      seen.add(id);
      const flex = Array.isArray(item.flexColumns) ? item.flexColumns : [];
      const textOf = (value: unknown): string => {
        if (value == null) return "";
        if (typeof value === "string") return value;
        if (Array.isArray(value)) return value.map(textOf).filter(Boolean).join(" ");
        if (typeof value === "object") {
          const o = value as Record<string, unknown>;
          if (typeof o.text === "string") return o.text;
          if (Array.isArray(o.runs)) return o.runs.map((r) => textOf(r)).filter(Boolean).join("");
          for (const [k, v] of Object.entries(o)) if (k.toLowerCase().includes("text") || k === "runs") { const t = textOf(v); if (t) return t; }
        }
        return "";
      };
      const title = textOf(flex[0] ?? item.title) || "YouTube Music";
      const artist = textOf(flex[1] ?? item.subtitle) || "YouTube Music";
      const cover = thumbnailOf(item);
      out.push({ id: `yt_${id}`, youtube_id: id, title, artist, album: "YouTube Music", cover_url: cover ?? `https://i.ytimg.com/vi/${id}/hqdefault.jpg`, audio_url: null, duration: 0, provider: "youtube_music", source: "youtube_music", downloadable: false });
    }
    return;
  }
  for (const child of Object.values(obj)) collect(child, out, seen, limit);
}

async function search(query: string, limit: number, clientName: string, clientVersion: string, clientId: string) {
  const response = await fetch(`https://music.youtube.com/youtubei/v1/search?key=${API_KEY}&prettyPrint=false`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Origin": "https://music.youtube.com",
      "Referer": "https://music.youtube.com/",
      "X-YouTube-Client-Name": clientId,
      "X-YouTube-Client-Version": clientVersion,
      "User-Agent": clientName === "ANDROID_MUSIC"
        ? `com.google.android.apps.youtube.music/${clientVersion} (Linux; U; Android 14)`
        : "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36",
    },
    body: JSON.stringify({ context: { client: { clientName, clientVersion, hl: "es", gl: "US" } }, query }),
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) throw new Error(`YouTube Music upstream HTTP ${response.status}`);
  const payload = await response.json();
  const results: Song[] = [];
  collect(payload, results, new Set(), limit);
  return results;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const body = await req.json();
    const query = String(body?.query ?? "").trim();
    const limit = Math.max(1, Math.min(30, Number(body?.limit) || 20));
    if (query.length < 2 || query.length > 120) return json({ error: "invalid_query" }, 400);
    let results: Song[] = [];
    try { results = await search(query, limit, "WEB_REMIX", "1.20260707.12.00", "67"); } catch { /* alternate client below */ }
    if (!results.length) results = await search(query, limit, "ANDROID_MUSIC", "8.39.42", "21");
    return json({ results, provider: "youtube_music", metadata_only: true });
  } catch (error) {
    return json({ error: "youtube_catalog_unavailable", detail: String(error).slice(0, 160) }, 502);
  }
});
