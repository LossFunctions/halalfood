#!/usr/bin/env node
/**
 * List Yelp business IDs for Supabase places (source=yelp) that have no Yelp photos yet.
 * Writes one Yelp business id per line to an output file or stdout.
 *
 * Usage:
 *   node scripts/find_yelp_places_missing_photos.js \
 *     --supabaseUrl=$SUPABASE_URL \
 *     --serviceKey=$SUPABASE_SERVICE_ROLE_KEY \
 *     [--out=scripts/missing_yelp_photo_ids.txt]
 */

const fs = require('fs');

function parseArgs() {
  const args = new Map();
  for (const raw of process.argv.slice(2)) {
    const [k, v] = raw.split('=');
    if (!v) continue;
    args.set(k.replace(/^--/, ''), v);
  }
  const SUPABASE_URL = args.get('supabaseUrl') || process.env.SUPABASE_URL;
  const SERVICE_KEY = args.get('serviceKey') || process.env.SUPABASE_SERVICE_ROLE_KEY;
  const out = args.get('out') || '';
  if (!SUPABASE_URL || !SERVICE_KEY) throw new Error('Provide --supabaseUrl and --serviceKey');
  return { SUPABASE_URL, SERVICE_KEY, out };
}

async function fetchPaged(url, headers, pageSize = 1000, selectRangeUnit = 'items') {
  const results = [];
  let start = 0;
  while (true) {
    const end = start + pageSize - 1;
    const resp = await fetch(url, {
      headers: {
        ...headers,
        'Range-Unit': selectRangeUnit,
        'Range': `${start}-${end}`,
        'Prefer': 'count=exact'
      }
    });
    if (!resp.ok && resp.status !== 206) {
      const text = await resp.text();
      throw new Error(`Fetch failed ${resp.status}: ${text}`);
    }
    const page = await resp.json();
    results.push(...page);
    if (page.length < pageSize) break;
    start += pageSize;
  }
  return results;
}

function yelpIdFromExternal(ext) {
  if (!ext) return null;
  if (ext.startsWith('yelp:')) return ext.slice(5);
  return null;
}

(async function main() {
  const { SUPABASE_URL, SERVICE_KEY, out } = parseArgs();
  const headers = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };

  // 1) All Yelp places (published)
  const placeUrl = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place`);
  placeUrl.searchParams.set('select', 'id,external_id');
  placeUrl.searchParams.set('source', 'eq.yelp');
  placeUrl.searchParams.set('status', 'eq.published');
  const yelpPlaces = await fetchPaged(placeUrl, headers);

  // 2) Distinct place_ids that already have Yelp photos
  const photoUrl = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place_photo`);
  photoUrl.searchParams.set('select', 'place_id');
  photoUrl.searchParams.set('src', 'eq.yelp');
  const yelpPhotos = await fetchPaged(photoUrl, headers);
  const withPhotos = new Set(yelpPhotos.map(r => r.place_id));

  const missing = [];
  for (const p of yelpPlaces) {
    if (!withPhotos.has(p.id)) {
      const yid = yelpIdFromExternal(p.external_id);
      if (yid) missing.push(yid);
    }
  }

  if (out) {
    fs.writeFileSync(out, missing.join('\n') + (missing.length ? '\n' : ''));
    console.log(`Wrote ${missing.length} Yelp ids to ${out}`);
  } else {
    console.log(missing.join('\n'));
  }
})().catch((e) => { console.error(e); process.exit(1); });

