import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Innertube } from "npm:youtubei.js@18.3.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const UA = "Nali/1.1 (https://github.com/lunethosdev-eng/nali)";

async function getText(url: string): Promise<string | null> {
  try {
    const response = await fetch(url, {
      headers: { "User-Agent": UA, Accept: "application/json, text/plain, */*" },
      signal: AbortSignal.timeout(5500),
    });
    return response.ok ? await response.text() : null;
  } catch { return null; }
}

function decode(value: string): string {
  return value.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/&#(\d+);/g, (_m, n) => String.fromCodePoint(Number(n)));
}

function timeMs(value: string): number | null {
  const parts = value.trim().split(":");
  const seconds = parts.length === 3
    ? Number(parts[0]) * 3600 + Number(parts[1]) * 60 + Number(parts[2])
    : parts.length === 2 ? Number(parts[0]) * 60 + Number(parts[1]) : Number(parts[0]);
  return Number.isFinite(seconds) && seconds >= 0 ? Math.round(seconds * 1000) : null;
}

function ttmlToLrc(value: string): string | null {
  const lines: { ms: number; text: string }[] = [];
  for (const match of value.matchAll(/<p\b([^>]*)>([\s\S]*?)<\/p>/gi)) {
    const begin = /\bbegin=["']([^"']+)["']/i.exec(match[1])?.[1];
    const ms = begin ? timeMs(begin) : null;
    const text = decode(match[2].replace(/<[^>]+>/g, "")).trim();
    if (ms !== null && text) lines.push({ ms, text });
  }
  if (!lines.length) return null;
  lines.sort((a, b) => a.ms - b.ms);
  return lines.map(({ ms, text }) => {
    const min = String(Math.floor(ms / 60000)).padStart(2, "0");
    const sec = String(Math.floor(ms % 60000 / 1000)).padStart(2, "0");
    const cs = String(Math.floor(ms % 1000 / 10)).padStart(2, "0");
    return `[${min}:${sec}.${cs}]${text}`;
  }).join("\n");
}

function normalize(value: unknown, format = "", syncType = ""): string | null {
  if (typeof value !== "string") return null;
  let text = value.trim();
  if (!text || /lyrics not found|no lyrics available|access denied from your region/i.test(text)) return null;
  if (/ttml/i.test(format) || /<tt(?:\s|>)/i.test(text) || /<p\b[^>]*\bbegin=/i.test(text)) return ttmlToLrc(text);
  if (/^\s*\{/.test(text)) {
    try {
      const data = JSON.parse(text);
      return normalize(data.ttml ?? data.lyrics ?? data.lrc ?? data.content ?? data.text, data.format ?? format, data.syncType ?? syncType);
    } catch { /* plain text */ }
  }
  if (/^\s*\[\d+,\d+]/m.test(text) && /\(\d+,\d+\)/.test(text)) {
    const rows: string[] = [];
    for (const line of text.split(/\r?\n/)) {
      const match = /^\[(\d+),\d+](.*)$/.exec(line.trim());
      if (!match) continue;
      const ms = Number(match[1]);
      const body = decode(match[2].replace(/\(\d+,\d+(?:,\d+)?\)/g, "")).trim();
      if (!body) continue;
      rows.push(`[${String(Math.floor(ms / 60000)).padStart(2, "0")}:${String(Math.floor(ms % 60000 / 1000)).padStart(2, "0")}.${String(Math.floor(ms % 1000 / 10)).padStart(2, "0")}]${body}`);
    }
    if (rows.length) return rows.join("\n");
  }
  text = decode(text.replace(/<br\s*\/?\s*>/gi, "\n").replace(/<[^>]+>/g, ""));
  if (syncType === "plain") text = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean).join("\n");
  return text.trim() || null;
}

function paramsUrl(base: string, title: string, artist: string, album: string, duration: number): string {
  const url = new URL(base);
  url.searchParams.set("s", title);
  url.searchParams.set("a", artist);
  if (duration > 0) url.searchParams.set("d", String(duration));
  if (album) url.searchParams.set("al", album);
  return url.toString();
}

async function betterLyrics(title: string, artist: string, album: string, duration: number, qq = false) {
  const raw = await getText(paramsUrl(qq ? "https://lyrics-api.boidu.dev/qq/getLyrics" : "https://lyrics-api.boidu.dev/getLyrics", title, artist, album, duration));
  return normalize(raw);
}

async function unison(title: string, artist: string, album: string, duration: number) {
  const url = new URL("https://unison.boidu.dev/lyrics");
  url.searchParams.set("song", title);
  url.searchParams.set("artist", artist);
  if (album) url.searchParams.set("album", album);
  if (duration > 0) url.searchParams.set("duration", String(duration));
  const raw = await getText(url.toString());
  if (!raw) return null;
  try {
    const data = JSON.parse(raw);
    return data?.success === true ? normalize(data?.data?.lyrics, data?.data?.format, data?.data?.syncType) : null;
  } catch { return null; }
}

async function simpmusic(videoId: string, duration: number) {
  if (!videoId) return null;
  const raw = await getText(`https://api-lyrics.simpmusic.org/v1/${encodeURIComponent(videoId)}`);
  if (!raw) return null;
  try {
    const data = JSON.parse(raw);
    if (data?.success !== true || !Array.isArray(data?.data)) return null;
    const rows = data.data.filter((item: any) => duration <= 0 || Math.abs(Number(item?.duration ?? 0) - duration) <= 10);
    rows.sort((a: any, b: any) => Math.abs(Number(a?.duration ?? 0) - duration) - Math.abs(Number(b?.duration ?? 0) - duration));
    const row = rows[0];
    return normalize(row?.richSyncLyrics, "lrc") ?? normalize(row?.syncedLyrics, "lrc") ?? normalize(row?.plainLyrics, "plain", "plain");
  } catch { return null; }
}

async function kugou(title: string, artist: string, album: string, duration: number) {
  const search = new URL("https://mobileservice.kugou.com/api/v3/search/song");
  search.search = new URLSearchParams({ version: "9108", plat: "0", pagesize: "8", showtype: "0", keyword: `${title} - ${artist} ${album}` }).toString();
  const raw = await getText(search.toString());
  if (!raw) return null;
  try {
    const info = JSON.parse(raw)?.data?.info ?? [];
    const songs = info.filter((item: any) => duration <= 0 || Math.abs(Number(item?.duration ?? 0) - duration) <= 8)
      .sort((a: any, b: any) => Math.abs(Number(a?.duration ?? 0) - duration) - Math.abs(Number(b?.duration ?? 0) - duration));
    for (const song of songs.slice(0, 3)) {
      const lookup = new URL("https://lyrics.kugou.com/search");
      lookup.search = new URLSearchParams({ ver: "1", man: "yes", client: "pc", hash: String(song.hash ?? "") }).toString();
      const found = await getText(lookup.toString());
      if (!found) continue;
      const candidate = JSON.parse(found)?.candidates?.[0];
      if (!candidate?.id || !candidate?.accesskey) continue;
      const download = new URL("https://lyrics.kugou.com/download");
      download.search = new URLSearchParams({ fmt: "lrc", charset: "utf8", client: "pc", ver: "1", id: String(candidate.id), accesskey: String(candidate.accesskey) }).toString();
      const content = await getText(download.toString());
      if (!content) continue;
      const encoded = JSON.parse(content)?.content;
      if (typeof encoded !== "string") continue;
      const decoded = new TextDecoder().decode(Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0)));
      const lines = decoded.split(/\r?\n/).filter((line) => /^\[\d{2}:\d{2}\.\d{2,3}]/.test(line)).join("\n");
      if (lines.length > 12) return normalize(lines, "lrc");
    }
  } catch { return null; }
  return null;
}

