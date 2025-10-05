#!/usr/bin/env node
/**
 * Fetch business photos from Yelp Fusion for existing Yelp places in Supabase and store URLs.
 *
 * IMPORTANT: Yelp Fusion terms generally do not allow downloading/re-hosting photos. This script stores
 * only the photo URLs and attribution in a separate `place_photo` table. Display with proper attribution.
 *
 * Usage:
 *   YELP_API_KEY=... node scripts/yelp_photos_ingest.js \
 *     --supabaseUrl=$SUPABASE_URL --serviceKey=$SUPABASE_SERVICE_ROLE_KEY \
 *     [--limit=0] [--delayMs=200]
 */

const fetch = globalThis.fetch;

function parseArgs() {
  const args = new Map();
  for (const raw of process.argv.slice(2)) {
    const [k, v] = raw.split('=');
    if (!v) continue;
    args.set(k.replace(/^--/, ''), v);
  }
  const apiKey = process.env.YELP_API_KEY;
  const SUPABASE_URL = args.get('supabaseUrl') || process.env.SUPABASE_URL;
  const SERVICE_KEY = args.get('serviceKey') || process.env.SUPABASE_SERVICE_ROLE_KEY;
  const limit = parseInt(args.get('limit') || '0', 10); // 0 = no limit
  const delayMs = Math.max(0, Math.min(parseInt(args.get('delayMs') || '200', 10), 2000));
  const idParam = args.get('id'); // accepts last --id=..., plus multi collect below
  const idsFile = args.get('idsFile');
  const maxPhotos = Math.max(1, Math.min(parseInt(args.get('maxPhotos') || '12', 10), 24));
  if (!apiKey) throw new Error('Set YELP_API_KEY');
  if (!SUPABASE_URL || !SERVICE_KEY) throw new Error('Provide --supabaseUrl/--serviceKey or set env vars');
  const manualIDs = new Set();
  // collect all repeated --id=... flags
  for (const raw of process.argv.slice(2)) {
    if (raw.startsWith('--id=')) {
      const val = raw.slice(5);
      const id = parseId(val);
      if (id) manualIDs.add(id);
    }
  }
  if (idParam) { const id = parseId(idParam); if (id) manualIDs.add(id); }
  if (idsFile) {
    try {
      const text = require('fs').readFileSync(idsFile, 'utf8');
      for (const line of text.split(/\r?\n/)) {
        const trimmed = line.split('#')[0].trim();
        if (!trimmed) continue;
        manualIDs.add(parseId(trimmed));
      }
    } catch {}
  }
  return { apiKey, SUPABASE_URL, SERVICE_KEY, limit, delayMs, manualIDs, maxPhotos };
}

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function listYelpPlaces(SUPABASE_URL, SERVICE_KEY, limit) {
  let url = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place`);
  url.searchParams.set('select', 'id,external_id');
  url.searchParams.set('source', 'eq.yelp');
  url.searchParams.set('status', 'eq.published');
  if (limit > 0) url.searchParams.set('limit', String(limit));
  const resp = await fetch(url, { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } });
  if (!resp.ok) throw new Error(`List places failed ${resp.status}`);
  return await resp.json();
}

function yelpIdFromExternal(external_id) {
  return external_id && external_id.startsWith('yelp:') ? external_id.slice(5) : null;
}

async function getDetails(apiKey, yelpId) {
  const url = `https://api.yelp.com/v3/businesses/${encodeURIComponent(yelpId)}`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${apiKey}` } });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Yelp details ${resp.status} for ${yelpId}: ${text}`);
  }
  return await resp.json();
}

async function getPhotosEndpoint(apiKey, yelpId) {
  const url = `https://api.yelp.com/v3/businesses/${encodeURIComponent(yelpId)}/photos`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${apiKey}` } });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Yelp photos ${resp.status} for ${yelpId}: ${text}`);
  }
  return await resp.json();
}

