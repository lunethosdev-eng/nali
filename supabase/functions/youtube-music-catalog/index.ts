import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const KEY = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30";
type Track = {
  id: string; youtube_id: string; title: string; artist: string; album: string;
  cover_url: string; audio_url: null; duration: number;
  provider: string; source: string; downloadable: false;
};

function textOf(value: unknown): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return value.map(textOf).filter(Boolean).join(" ");
  if (!value || typeof value !== "object") return "";
  const obj = value as Record<string, unknown>;
  if (typeof obj.text === "string") return obj.text;
  if (obj.text && typeof obj.text === "object") return textOf(obj.text);
  if (Array.isArray(obj.runs)) return (obj.runs as unknown[]).map(textOf).join("");
  if (obj.musicResponsiveListItemFlexColumnRenderer) return textOf(obj.musicResponsiveListItemFlexColumnRenderer);
  return "";
}

function thumbnailOf(value: unknown): string | null {
  if (Array.isArray(value)) {
    for (let i = value.length - 1; i >= 0; i--) {
      const found = thumbnailOf(value[i]);
      if (found) return found;
    }
  } else if (value && typeof value === "object") {
    const obj = value as Record<string, unknown>;
    if (Array.isArray(obj.thumbnails)) {
      for (let i = (obj.thumbnails as unknown[]).length - 1; i >= 0; i--) {
        const url = ((obj.thumbnails as Record<string, unknown>[])[i])?.url;
        if (typeof url === "string" && url.startsWith("https://")) return url.replaceAll("\\u0026", "&");
      }
    }
    for (const child of Object.values(obj)) {
      const found = thumbnailOf(child);
      if (found) return found;
    }
  }
  return null;
}

function walk(value: unknown, output: Track[], seen: Set<string>, limit: number): void {
  if (value == null || output.length >= limit) return;
  if (Array.isArray(value)) {
    for (const child of value) walk(child, output, seen, limit);
    return;
  }
  if (typeof value !== "object") return;
  const obj = value as Record<string, unknown>;
  const item = (obj.musicResponsiveListItemRenderer ?? obj.musicTwoRowItemRenderer) as Record<string, unknown> | undefined;
  if (item) {
    const id = JSON.stringify(item).match(/"videoId"\s*:\s*"([A-Za-z0-9_-]{11})"/)?.[1];
    if (id && !seen.has(id)) {
      seen.add(id);
      const columns = Array.isArray(item.flexColumns) ? item.flexColumns : [];
      const title = textOf(columns[0] ?? item.title) || "YouTube Music";
      const artist = textOf(columns[1] ?? item.subtitle) || "YouTube Music";
      output.push({
        id: `yt_${id}`, youtube_id: id, title, artist, album: "YouTube Music",
        cover_url: thumbnailOf(item) ?? `https://i.ytimg.com/vi/${id}/hqdefault.jpg`,
        audio_url: null, duration: 0, provider: "youtube_music", source: "youtube_music", downloadable: false,
      });
    }
    return;
  }
  for (const child of Object.values(obj)) walk(child, output, seen, limit);
}

async function search(query: string, limit: number, clientName: string, version: string, clientId: string): Promise<Track[]> {
  const response = await fetch(`https://music.youtube.com/youtubei/v1/search?key=${KEY}&prettyPrint=false`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json", "Origin": "https://music.youtube.com",
      "Referer": "https://music.youtube.com/", "X-YouTube-Client-Name": clientId,
      "X-YouTube-Client-Version": version,
      "User-Agent": clientName === "ANDROID_MUSIC"
        ? `com.google.android.apps.youtube.music/${version} (Linux; U; Android 14)`
        : "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36",
    },
    // The params value is base64. Do not URL-encode the trailing == characters.
    body: JSON.stringify({
      context: { client: { clientName, clientVersion: version, hl: "es", gl: "US" } },
      query, params: "EgWKAQIIAWoKEAMQBBAJEAoQBQ==",
    }),
    signal: AbortSignal.timeout(14000),
  });
  if (!response.ok) throw new Error(`YouTube Music HTTP ${response.status}`);
  const output: Track[] = [];
  walk(await response.json(), output, new Set<string>(), limit);
  return output;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") return Response.json({ error: "method_not_allowed" }, { status: 405, headers: CORS });
  try {
    const body = await request.json();
    const query = String(body?.query ?? "").trim();
    const limit = Math.max(1, Math.min(30, Number(body?.limit) || 20));
    if (query.length < 2 || query.length > 120) {
      return Response.json({ error: "invalid_query" }, { status: 400, headers: CORS });
    }
    let results: Track[] = [];
    const errors: string[] = [];
    try { results = await search(query, limit, "WEB_REMIX", "1.20260707.12.00", "67"); }
    catch (error) { errors.push(String(error)); }
    if (!results.length) {
      try { results = await search(query, limit, "ANDROID_MUSIC", "8.39.42", "21"); }
      catch (error) { errors.push(String(error)); }
    }
    return Response.json({ results, provider: "youtube_music", metadata_only: true, upstream_errors: results.length ? undefined : errors }, {
      headers: { ...CORS, "Cache-Control": "private, max-age=30" },
    });
  } catch (error) {
    return Response.json({ error: "youtube_catalog_unavailable", detail: String(error).slice(0, 160) }, { status: 502, headers: CORS });
  }
});
