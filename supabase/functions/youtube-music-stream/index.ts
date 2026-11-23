import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Innertube, Platform } from "npm:youtubei.js@18.3.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// YouTube.js needs a JavaScript evaluator to decipher signed media URLs.
// The evaluated source is YouTube's public player script, not user input.
Platform.shim.eval = async (
  data: { output: string },
  env: Record<string, string | number | boolean | null | undefined>,
) => {
  // youtubei.js expects the evaluator to return the decipher functions, not
  // just execute the player script. Without these exports, signed `sig` and
  // throttling `n` parameters remain unusable even when the player script loads.
  const properties: string[] = [];
  if (env.n) {
    properties.push(`n: exportedVars.nFunction(${JSON.stringify(env.n)})`);
  }
  if (env.sig) {
    properties.push(`sig: exportedVars.sigFunction(${JSON.stringify(env.sig)})`);
  }
  return new Function(`${data.output}\nreturn { ${properties.join(', ')} }`)();
};

// Supabase Edge egress can fail against www.youtube.com. Retry InnerTube API
// calls through Google's API hostname before giving up; keep player-script
// and googlevideo requests on their original hosts.
const API_HOSTS = [
  "youtubei.googleapis.com",
  "www.youtube.com",
  "music.youtube.com",
] as const;

const innertubeFetch: typeof fetch = async (input, init) => {
  const request = new Request(input, init);
  const original = new URL(request.url);
  if (!original.pathname.startsWith("/youtubei/v1/")) {
    return fetch(request);
  }

  const failures: string[] = [];
  for (const host of API_HOSTS) {
    const target = new URL(original);
    target.hostname = host;
    try {
      const response = await fetch(new Request(target, request.clone()));
      if (response.ok) return response;
      failures.push(host + ":HTTP " + response.status);
    } catch (error) {
      failures.push(host + ":" + String(error).slice(0, 120));
    }
  }
  throw new Error("InnerTube endpoint failed on all hosts (" + failures.join(" | ") + ")");
};

let clientPromise: Promise<Innertube> | null = null;
function getClient(): Promise<Innertube> {
  clientPromise ??= Innertube.create({
    lang: "en",
    location: "US",
    retrieve_player: true,
    enable_session_cache: true,
    fetch: innertubeFetch,
  });
  return clientPromise;
}

type CachedStream = {
  url: string;
  mime_type: string;
  bitrate: number;
  duration_seconds: number;
  expires: number;
};
const cache = new Map<string, CachedStream>();

const FORMAT_ATTEMPTS = [
  { client: "TV_EMBEDDED", codec: "mp4a", format: "mp4" },
  { client: "TV_EMBEDDED" },
  { client: "ANDROID", codec: "mp4a", format: "mp4" },
  { client: "ANDROID" },
  { client: "WEB" },
] as const;

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405, headers: CORS });
  }

  try {
    const body = await request.json();
    const videoId = String(body?.videoId ?? body?.youtube_id ?? "").trim();
    if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) {
      return Response.json({ error: "invalid_video_id" }, { status: 400, headers: CORS });
    }

    const cached = cache.get(videoId);
    if (cached && cached.expires > Date.now()) {
      return Response.json({
        audio_url: cached.url,
        mime_type: cached.mime_type,
        bitrate: cached.bitrate,
        duration_seconds: cached.duration_seconds,
        provider: "youtube_music",
      }, { headers: { ...CORS, "Cache-Control": "private, max-age=30" } });
    }

    const client = await getClient();
    const failures: string[] = [];
    let selected: any = null;

    // TV_EMBEDDED often exposes audio formats without the same restrictions
    // as WEB/ANDROID. Prefer AAC/MP4 for browser compatibility, then allow the
    // best available audio format as a fallback.
    for (const attempt of FORMAT_ATTEMPTS) {
      try {
        const format = await client.getStreamingData(videoId, {
          type: "audio",
          quality: "best",
          ...attempt,
        });
        const url = String(format?.url ?? "");
        if (url.startsWith("https://") && new URL(url).hostname.endsWith("googlevideo.com")) {
          selected = format;
          break;
        }
        failures.push(attempt.client + ":no_usable_audio_format");
      } catch (error) {
        failures.push(attempt.client + "/" + ("codec" in attempt ? attempt.codec : "auto") + ":" + String(error).slice(0, 180));
      }
    }

    const url = String(selected?.url ?? "");
    if (!url.startsWith("https://") || !new URL(url).hostname.endsWith("googlevideo.com")) {
      throw new Error(failures.join(" || ") || "YouTube returned no playable audio format");
    }

    const mimeType = String(selected?.mime_type ?? "audio/mp4");
    const durationSeconds = Math.max(0, Math.round(Number(selected?.approx_duration_ms ?? 0) / 1000));
    const result: CachedStream = {
      url,
      mime_type: mimeType,
      bitrate: Number(selected?.bitrate ?? 0),
      duration_seconds: durationSeconds,
      expires: Date.now() + 3 * 60 * 1000,
    };
    cache.set(videoId, result);

    return Response.json({
      audio_url: result.url,
      mime_type: result.mime_type,
      bitrate: result.bitrate,
      duration_seconds: result.duration_seconds,
      provider: "youtube_music",
    }, { headers: { ...CORS, "Cache-Control": "private, max-age=30" } });
  } catch (error) {
    console.error("youtube-music-stream:", error);
    return Response.json({
      error: "youtube_stream_unavailable",
      detail: String(error).slice(0, 900),
    }, { status: 502, headers: CORS });
  }
});
