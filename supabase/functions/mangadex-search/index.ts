import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => Response.json(body, {
  status, headers: { ...CORS, "Cache-Control": "public, max-age=90" },
});

async function aniListFallback(query: string, limit: number) {
  const graphql = `query ($search: String, $perPage: Int) {
    Page(perPage: $perPage) {
      media(search: $search, type: MANGA, sort: SEARCH_MATCH) {
        id title { romaji english native } coverImage { large }
      }
    }
  }`;
  const response = await fetch("https://graphql.anilist.co", {
    method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ query: graphql, variables: { search: query, perPage: limit } }),
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) throw new Error(`AniList HTTP ${response.status}`);
  const payload = await response.json();
  const rows = payload?.data?.Page?.media;
  if (!Array.isArray(rows)) throw new Error("AniList returned no manga list");
  return rows.map((row: Record<string, unknown>) => {
    const titles = row.title && typeof row.title === "object" ? row.title as Record<string, unknown> : {};
    const cover = row.coverImage && typeof row.coverImage === "object" ? row.coverImage as Record<string, unknown> : {};
    return {
      id: `anilist:${row.id}`,
      attributes: { title: { en: titles.english ?? titles.romaji, romaji: titles.romaji }, coverUrl: cover.large ?? null },
      relationships: [],
    };
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const body = await request.json();
    const query = String(body?.query ?? "").trim();
    const limit = Math.max(1, Math.min(32, Number(body?.limit) || 12));
    if (query.length < 2 || query.length > 100) return json({ error: "invalid_query" }, 400);

    const url = new URL("https://api.mangadex.org/manga");
    url.searchParams.set("title", query);
    url.searchParams.set("limit", String(limit));
    url.searchParams.append("includes[]", "cover_art");
    url.searchParams.set("order[relevance]", "desc");
    url.searchParams.append("contentRating[]", "safe");

    // MangaDex may reject cloud egress IPs with 403. Retry once with a normal
    // browser UA; if still blocked, provide an explicit AniList fallback.
    let upstream = await fetch(url, {
      headers: { Accept: "application/json", "User-Agent": "Nali/1.1 (https://github.com/lunethosdev-eng/nali)" },
      signal: AbortSignal.timeout(12000),
    });
    if (upstream.status === 403 || upstream.status === 429) {
      upstream = await fetch(url, {
        headers: { Accept: "application/json", "User-Agent": "Mozilla/5.0 (compatible; Nali/1.1)" },
        signal: AbortSignal.timeout(12000),
      });
    }
    if (upstream.ok) {
      const payload = await upstream.json();
      if (Array.isArray(payload?.data)) return json({ ...payload, provider: "mangadex" });
    }
    const fallback = await aniListFallback(query, limit);
    return json({ data: fallback, provider: "anilist_fallback", warning: `MangaDex HTTP ${upstream.status}; se usó AniList.` });
  } catch (error) {
    return json({ error: "manga_search_unavailable", detail: String(error).slice(0, 180) }, 502);
  }
});
