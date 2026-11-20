import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors });
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';
  if (!token) return new Response(JSON.stringify({ error: 'Missing bearer token' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return new Response(JSON.stringify({ error: 'Server configuration missing' }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } });

  // Validate the caller JWT against Auth before using admin privileges.
  const caller = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false }, global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: authData, error: authError } = await caller.auth.getUser(token);
  const user = authData.user;
  if (authError || !user) return new Response(JSON.stringify({ error: 'Invalid session' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });
  // Enforce recent reauthentication server-side (client prompts alone are not security).
  try {
    const encoded = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = encoded.padEnd(Math.ceil(encoded.length / 4) * 4, '=');
    const payload = JSON.parse(atob(padded));
    const authTime = Number(payload.auth_time);
    const now = Math.floor(Date.now() / 1000);
    if (!Number.isFinite(authTime) || now - authTime > 300 || authTime > now + 30) {
      return new Response(JSON.stringify({ error: 'Recent reauthentication required (within 5 minutes).' }), { status: 403, headers: { ...cors, 'Content-Type': 'application/json' } });
    }
  } catch {
    return new Response(JSON.stringify({ error: 'Unable to verify authentication time.' }), { status: 401, headers: { ...cors, 'Content-Type': 'application/json' } });
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  // Clean known profile media paths in the existing avatars bucket. Other data
  // cleanup must be completed through audited foreign-key cascades/migrations.
  async function collectFiles(bucket: string, folder: string): Promise<string[]> {
    const { data, error } = await admin.storage.from(bucket).list(folder, { limit: 1000 });
    if (error) throw error;
    const paths: string[] = [];
    for (const entry of data ?? []) {
      const full = `${folder}/${entry.name}`;
      if (entry.id === null) paths.push(...await collectFiles(bucket, full));
      else paths.push(full);
    }
    return paths;
  }
  try {
    const mediaPaths = [
      ...await collectFiles('avatars', `avatars/${user.id}`),
      ...await collectFiles('avatars', `banners/${user.id}`),
      ...await collectFiles('avatars', `playlist_covers/${user.id}`),
    ];
    if (mediaPaths.length) {
      const { error: storageError } = await admin.storage.from('avatars').remove(mediaPaths);
      if (storageError) throw storageError;
    }
    // Remove known user-owned rows in dependency order. Playlist child rows are
    // deleted by playlist IDs because playlist_songs has no user_id in the client schema.
    const { data: ownedPlaylists, error: playlistReadError } = await admin.from('playlists').select('id').eq('user_id', user.id);
    if (playlistReadError) throw playlistReadError;
    const playlistIds = (ownedPlaylists ?? []).map((row) => row.id).filter((id) => id != null);
    if (playlistIds.length) {
      const { error: childError } = await admin.from('playlist_songs').delete().in('playlist_id', playlistIds);
      if (childError) throw childError;
      const { error: playlistError } = await admin.from('playlists').delete().eq('user_id', user.id);
      if (playlistError) throw playlistError;
    }
    const { error: followError } = await admin.from('artist_follows').delete().eq('user_id', user.id);
    if (followError) throw followError;
    const { error: profileError } = await admin.from('profiles').delete().eq('id', user.id);
    if (profileError) throw profileError;
    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) throw deleteError;
    return new Response(JSON.stringify({ deleted: true, userId: user.id, cleanup: ['avatars/banners/playlist_covers user folders', 'playlist_songs rows', 'playlists rows', 'artist_follows rows', 'profiles row', 'auth user'] }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } });
  } catch (e) {
    console.error('delete-account partial failure', { userId: user.id, message: String(e) });
    return new Response(JSON.stringify({ error: 'Account deletion could not complete safely. No success was reported.', detail: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } });
  }
});
