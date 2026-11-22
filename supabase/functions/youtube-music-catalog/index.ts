import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Innertube } from "npm:youtubei.js@18.3.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Track = {
  id: string;
  youtube_id: string;
  title: string;
  artist: string;
  album: string;
  cover_url: string;
  audio_url: null;
  duration: number;
  duration_seconds: number;
  provider: "youtube_music";
  source: "youtube_music";
  permalink_url: string;
  downloadable: false;
};

let clientPromise: Promise<Innertube> | null = null;
function getClient(): Promise<Innertube> {
  clientPromise ??= Innertube.create({
    lang: "es",
    location: "US",
    retrieve_player: false,
    enable_session_cache: true,
  });
  return clientPromise;
}

function toTrack(item: any): Track | null {
  const videoId = String(item?.id ?? "").trim();
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) return null;
  const title = String(item?.title ?? "").trim();
  if (!title) return null;
  const artist = (Array.isArray(item?.artists) ? item.artists : [])
    .map((entry: any) => String(entry?.name ?? "").trim())
    .filter(Boolean)
    .join(", ") || String(item?.author?.name ?? "YouTube Music");
  const album = String(item?.album?.name ?? "YouTube Music");
  const thumbnails = Array.isArray(item?.thumbnails) ? item.thumbnails : [];
  const cover = [...thumbnails].reverse().find((entry: any) =>
    typeof entry?.url === "string" && entry.url.startsWith("https://")
  )?.url ?? `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;
  const duration = Number(item?.duration?.seconds ?? 0) || 0;
  return {
    id: `yt_${videoId}`,
    youtube_id: videoId,
    title,
    artist,
    album,
    cover_url: String(cover),
    audio_url: null,
    duration,
    duration_seconds: duration,
    provider: "youtube_music",
    source: "youtube_music",
    permalink_url: `https://music.youtube.com/watch?v=${videoId}`,
    downloadable: false,
  };
}

function extractTracks(search: any, limit: number): Track[] {
  const items = [
    ...(search?.songs?.contents ?? []),
    ...(search?.videos?.contents ?? []),
  ];
  const seen = new Set<string>();
  const output: Track[] = [];
  for (const item of items) {
    const track = toTrack(item);
    if (!track || seen.has(track.youtube_id)) continue;
    seen.add(track.youtube_id);
    output.push(track);
    if (output.length >= limit) break;
  }
  return output;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405, headers: CORS });
  }
  try {
    const body = await request.json();
    const query = String(body?.query ?? "").trim();
    const limit = Math.max(1, Math.min(30, Number(body?.limit) || 20));
    if (query.length < 2 || query.length > 120) {
      return Response.json({ error: "invalid_query" }, { status: 400, headers: CORS });
    }

    const music = (await getClient()).music;
    const filtered = await music.search(query, { type: "song" });
    let results = extractTracks(filtered, limit);
    if (results.length < Math.min(5, limit)) {
      // Artist-name searches can return an artist shelf before the song shelf.
      // A broad pass lets the parser expose song/video rows in that layout too.
      const broad = await music.search(query, { type: "all" });
      const extra = extractTracks(broad, limit);
      const seen = new Set(results.map((track) => track.youtube_id));
      results = [...results, ...extra.filter((track) => !seen.has(track.youtube_id))].slice(0, limit);
    }

    return Response.json({
      results,
      count: results.length,
      provider: "youtube_music",
      metadata_only: true,
    }, { headers: { ...CORS, "Cache-Control": "private, max-age=30" } });
  } catch (error) {
    console.error("youtube-music-catalog:", error);
    return Response.json({
      error: "youtube_catalog_unavailable",
      detail: String(error).slice(0, 220),
      results: [],
    }, { status: 502, headers: CORS });
  }
});
