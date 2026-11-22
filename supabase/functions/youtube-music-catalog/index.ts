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
  preview_only: false;
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

function asArray(value: unknown): any[] {
  if (Array.isArray(value)) return value;
  if (value && typeof value === "object" && Symbol.iterator in value) {
    try { return Array.from(value as Iterable<unknown>); } catch { return []; }
  }
  return [];
}

function textOf(value: any): string {
  if (typeof value === "string" || typeof value === "number") return String(value).trim();
  if (value && typeof value === "object") {
    if (typeof value.text === "string") return value.text.trim();
    if (typeof value.toString === "function") {
      const text = String(value.toString()).trim();
      if (text && text !== "[object Object]") return text;
    }
  }
  return "";
}

function durationOf(item: any): number {
  const direct = Number(item?.duration?.seconds ?? item?.duration_seconds ?? item?.durationSeconds ?? 0);
  if (Number.isFinite(direct) && direct > 0) return Math.round(direct);
  const label = textOf(item?.duration?.text ?? item?.duration);
  const parts = label.split(":").map(Number);
  if (parts.length === 2 && parts.every(Number.isFinite)) return parts[0] * 60 + parts[1];
  if (parts.length === 3 && parts.every(Number.isFinite)) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  return 0;
}

function toTrack(item: any): Track | null {
  const videoId = String(
    item?.id ?? item?.video_id ?? item?.videoId ??
    item?.endpoint?.payload?.videoId ?? item?.endpoint?.payload?.video_id ?? ""
  ).trim();
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) return null;

  const title = textOf(item?.title ?? item?.name);
  if (!title) return null;

  const rawArtists = asArray(item?.artists ?? item?.authors);
  const artist = rawArtists.map((entry: any) => textOf(entry?.name ?? entry))
    .filter(Boolean).join(", ") ||
    textOf(item?.author?.name ?? item?.author) || "YouTube Music";

  const album = textOf(item?.album?.name ?? item?.album) || "YouTube Music";
  const thumbnails = asArray(item?.thumbnails ?? item?.thumbnail?.contents ?? item?.thumbnail);
  const cover = [...thumbnails].reverse().map((entry: any) => textOf(entry?.url ?? entry?.source))
    .find((url: string) => url.startsWith("https://")) ??
    `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;
  const duration = durationOf(item);

  return {
    id: `yt_${videoId}`,
    youtube_id: videoId,
    title,
    artist,
    album,
    cover_url: cover,
    audio_url: null,
    duration,
    duration_seconds: duration,
    provider: "youtube_music",
    source: "youtube_music",
    permalink_url: `https://music.youtube.com/watch?v=${videoId}`,
    preview_only: false,
    downloadable: false,
  };
}

function itemsFrom(search: any): any[] {
  const items: any[] = [];
  const shelves = [
    search?.songs,
    search?.videos,
    ...asArray(search?.contents).filter((node: any) =>
      node?.type === "MusicShelf" || node?.type === "MusicCardShelf" ||
      node?.type === "ItemSection"
    ),
  ];
  for (const shelf of shelves) {
    items.push(...asArray(shelf?.contents));
    for (const child of asArray(shelf?.contents)) {
      if (child?.contents) items.push(...asArray(child.contents));
    }
  }
  return items;
}

function extractTracks(search: any, limit: number): Track[] {
  const seen = new Set<string>();
  const output: Track[] = [];
  for (const item of itemsFrom(search)) {
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
    let rawCount = itemsFrom(filtered).length;

    if (results.length < Math.min(5, limit)) {
      const broad = await music.search(query, { type: "all" });
      rawCount += itemsFrom(broad).length;
      const extra = extractTracks(broad, limit);
      const seen = new Set(results.map((track) => track.youtube_id));
      results = [...results, ...extra.filter((track) => !seen.has(track.youtube_id))].slice(0, limit);
    }

    console.log("youtube catalog search", {
      queryLength: query.length,
      filteredRawCount: itemsFrom(filtered).length,
      rawCount,
      resultCount: results.length,
      filteredContents: asArray(filtered?.contents).length,
    });

    return Response.json({
      results,
      count: results.length,
      provider: "youtube_music",
      metadata_only: true,
      preview_only: false,
    }, { headers: { ...CORS, "Cache-Control": "private, max-age=20" } });
  } catch (error) {
    console.error("youtube-music-catalog:", error);
    return Response.json({
      error: "youtube_catalog_unavailable",
      detail: String(error).slice(0, 220),
      results: [],
    }, { status: 502, headers: CORS });
  }
});