function parseId(input) {
  if (!input) return null;
  if (/^https?:\/\//i.test(input)) {
    try {
      const u = new URL(input);
      const parts = u.pathname.split('/').filter(Boolean);
      const bizIdx = parts.findIndex(p => p.toLowerCase() === 'biz');
      if (bizIdx >= 0 && parts.length > bizIdx + 1) return parts[bizIdx + 1];
    } catch {}
    return null;
  }
  return input;
}

async function upsertPhotos(SUPABASE_URL, SERVICE_KEY, rows) {
  if (!rows.length) return;
  const endpoint = `${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place_photo`;
  const resp = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Prefer': 'return=representation,resolution=merge-duplicates',
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(rows),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Upsert photos failed ${resp.status}: ${text}`);
  }
  return await resp.json();
}

async function clearExisting(SUPABASE_URL, SERVICE_KEY, placeId, src) {
  const url = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place_photo`);
  url.searchParams.set('place_id', `eq.${placeId}`);
  url.searchParams.set('src', `eq.${src}`);
  const resp = await fetch(url, {
    method: 'DELETE',
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  });
  if (!resp.ok && resp.status !== 404) {
    const text = await resp.text();
    throw new Error(`Clear photos failed ${resp.status}: ${text}`);
  }
}

(async function main() {
  const { apiKey, SUPABASE_URL, SERVICE_KEY, limit, delayMs, manualIDs, maxPhotos } = parseArgs();
  let places = [];
  if (manualIDs.size) {
    // Create pseudo place list from manual IDs by looking up matching place rows
    console.log(`Processing manual Yelp ids: ${Array.from(manualIDs).join(', ')}`);
    for (const yid of manualIDs) {
      const ext = `yelp:${yid}`;
      const url = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place`);
      url.searchParams.set('select', 'id,external_id');
      url.searchParams.set('source', 'eq.yelp');
      url.searchParams.set('external_id', `eq.${ext}`);
      const resp = await fetch(url, { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } });
      if (resp.ok) {
        const rows = await resp.json();
        if (rows.length) places.push(rows[0]);
      }
      await sleep(delayMs);
    }
  } else {
    places = await listYelpPlaces(SUPABASE_URL, SERVICE_KEY, limit);
  }
  console.log(`Found ${places.length} Yelp places to process`);

  let totalPhotos = 0;
  for (const [idx, p] of places.entries()) {
    const yelpId = yelpIdFromExternal(p.external_id);
    if (!yelpId) continue;
    try {
      let urls = [];
      // Prefer the photos endpoint (often returns more photos); fall back to details
      try {
        const p = await getPhotosEndpoint(apiKey, yelpId);
        if (Array.isArray(p.photos) && p.photos.length) {
          urls = p.photos.map(ph => ph.url).filter(Boolean);
        }
      } catch (e) {
        // Fall back silently to details endpoint
      }
      if (!urls.length) {
        const d = await getDetails(apiKey, yelpId);
        urls = Array.isArray(d.photos) ? d.photos.slice() : [];
        if (d.image_url && !urls.includes(d.image_url)) urls.unshift(d.image_url);
      }
      const rows = urls.slice(0, maxPhotos).map((url, i) => ({
        place_id: p.id,
        src: 'yelp',
        external_id: `yelp:${yelpId}:${i}`,
        image_url: url,
        width: null,
        height: null,
        priority: i,
        attribution: 'Yelp',
      }));
      // Clear existing Yelp photos for this place to avoid duplicates
      await clearExisting(SUPABASE_URL, SERVICE_KEY, p.id, 'yelp');
      const res = await upsertPhotos(SUPABASE_URL, SERVICE_KEY, rows);
      totalPhotos += rows.length;
      if ((idx + 1) % 50 === 0) console.log(`Processed ${idx + 1}/${places.length} places…`);
    } catch (e) {
      console.warn(`Failed for ${yelpId}: ${e.message}`);
    }
    await sleep(delayMs);
  }
  console.log(`Done. Upserted photo URL rows: ${totalPhotos}`);
})();
