import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Innertube, Platform } from "npm:youtubei.js@18.3.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// YouTube.js needs a small JS evaluator to decipher signed media URLs. This is
// the library's documented Deno/browser shim; the code being evaluated is the
// public YouTube player script fetched by the library, not user input.
Platform.shim.eval = async (
  data: { output: string },
  env: Record<string, string | number | boolean | null | undefined>,
) => {
  const names = Object.keys(env);
  const values = names.map((name) => env[name]);
  return new Function(...names, data.output)(...values);
};

let clientPromise: Promise<Innertube> | null = null;
function getClient(): Promise<Innertube> {
  clientPromise ??= Innertube.create({
    lang: "en",
    location: "US",
    retrieve_player: true,
    enable_session_cache: true,
  });
  return clientPromise;
}

const cache = new Map<string, { url: string; mime_type: string; expires: number }>();

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
      return Response.json({ audio_url: cached.url, mime_type: cached.mime_type, provider: "youtube_music" }, {
        headers: { ...CORS, "Cache-Control": "private, max-age=30" },
      });
    }

    const client = await getClient();
    let format: any = null;
    const failures: string[] = [];
    // Tori's resolver uses non-Music player clients for playback because the
    // YT Music client can return metadata while marking the stream unplayable.
    for (const playerClient of ["ANDROID", "WEB"] as const) {
      try {
        format = await client.getStreamingData(videoId, {
          type: "audio",
          quality: "best",
          client: playerClient,
        });
        if (format?.url) break;
      } catch (error) {
        failures.push(`${playerClient}: ${String(error).slice(0, 100)}`);
      }
    }
    const url = String(format?.url ?? "");
    if (!url.startsWith("https://") || !new URL(url).hostname.endsWith("googlevideo.com")) {
      throw new Error(failures.join("; ") || "YouTube did not return a usable audio URL");
    }
    const mimeType = String(format?.mime_type ?? "audio/webm");
    cache.set(videoId, { url, mime_type: mimeType, expires: Date.now() + 4 * 60 * 1000 });
    return Response.json({
      audio_url: url,
      mime_type: mimeType,
      bitrate: Number(format?.bitrate ?? 0),
      provider: "youtube_music",
    }, { headers: { ...CORS, "Cache-Control": "private, max-age=30" } });
  } catch (error) {
    console.error("youtube-music-stream:", error);
    return Response.json({
      error: "youtube_stream_unavailable",
      detail: String(error).slice(0, 220),
    }, { status: 502, headers: CORS });
  }
});
