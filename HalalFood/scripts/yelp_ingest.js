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
 *     [--batchSize=400] [--skipClosed=true] [--allowHalalStatusUpdates=false] [--dryRun=false]
 */

const fs = require('fs');
const { resolveDisplayLocation } = require('./lib/display_location');

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
  // Kebabish variants — ensure KebabishQ and spelling variations are treated as fully halal
  'kababish',
  'kebabish',
  'kebabishq',
  'momocrave',
  // Request: Treat Guac Island as fully halal
  'guacisland',
  // Request: Treat Karachi Kabab Boiz as fully halal
  'karachikababboiz', 'karachikabab'
  ,
  // Request: Treat MOTW Coffee as fully halal
  'motwcoffee',
  // Request: Treat new additions as fully halal
  'periperigrillhouse',
  'gnocchibella',
  'filli',
  'sheikhsnburgers'
];

const nonHalalChainTokens = [
  'mcdonalds',
  'tacobell',
  'burgerking',
  'wendys',
  'kfc',
  'chipotle',
  'dominos',
  'pizzahut',
  'papajohns',
  'fiveguys',
  'whitecastle',
  'panerabread',
  'starbucks',
  'dunkin',
  'chickfila',
  'popeyes',
  'arbys',
  'jackinthebox',
  'sonicdrivein',
  'littlecaesars',
  'carlsjr',
  'hardees',
  'subway'
];

const alcoholCategorySignals = new Set([
  'bars',
  'beerbar',
  'cocktailbars',
  'sportsbars',
  'wine_bars',
  'pubs',
  'brewpubs',
  'breweries',
  'distilleries',
  'tiki_bars',
  'whiskeybars',
  'beer_and_wine',
  'irish_pubs',
  'hookah_bars'
]);

const alcoholNamePatterns = [
  /\bbar\b/i,
  /\bpub\b/i,
  /\btavern\b/i,
  /\bbrewery\b/i,
  /\bbrewpub\b/i,
  /\bbrewhouse\b/i,
  /\bwinery\b/i,
  /\bwine bar\b/i,
  /\balehouse\b/i,
  /\bspeakeasy\b/i,
  /\bcocktail\b/i,
  /\bdistillery\b/i
];

function clamp01(value) {
  if (value <= 0) return 0;
  if (value >= 1) return 1;
  return value;
}

function hasHalalSignal(normalizedName, categories) {
  if (normalizedName.includes('halal')) return true;
  if (!Array.isArray(categories)) return false;
  return categories.some(cat => String(cat || '').toLowerCase() === 'halal');
}

function isNonHalalChain(normalizedName) {
  if (!normalizedName) return false;
  return nonHalalChainTokens.some(token => normalizedName.includes(token));
}

function computeConfidence({ match, forcedOnly, halalStatus, normalizedName, categories, isBlacklisted }) {
  let confidence = 0.6;
  if (match.includes('category')) {
    confidence = 0.85;
  } else if (match.includes('manual')) {
    confidence = 0.8;
  } else if (match.includes('term')) {
    confidence = 0.6;
  }

  if (forcedOnly) {
    confidence = Math.max(confidence, 0.95);
  }
  if (hasHalalSignal(normalizedName, categories)) {
    confidence = Math.max(confidence, 0.9);
  }
  if (halalStatus === 'only') {
    confidence = Math.max(confidence, 0.8);
  }

  if (isBlacklisted) {
    confidence = halalStatus === 'no' ? Math.max(confidence, 0.9) : Math.min(confidence, 0.1);
  }

  return clamp01(confidence);
}

function detectServesAlcohol(name, categories) {
  const nameValue = String(name || '');
  for (const pattern of alcoholNamePatterns) {
    if (pattern.test(nameValue)) {
      return true;
    }
  }
  if (Array.isArray(categories)) {
    for (const raw of categories) {
      const value = String(raw || '').toLowerCase();
      if (alcoholCategorySignals.has(value)) {
        return true;
      }
    }
  }
  return null;
}

function servesAlcoholFromAttributes(attributes) {
  if (!attributes || typeof attributes !== 'object') return null;
  const raw = attributes.alcohol;
  if (typeof raw !== 'string' || !raw.trim()) return null;
  const normalized = raw.toLowerCase();
  if (normalized === 'none' || normalized === 'no' || normalized === 'false') {
    return false;
  }
  if (normalized === 'beer_and_wine' || normalized === 'full_bar') {
    return true;
  }
  return null;
}

