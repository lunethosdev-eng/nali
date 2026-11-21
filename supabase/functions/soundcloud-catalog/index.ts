const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
let tokenCache: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  if (tokenCache && tokenCache.expiresAt > Date.now() + 60_000) return tokenCache.value;
  const clientId = Deno.env.get('SOUNDCLOUD_CLIENT_ID');
  const clientSecret = Deno.env.get('SOUNDCLOUD_CLIENT_SECRET');
  if (!clientId || !clientSecret) throw new Error('SoundCloud credentials are not configured');
  const basic = btoa(`${clientId}:${clientSecret}`);
  const response = await fetch('https://secure.soundcloud.com/oauth/token', {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${basic}`,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    },
    body: new URLSearchParams({ grant_type: 'client_credentials' }),
  });
  if (!response.ok) throw new Error(`SoundCloud OAuth ${response.status}`);
  const data = await response.json();
  tokenCache = { value: data.access_token, expiresAt: Date.now() + Number(data.expires_in ?? 3600) * 1000 };
  return tokenCache.value;
}

const streamWindows = new Map<string, { started: number; count: number }>();

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const url = new URL(req.url);
  const action = url.searchParams.get('action');

  // Public, playable SoundCloud tracks only. The edge function resolves the
  // authenticated API stream and redirects to SoundCloud's CDN transcoding URL.
  if (req.method === 'GET' && action === 'stream') {
    const id = url.searchParams.get('id') ?? '';
    if (!/^\d+$/.test(id)) return new Response('Invalid track id', { status: 400 });
    const ip = req.headers.get('cf-connecting-ip') ?? req.headers.get('x-forwarded-for') ?? 'unknown';
    const now = Date.now();
    const window = streamWindows.get(ip);
    if (!window || now - window.started > 60_000) {
      streamWindows.set(ip, { started: now, count: 1 });
    } else {
      window.count += 1;
      if (window.count > 45) return new Response('Rate limit exceeded', { status: 429 });
    }
    try {
      const token = await accessToken();
      const upstream = await fetch(`https://api.soundcloud.com/tracks/${id}/stream`, {
        headers: { Authorization: `OAuth ${token}`, Accept: 'application/json' },
        redirect: 'manual',
      });
      const location = upstream.headers.get('location');
      if ((upstream.status === 301 || upstream.status === 302 || upstream.status === 303 || upstream.status === 307 || upstream.status === 308) && location) {
        return new Response(null, {
          status: 302,
          headers: { ...cors, Location: location, 'Cache-Control': 'private, max-age=120' },
        });
      }
      return new Response('SoundCloud did not provide a playable stream', { status: 404, headers: cors });
    } catch (error) {
      return new Response(`SoundCloud stream error: ${String(error)}`, { status: 502, headers: cors });
    }
  }

  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors });
  const auth = req.headers.get('Authorization') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!jwt || !anon || !supabaseUrl) return Response.json({ error: 'Unauthorized' }, { status: 401, headers: cors });
  const verify = await fetch(`${supabaseUrl}/auth/v1/user`, { headers: { apikey: anon, Authorization: `Bearer ${jwt}` } });
  if (!verify.ok) return Response.json({ error: 'Unauthorized' }, { status: 401, headers: cors });
  let body: { action?: string; query?: string; limit?: number };
  try { body = await req.json(); } catch { return Response.json({ error: 'Invalid JSON' }, { status: 400, headers: cors }); }
  const query = (body.query ?? '').trim();
  if (body.action !== 'search' || query.length < 2 || query.length > 100) {
    return Response.json({ error: 'Invalid search request' }, { status: 400, headers: cors });
  }
  try {
    const token = await accessToken();
    const endpoint = new URL('https://api.soundcloud.com/tracks');
    endpoint.searchParams.set('q', query);
    endpoint.searchParams.set('limit', String(Math.max(1, Math.min(30, Number(body.limit ?? 20)))));
    endpoint.searchParams.set('access', 'playable');
    const upstream = await fetch(endpoint, { headers: { Authorization: `OAuth ${token}`, Accept: 'application/json' } });
    if (!upstream.ok) return Response.json({ error: `SoundCloud API ${upstream.status}` }, { status: 502, headers: cors });
    const rows = await upstream.json();
    const results = (Array.isArray(rows) ? rows : []).map((track: Record<string, any>) => ({
      id: track.id,
      title: track.title,
      duration: track.duration,
      artwork_url: track.artwork_url,
      permalink_url: track.permalink_url,
      user: { username: track.user?.username ?? 'SoundCloud' },
    }));
    return Response.json({ results }, { headers: { ...cors, 'Cache-Control': 'private, max-age=30' } });
  } catch (error) {
    return Response.json({ error: String(error) }, { status: 502, headers: cors });
  }
});
