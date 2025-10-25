#!/usr/bin/env node
/**
 * Yelp JSON → Supabase upsert
 *
 * Reads data/yelp_halal.json (produced by yelp_halal_fetch.js) and upserts rows into
 * Supabase table `place` using PostgREST with on_conflict=source,external_id.
 *
 * Usage:
 *   node scripts/yelp_ingest.js \
 *     --file=data/yelp_halal.json \
 *     --supabaseUrl=$SUPABASE_URL \
 *     --serviceKey=$SUPABASE_SERVICE_ROLE_KEY \
 *     [--batchSize=400] [--skipClosed=true]
 */

const fs = require('fs');

function normalizeName(name) {
  return name
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]/g, '');
}

const forcedFullyHalalPrefixes = [
  'affys',
  'affysgrill',
  'atomicwings',
  'fevyschicken',
  'nurthai',
  'halalmunchies',
  'pattanianthai',
  'melindashalalmeatmarket',
  'bakhterhalalfood',
  'zatar',
  'birdieshotchicken',
  'marrakechrestaurant',
  'afghankabab',
  'terryandyaki',
  'shawarmaspot',
  'duzan',
  'kababish',
  'momocrave'
];

function parseArgs() {
  const args = new Map();
  for (const raw of process.argv.slice(2)) {
    const [k, v] = raw.split('=');
    if (!v) continue;
    args.set(k.replace(/^--/, ''), v);
  }
  const file = args.get('file') || 'data/yelp_halal.json';
  const SUPABASE_URL = args.get('supabaseUrl') || process.env.SUPABASE_URL;
  const SERVICE_KEY = args.get('serviceKey') || process.env.SUPABASE_SERVICE_ROLE_KEY;
  const batchSize = Math.max(50, Math.min(parseInt(args.get('batchSize') || '400', 10), 800));
  const skipClosed = /^true$/i.test(args.get('skipClosed') || 'true');
  if (!SUPABASE_URL || !SERVICE_KEY) {
    throw new Error('Provide --supabaseUrl and --serviceKey (service role), or set SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY');
  }
  return { file, SUPABASE_URL, SERVICE_KEY, batchSize, skipClosed };
}

function mapRow(item) {
  if (!item || !item.id) return null;
  const lat = item.latitude;
  const lon = item.longitude;
  if (typeof lat !== 'number' || typeof lon !== 'number') return null;
  const note = typeof item.note === 'string' ? item.note.trim() : null;

  const address = (item.address || '').trim();
  const match = String(item.match || '').toLowerCase();
  const normalized = normalizeName(item.name || '');
  const forcedOnly = forcedFullyHalalPrefixes.some(prefix => normalized.startsWith(prefix));
  const halalStatus = forcedOnly || match.includes('category') ? 'only' : 'yes';
  const rating = typeof item.rating === 'number' ? item.rating : null;
  const ratingCount = typeof item.review_count === 'number' ? item.review_count : null;
  const confidence = 0.7; // heuristic default

  return {
    external_id: `yelp:${item.id}`,
    source: 'yelp',
    name: item.name || 'Yelp Place',
    category: 'restaurant',
    lat,
    lon,
    address: address.length ? address : null,
    halal_status: halalStatus,
    rating: rating,
    rating_count: ratingCount,
    confidence: confidence,
    note: note && note.length ? note : null,
    source_raw: { url: item.url || null, categories: item.categories || [], match: item.match || null },
    status: 'published',
  };
}

async function upsertBatch(SUPABASE_URL, SERVICE_KEY, rows) {
  const endpoint = `${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place?on_conflict=source,external_id`;
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
    throw new Error(`Supabase upsert failed ${resp.status}: ${text}`);
  }
  return await resp.json();
}

(async function main() {
  const { file, SUPABASE_URL, SERVICE_KEY, batchSize, skipClosed } = parseArgs();
  const json = JSON.parse(fs.readFileSync(file, 'utf8'));
  const items = Array.isArray(json.items) ? json.items : [];
  console.log(`Loaded ${items.length} Yelp items from ${file}`);

  const filtered = items.filter(it => {
    if (skipClosed && it.is_closed) return false;
    return typeof it.latitude === 'number' && typeof it.longitude === 'number';
  });
  console.log(`Preparing ${filtered.length} items for upsert (skipClosed=${skipClosed})`);

  const rows = filtered.map(mapRow).filter(Boolean);
  let inserted = 0;
  for (let i = 0; i < rows.length; i += batchSize) {
    const slice = rows.slice(i, i + batchSize);
    const res = await upsertBatch(SUPABASE_URL, SERVICE_KEY, slice);
    inserted += Array.isArray(res) ? res.length : 0;
    console.log(`Upserted batch ${Math.floor(i / batchSize) + 1}: ${slice.length} rows (total returned: ${inserted})`);
  }
  console.log('Done upserting Yelp rows.');
})();