async function fetchPaged(url, headers, pageSize = 1000, rangeUnit = 'items') {
  const results = [];
  let start = 0;
  while (true) {
    const end = start + pageSize - 1;
    const resp = await fetch(url, {
      headers: {
        ...headers,
        'Range-Unit': rangeUnit,
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

async function fetchExistingPlaceMeta(SUPABASE_URL, SERVICE_KEY) {
  const url = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place`);
  url.searchParams.set('select', 'external_id,halal_status,note,serves_alcohol');
  url.searchParams.set('source', 'eq.yelp');
  url.searchParams.set('status', 'not.eq.deleted');
  const headers = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };
  const rows = await fetchPaged(url, headers);
  const map = new Map();
  for (const row of rows) {
    if (!row || typeof row.external_id !== 'string') continue;
    map.set(row.external_id, {
      halal_status: typeof row.halal_status === 'string' ? row.halal_status : null,
      note: typeof row.note === 'string' && row.note.trim().length ? row.note.trim() : null,
      serves_alcohol: typeof row.serves_alcohol === 'boolean' ? row.serves_alcohol : null
    });
  }
  return map;
}

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
  const allowHalalStatusUpdates = /^true$/i.test(args.get('allowHalalStatusUpdates') || 'false');
  const dryRun = /^true$/i.test(args.get('dryRun') || 'false');
  if (!dryRun && (!SUPABASE_URL || !SERVICE_KEY)) {
    throw new Error('Provide --supabaseUrl and --serviceKey (service role), or set SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY');
  }
  return { file, SUPABASE_URL, SERVICE_KEY, batchSize, skipClosed, allowHalalStatusUpdates, dryRun };
}

function mapRow(item, existingMeta, allowHalalStatusUpdates) {
  if (!item || !item.id) return null;
  const lat = item.latitude;
  const lon = item.longitude;
  if (typeof lat !== 'number' || typeof lon !== 'number') return null;
  const note = typeof item.note === 'string' ? item.note.trim() : null;

  const address = (item.address || '').trim();
  const match = String(item.match || '').toLowerCase();
  const normalized = normalizeName(item.name || '');
  const forcedOnly = forcedFullyHalalPrefixes.some(prefix => normalized.startsWith(prefix));
  let halalStatus = forcedOnly || match.includes('category') ? 'only' : 'yes';
  const isBlacklisted = isNonHalalChain(normalized);
  if (isBlacklisted && allowHalalStatusUpdates) {
    halalStatus = 'no';
  }
  const rating = typeof item.rating === 'number' ? item.rating : null;
  const ratingCount = typeof item.review_count === 'number' ? item.review_count : null;
  const categories = Array.isArray(item.categories) ? item.categories : [];
  const alcoholFromAttributes = servesAlcoholFromAttributes(item.attributes);
  let servesAlcohol = alcoholFromAttributes;
  if (servesAlcohol === null) {
    servesAlcohol = detectServesAlcohol(item.name, categories);
  }
  const displayLocation = resolveDisplayLocation({ address });
  const externalId = `yelp:${item.id}`;
  const existing = existingMeta.get(externalId) || null;
  const sourceRaw = {
    url: item.url || null,
    categories: categories,
    match: item.match || null
  };
  if (item.attributes && typeof item.attributes === 'object') {
    sourceRaw.attributes = item.attributes;
  }
  if (note && note.length) {
    sourceRaw.note = note;
  }
  if (displayLocation) {
    sourceRaw.display_location = displayLocation;
  }

  if (existing && existing.halal_status && !allowHalalStatusUpdates) {
    halalStatus = existing.halal_status;
  }

  const confidence = computeConfidence({
    match,
    forcedOnly,
    halalStatus,
    normalizedName: normalized,
    categories,
    isBlacklisted
  });

  if (existing && typeof existing.serves_alcohol === 'boolean') {
    servesAlcohol = existing.serves_alcohol;
  }

  const rowNote = existing?.note ?? (note && note.length ? note : null);

  const row = {
    external_id: externalId,
    source: 'yelp',
    name: item.name || 'Yelp Place',
    category: 'restaurant',
    lat,
    lon,
    address: address.length ? address : null,
    display_location: displayLocation || null,
    halal_status: halalStatus,
    rating: rating,
    rating_count: ratingCount,
    confidence: confidence,
    serves_alcohol: servesAlcohol ?? null,
    source_raw: sourceRaw,
    status: 'published',
    note: rowNote ?? null
  };

  return row;
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
  const { file, SUPABASE_URL, SERVICE_KEY, batchSize, skipClosed, allowHalalStatusUpdates, dryRun } = parseArgs();
  const json = JSON.parse(fs.readFileSync(file, 'utf8'));
  const items = Array.isArray(json.items) ? json.items : [];
  console.log(`Loaded ${items.length} Yelp items from ${file}`);

  let existingMeta = new Map();
  if (SUPABASE_URL && SERVICE_KEY) {
    console.log('Fetching existing Supabase Yelp place metadata…');
    existingMeta = await fetchExistingPlaceMeta(SUPABASE_URL, SERVICE_KEY);
    console.log(`Loaded ${existingMeta.size} existing Yelp place records for note/halal status preservation`);
  } else {
    console.log('Supabase credentials not provided; skipping existing metadata lookup.');
  }

  const filtered = items.filter(it => {
    if (skipClosed && it.is_closed) return false;
    return typeof it.latitude === 'number' && typeof it.longitude === 'number';
  });
  console.log(`Preparing ${filtered.length} items for upsert (skipClosed=${skipClosed})`);

  const rows = filtered.map(item => mapRow(item, existingMeta, allowHalalStatusUpdates)).filter(Boolean);
  if (dryRun) {
    const previewCount = Math.min(rows.length, 5);
    console.log(`Dry run enabled. Previewing ${previewCount} row(s).`);
    console.log(JSON.stringify(rows.slice(0, previewCount), null, 2));
    console.log('Dry run complete. No Supabase writes performed.');
    return;
  }
  let inserted = 0;
  for (let i = 0; i < rows.length; i += batchSize) {
    const slice = rows.slice(i, i + batchSize);
    const res = await upsertBatch(SUPABASE_URL, SERVICE_KEY, slice);
    inserted += Array.isArray(res) ? res.length : 0;
    console.log(`Upserted batch ${Math.floor(i / batchSize) + 1}: ${slice.length} rows (total returned: ${inserted})`);
  }
  console.log('Done upserting Yelp rows.');
})();
