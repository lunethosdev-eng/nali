import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
type Track = Record<string, unknown>;

async function appleSearch(query: string, limit: number): Promise<Track[]> {
  const url = new URL("https://itunes.apple.com/search");
  url.searchParams.set("term", query); url.searchParams.set("entity", "song");
  url.searchParams.set("media", "music"); url.searchParams.set("limit", String(limit));
  const response = await fetch(url, { headers: { Accept: "application/json", "User-Agent": "Nali/1.1" }, signal: AbortSignal.timeout(12000) });
  if (!response.ok) throw new Error(`Apple Search HTTP ${response.status}`);
  const body = await response.json();
  const rows = Array.isArray(body?.results) ? body.results : [];
  return rows.filter((row: Record<string, unknown>) => typeof row.previewUrl === "string").map((row: Record<string, unknown>) => ({
    id: `apple_${row.trackId ?? row.collectionId ?? crypto.randomUUID()}`,
    provider: "apple_music", source: "apple_music", title: String(row.trackName ?? "Apple Music track"),
    artist: String(row.artistName ?? "Apple Music"), album: String(row.collectionName ?? ""),
    cover_url: typeof row.artworkUrl100 === "string" ? row.artworkUrl100.replace("100x100", "600x600") : null,
    audio_url: row.previewUrl, stream_url: row.previewUrl,
    duration: typeof row.trackTimeMillis === "number" ? Math.round(row.trackTimeMillis / 1000) : 30,
    duration_ms: row.trackTimeMillis ?? 30000, permalink_url: row.trackViewUrl ?? null,
    preview_only: true, downloadable: false,
  }));
}

async function deezerSearch(query: string, limit: number): Promise<Track[]> {
  const url = new URL("https://api.deezer.com/search/track");
  url.searchParams.set("q", query); url.searchParams.set("limit", String(limit));
  const response = await fetch(url, { headers: { Accept: "application/json", "User-Agent": "Nali/1.1" }, signal: AbortSignal.timeout(12000) });
  if (!response.ok) throw new Error(`Deezer HTTP ${response.status}`);
  const body = await response.json();
  const rows = Array.isArray(body?.data) ? body.data : [];
  return rows.filter((row: Record<string, unknown>) => typeof row.preview === "string").map((row: Record<string, unknown>) => {
    const artist = row.artist && typeof row.artist === "object" ? row.artist as Record<string, unknown> : {};
    const album = row.album && typeof row.album === "object" ? row.album as Record<string, unknown> : {};
    return {
      id: `deezer_${row.id ?? crypto.randomUUID()}`, provider: "deezer", source: "deezer",
      title: String(row.title ?? "Deezer track"), artist: String(artist.name ?? "Deezer"),
      album: String(album.title ?? ""), cover_url: album.cover_big ?? album.cover_medium ?? null,
      audio_url: row.preview, stream_url: row.preview,
      duration: typeof row.duration === "number" ? row.duration : 30,
      duration_ms: typeof row.duration === "number" ? row.duration * 1000 : 30000,
      permalink_url: row.link ?? null, preview_only: true, downloadable: false,
    };
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") return Response.json({ error: "method_not_allowed" }, { status: 405, headers: CORS });
  try {
    const body = await request.json();
    const provider = String(body?.provider ?? "").toLowerCase();
    const query = String(body?.query ?? "").trim();
    const limit = Math.max(1, Math.min(30, Number(body?.limit) || 20));
    if (query.length < 2 || query.length > 120 || !["apple", "deezer"].includes(provider)) {
      return Response.json({ error: "invalid_request" }, { status: 400, headers: CORS });
    }
    const results = provider === "apple" ? await appleSearch(query, limit) : await deezerSearch(query, limit);
    return Response.json({ provider, results, preview_only: true }, { headers: { ...CORS, "Cache-Control": "public, max-age=60" } });
  } catch (error) {
    return Response.json({ error: "music_provider_unavailable", detail: String(error).slice(0, 180) }, { status: 502, headers: CORS });
  }
});
