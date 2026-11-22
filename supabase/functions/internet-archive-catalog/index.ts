import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function jsonGet(url: string): Promise<any | null> {
  try {
    const response = await fetch(url, {
      headers: { "User-Agent": "Nali/1.1 (https://github.com/lunethosdev-eng/nali)", Accept: "application/json" },
      signal: AbortSignal.timeout(9000),
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

function text(value: unknown): string {
  if (Array.isArray(value)) return value.map(text).filter(Boolean).join(", ");
  return typeof value === "string" || typeof value === "number" ? String(value).trim() : "";
}

function hasOpenLicense(metadata: any): boolean {
  const license = `${text(metadata?.licenseurl)} ${text(metadata?.license)} ${text(metadata?.rights)}`.toLowerCase();
  return license.includes("creativecommons.org") || license.includes("public domain") || license.includes("cc0");
}

function audioFile(files: any[]): any | null {
  const candidates = files.filter((file) => {
    const name = text(file?.name).toLowerCase();
    const format = text(file?.format).toLowerCase();
    return !file?.private && !text(file?.source).toLowerCase().includes("metadata") &&
      (/\.(mp3|ogg|oga|flac|wav|m4a|aac|opus)$/i.test(name) || /mp3|ogg|flac|wave|m4a|aac|opus/.test(format));
  });
  const score = (file: any) => {
    const name = text(file?.name).toLowerCase();
    const format = text(file?.format).toLowerCase();
    return (name.endsWith(".mp3") || format.includes("mp3") ? 100 : 0) +
      (name.includes("128kbps") ? 20 : 0) +
      (name.includes("64kbps") ? 5 : 0) +
      (Number(file?.size ?? 0) > 0 ? 1 : 0);
  };
  candidates.sort((a, b) => score(b) - score(a));
  return candidates[0] ?? null;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") return Response.json({ error: "method_not_allowed" }, { status: 405, headers: CORS });
  try {
    const body = await request.json();
    const query = String(body?.query ?? "").trim().slice(0, 100);
    const limit = Math.max(1, Math.min(20, Number(body?.limit) || 12));
    if (query.length < 2) return Response.json({ results: [] }, { headers: CORS });

    const safe = query.replace(/[+\-!(){}\[\]^"~*?:\\/]/g, " ").replace(/\s+/g, " ").trim();
    const searchUrl = new URL("https://archive.org/advancedsearch.php");
    searchUrl.searchParams.set("q", `mediatype:audio AND (title:("${safe}") OR creator:("${safe}"))`);
    searchUrl.searchParams.append("fl[]", "identifier");
    searchUrl.searchParams.append("fl[]", "title");
    searchUrl.searchParams.append("fl[]", "creator");
    searchUrl.searchParams.set("rows", String(Math.min(30, limit * 2)));
    searchUrl.searchParams.set("output", "json");
    searchUrl.searchParams.append("sort[]", "downloads desc");

    const search = await jsonGet(searchUrl.toString());
    const docs = Array.isArray(search?.response?.docs) ? search.response.docs : [];
    const metadataRows = await Promise.all(docs.slice(0, limit * 2).map(async (doc: any) => {
      const identifier = text(doc?.identifier);
      if (!identifier) return null;
      const payload = await jsonGet(`https://archive.org/metadata/${encodeURIComponent(identifier)}`);
      const metadata = payload?.metadata ?? {};
      if (!hasOpenLicense(metadata)) return null;
      const file = audioFile(Array.isArray(payload?.files) ? payload.files : []);
      if (!file) return null;
      const fileName = text(file.name);
      if (!fileName) return null;
      const creator = text(metadata.creator ?? doc.creator) || "Internet Archive";
      const title = text(metadata.title ?? doc.title) || "Untitled recording";
      const seconds = Number.parseFloat(text(file.length)) || 0;
      return {
        id: `ia_${identifier}`,
        provider: "internet_archive",
        source: "internet_archive",
        title,
        artist: creator,
        album: "Internet Archive",
        cover_url: `https://archive.org/services/img/${encodeURIComponent(identifier)}`,
        audio_url: `https://archive.org/download/${encodeURIComponent(identifier)}/${fileName.split("/").map(encodeURIComponent).join("/")}`,
        permalink_url: `https://archive.org/details/${encodeURIComponent(identifier)}`,
        duration: seconds,
        duration_seconds: seconds,
        license: text(metadata.licenseurl ?? metadata.license ?? metadata.rights),
        downloadable: false,
      };
    }));
    const results = metadataRows.filter(Boolean).slice(0, limit);
    return Response.json({ results, count: results.length, provider: "internet_archive" }, {
      headers: { ...CORS, "Cache-Control": "private, max-age=60" },
    });
  } catch (error) {
    console.error("internet-archive-catalog:", error);
    return Response.json({ error: "archive_search_failed", detail: String(error).slice(0, 180), results: [] }, {
      status: 502,
      headers: CORS,
    });
  }
});
