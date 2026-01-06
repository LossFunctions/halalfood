#!/usr/bin/env node
/**
 * Hydrate serves_alcohol for existing Yelp places using Yelp Business Details.
 *
 * Usage:
 *   YELP_API_KEY=... node scripts/yelp_hydrate_alcohol.js \
 *     --supabaseUrl=$SUPABASE_URL \
 *     --serviceKey=$SUPABASE_SERVICE_ROLE_KEY \
 *     [--limit=25] [--delayMs=250] [--minReviews=1] [--dryRun=true] [--updateSourceRaw=false]
 */

function parseArgs() {
  const args = new Map();
  for (const raw of process.argv.slice(2)) {
    const [k, v] = raw.split('=');
    if (!v) continue;
    args.set(k.replace(/^--/, ''), v);
  }

  const SUPABASE_URL = args.get('supabaseUrl') || process.env.SUPABASE_URL;
  const SERVICE_KEY = args.get('serviceKey') || process.env.SUPABASE_SERVICE_ROLE_KEY;
  const YELP_API_KEY = args.get('apiKey') || process.env.YELP_API_KEY;
  const limit = Math.max(1, parseInt(args.get('limit') || '25', 10));
  const delayMs = Math.max(0, parseInt(args.get('delayMs') || '250', 10));
  const minReviews = Math.max(0, parseInt(args.get('minReviews') || '1', 10));
  const dryRun = /^true$/i.test(args.get('dryRun') || 'false');
  const updateSourceRaw = /^true$/i.test(args.get('updateSourceRaw') || 'false');

  if (!SUPABASE_URL || !SERVICE_KEY || !YELP_API_KEY) {
    throw new Error('Provide --supabaseUrl, --serviceKey, and --apiKey (or set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, YELP_API_KEY).');
  }

  return {
    SUPABASE_URL,
    SERVICE_KEY,
    YELP_API_KEY,
    limit,
    delayMs,
    minReviews,
    dryRun,
    updateSourceRaw
  };
}

async function fetchPaged(url, headers, pageSize = 1000, rangeUnit = 'items', maxRows = null) {
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
    if (maxRows && results.length >= maxRows) {
      return results.slice(0, maxRows);
    }
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

function mergeSourceRaw(existing, attributes) {
  const base = existing && typeof existing === 'object' && !Array.isArray(existing) ? { ...existing } : {};
  if (attributes && typeof attributes === 'object') {
    base.attributes = { ...attributes };
  }
  return base;
}

async function fetchYelpDetails(apiKey, yelpId) {
  const url = `https://api.yelp.com/v3/businesses/${encodeURIComponent(yelpId)}`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${apiKey}` } });
  if (!resp.ok) {
    const text = await resp.text();
    const error = new Error(`Yelp error ${resp.status}: ${text}`);
    error.status = resp.status;
    throw error;
  }
  return await resp.json();
}

async function updatePlace(SUPABASE_URL, SERVICE_KEY, placeId, payload) {
  const endpoint = `${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place?id=eq.${placeId}`;
  const resp = await fetch(endpoint, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(payload),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Supabase update failed ${resp.status}: ${text}`);
  }
  return await resp.json();
}

function sleep(ms) {
  if (!ms) return Promise.resolve();
  return new Promise(resolve => setTimeout(resolve, ms));
}

(async function main() {
  const {
    SUPABASE_URL,
    SERVICE_KEY,
    YELP_API_KEY,
    limit,
    delayMs,
    minReviews,
    dryRun,
    updateSourceRaw
  } = parseArgs();

  const headers = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };
  const placeUrl = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place`);
  const selectFields = ['id', 'name', 'external_id', 'serves_alcohol'];
  if (updateSourceRaw) selectFields.push('source_raw');
  placeUrl.searchParams.set('select', selectFields.join(','));
  placeUrl.searchParams.set('source', 'eq.yelp');
  placeUrl.searchParams.set('status', 'eq.published');
  placeUrl.searchParams.set('serves_alcohol', 'is.null');
  if (minReviews > 0) {
    placeUrl.searchParams.set('rating_count', `gte.${minReviews}`);
  }
  placeUrl.searchParams.set('order', 'rating_count.desc.nullslast,id');

  const pageSize = Math.min(1000, limit);
  const candidates = await fetchPaged(placeUrl, headers, pageSize, 'items', limit);
  console.log(`Loaded ${candidates.length} candidate Yelp places missing serves_alcohol (limit=${limit}).`);

  let detailsCalls = 0;
  let updated = 0;
  let skippedNoYelpId = 0;
  let skippedNoAlcoholInfo = 0;
  let skippedUnavailable = 0;
  let failures = 0;

  for (const place of candidates) {
    const yelpId = yelpIdFromExternal(place.external_id);
    if (!yelpId) {
      skippedNoYelpId += 1;
      continue;
    }

    let details;
    try {
      details = await fetchYelpDetails(YELP_API_KEY, yelpId);
      detailsCalls += 1;
    } catch (error) {
      const status = error && typeof error === 'object' ? error.status : null;
      if (status === 403) {
        skippedUnavailable += 1;
        console.warn(`Yelp unavailable for ${place.name || place.id} (${yelpId}).`);
        await sleep(delayMs);
        continue;
      }
      failures += 1;
      console.warn(`Failed to fetch Yelp details for ${place.name || place.id} (${yelpId}): ${error.message}`);
      if (status === 429) {
        console.warn('Rate limit hit. Stopping early to avoid further calls.');
        break;
      }
      await sleep(delayMs);
      continue;
    }

    const servesAlcohol = servesAlcoholFromAttributes(details.attributes);
    if (servesAlcohol === null) {
      skippedNoAlcoholInfo += 1;
      await sleep(delayMs);
      continue;
    }

    const payload = { serves_alcohol: servesAlcohol };
    if (updateSourceRaw) {
      payload.source_raw = mergeSourceRaw(place.source_raw, details.attributes);
    }

    if (dryRun) {
      console.log(`[dry-run] ${place.name || place.id} (${yelpId}) serves_alcohol=${servesAlcohol}`);
      updated += 1;
    } else {
      await updatePlace(SUPABASE_URL, SERVICE_KEY, place.id, payload);
      console.log(`Updated ${place.name || place.id} (${yelpId}) serves_alcohol=${servesAlcohol}`);
      updated += 1;
    }

    await sleep(delayMs);
  }

  console.log('Done.');
  console.log(`Yelp detail calls: ${detailsCalls}`);
  console.log(`Updated rows: ${updated}`);
  console.log(`Skipped (no Yelp ID): ${skippedNoYelpId}`);
  console.log(`Skipped (no alcohol info): ${skippedNoAlcoholInfo}`);
  console.log(`Skipped (Yelp unavailable): ${skippedUnavailable}`);
  console.log(`Failures: ${failures}`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
