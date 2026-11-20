import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors });
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  const url = Deno.env.get('SUPABASE_URL'); const anon = Deno.env.get('SUPABASE_ANON_KEY');
  if (!token || !url || !anon) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });
  const client = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false }, global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: authData, error: authError } = await client.auth.getUser(token);
  if (authError || !authData.user) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });
  let body: { query?: string; limit?: number };
  try { body = await req.json(); } catch { return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } }); }
  const query = (body.query ?? '').trim(); const limit = Math.max(1, Math.min(32, Number(body.limit ?? 12)));
  if (query.length < 2 || query.length > 100) return new Response(JSON.stringify({ error: 'Query length invalid' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } });
  const mangaUrl = new URL('https://api.mangadex.org/manga');
  mangaUrl.searchParams.set('title', query); mangaUrl.searchParams.set('limit', String(limit)); mangaUrl.searchParams.append('includes[]', 'cover_art'); mangaUrl.searchParams.set('order[relevance]', 'desc'); mangaUrl.searchParams.append('contentRating[]', 'safe');
  const upstream = await fetch(mangaUrl, { headers: { Accept: 'application/json', 'User-Agent': 'Nali/1.0 (https://github.com/lunethosdev-eng/Nali)' } });
  if (!upstream.ok) return new Response(JSON.stringify({ error: `MangaDex upstream ${upstream.status}` }), { status: 502, headers: { ...cors, 'Content-Type': 'application/json' } });
  const data = await upstream.json();
  return new Response(JSON.stringify(data), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } });
});