let ytClient: Promise<Innertube> | null = null;
async function youtubeMusicLyrics(videoId: string) {
  if (!videoId) return null;
  ytClient ??= Innertube.create({ lang: "en", location: "US", retrieve_player: false });
  try {
    const shelf: any = await Promise.race([
      (await ytClient).music.getLyrics(videoId),
      new Promise((_, reject) => setTimeout(() => reject(new Error("lyrics timeout")), 8000)),
    ]);
    const description = shelf?.description;
    return normalize(typeof description === "string" ? description : description?.toString?.(), "plain", "plain");
  } catch { return null; }
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") return Response.json({ error: "method_not_allowed" }, { status: 405, headers: CORS });
  try {
    const body = await request.json();
    const title = String(body?.title ?? "").trim().slice(0, 180);
    const artist = String(body?.artist ?? "").trim().slice(0, 180);
    const album = String(body?.album ?? "").trim().slice(0, 180);
    const videoId = String(body?.videoId ?? body?.youtube_id ?? "").trim();
    const duration = Math.max(0, Math.min(7200, Number(body?.durationSeconds) || 0));
    if (!title || !artist) return Response.json({ error: "invalid_track" }, { status: 400, headers: CORS });

    const providers: [string, () => Promise<string | null>][] = [
      ["BetterLyrics", () => betterLyrics(title, artist, album, duration)],
      ["BetterLyrics QQ", () => betterLyrics(title, artist, album, duration, true)],
      ["Unison", () => unison(title, artist, album, duration)],
      ["SimpMusic", () => simpmusic(videoId, duration)],
      ["KuGou", () => kugou(title, artist, album, duration)],
      ["YouTube Music", () => youtubeMusicLyrics(videoId)],
    ];
    const attempts = await Promise.all(providers.map(async ([provider, lookup]) => {
      try { return { provider, lyrics: await lookup() }; }
      catch (error) { console.warn(`lyrics provider ${provider}:`, String(error).slice(0, 120)); return { provider, lyrics: null }; }
    }));
    const winner = attempts.find((entry) => entry.lyrics && entry.lyrics.trim().length >= 12 && !/lyrics not found|server error/i.test(entry.lyrics));
    if (winner?.lyrics) {
      return Response.json({ lyrics: winner.lyrics, provider: winner.provider, synced: /^\s*\[\d{1,3}:\d{2}/m.test(winner.lyrics) }, {
        headers: { ...CORS, "Cache-Control": "private, max-age=120" },
      });
    }
    return Response.json({ lyrics: null, provider: null }, { headers: CORS });
  } catch (error) {
    console.error("lyrics-catalog:", error);
    return Response.json({ error: "lyrics_lookup_failed", detail: String(error).slice(0, 180) }, { status: 502, headers: CORS });
  }
});
