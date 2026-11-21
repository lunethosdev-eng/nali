import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return Response.json({ error: "method_not_allowed" }, { status: 405, headers: CORS });
  try {
    const body = await req.json();
    const raw = String(body?.url ?? "").trim();
    const track = new URL(raw);
    if (track.protocol !== "https:" || !(track.hostname === "soundcloud.com" || track.hostname.endsWith(".soundcloud.com"))) {
      return Response.json({ error: "invalid_soundcloud_url" }, { status: 400, headers: CORS });
    }
    const endpoint = new URL("https://soundcloud.com/oembed");
    endpoint.searchParams.set("format", "json");
    endpoint.searchParams.set("url", track.toString());
    const response = await fetch(endpoint, { headers: { Accept: "application/json" }, signal: AbortSignal.timeout(12000) });
    if (!response.ok) return Response.json({ error: "soundcloud_track_unavailable", status: response.status }, { status: 404, headers: CORS });
    const data = await response.json();
    const html = String(data?.html ?? "");
    const embed = html.match(/src=["']([^"']+)["']/i)?.[1] ?? null;
    return Response.json({
      title: String(data?.title ?? "SoundCloud track").slice(0, 180),
      artist: String(data?.author_name ?? "SoundCloud").slice(0, 120),
      thumbnail_url: data?.thumbnail_url ?? null,
      url: track.toString(), embed_url: embed,
      provider: "soundcloud", playback: "official_embed_or_external_link",
      downloadable: false, api_key_required: false,
    }, { headers: { ...CORS, "Cache-Control": "public, max-age=300" } });
  } catch (error) {
    return Response.json({ error: "soundcloud_oembed_failed", detail: String(error).slice(0, 160) }, { status: 502, headers: CORS });
  }
});
