#!/usr/bin/env node
/**
 * Yelp halal fetcher
 *
 * Fetches businesses in the Yelp Fusion API with category=halal for one or more bounding boxes,
 * deduplicates by business id, and writes both JSON and Markdown summaries.
 *
 * Usage examples:
 *   node scripts/yelp_halal_fetch.js --apiKey=$YELP_API_KEY --bboxFile=overpass-bboxes.txt
 *   node scripts/yelp_halal_fetch.js --apiKey=$YELP_API_KEY --bbox=-74.26,40.47,-73.70,40.92 --label="NYC"
 *
 * Notes:
 *   - Yelp Business Search supports radius up to 40000m and max 50 results per request (offset up to 1000).
 *   - This script tiles each bbox with overlapping circles to cover the area while keeping request counts reasonable.
 */

const fs = require('fs');
const path = require('path');

function parseArgs() {
  const args = new Map();
  const multi = [];
  for (const raw of process.argv.slice(2)) {
    const [k, v] = raw.split('=');
    if (!v) continue;
    const key = k.replace(/^--/, '');
    if (key === 'bbox') { multi.push({ type: 'bbox', value: v }); continue; }
    if (key === 'label') { multi.push({ type: 'label', value: v }); continue; }
    args.set(key, v);
  }

  const apiKey = args.get('apiKey') || process.env.YELP_API_KEY;
  if (!apiKey) throw new Error('Provide --apiKey=... or set YELP_API_KEY');

  const boxes = [];
  const bboxFile = args.get('bboxFile');
  if (bboxFile) {
    const text = fs.readFileSync(bboxFile, 'utf8');
    for (const line of text.split(/\r?\n/)) {
      const trimmed = line.split('#')[0].trim();
      if (!trimmed) continue;
      const [coords, label] = trimmed.split('|').map(s => s.trim());
      const [west, south, east, north] = coords.split(',').map(Number);
      if ([west, south, east, north].some(n => Number.isNaN(n))) continue;
      boxes.push({ west, south, east, north, label: label || coords });
    }
  }

  // Allow a single inline bbox
  const inlineBbox = multi.find(e => e.type === 'bbox')?.value;
  if (inlineBbox) {
    const [west, south, east, north] = inlineBbox.split(',').map(Number);
    boxes.push({ west, south, east, north, label: (multi.find(e => e.type === 'label')?.value) || inlineBbox });
  }

  if (!boxes.length) throw new Error('Provide --bboxFile=... or --bbox=west,south,east,north');

  const outDir = args.get('outDir') || 'data';
  const radius = Math.max(1000, Math.min(parseInt(args.get('radius') || '20000', 10), 40000));
  const delayMs = Math.max(0, Math.min(parseInt(args.get('delayMs') || '150', 10), 2000));
  const mode = (args.get('mode') || 'both').toLowerCase(); // 'category' | 'term' | 'both'
  const term = (args.get('term') || 'halal').trim();
  const idParam = args.get('id');
  const idsFile = args.get('idsFile');

  const manualIDs = new Set();
  if (idParam) manualIDs.add(idParam);
  if (idsFile && fs.existsSync(idsFile)) {
    const text = fs.readFileSync(idsFile, 'utf8');
    for (const line of text.split(/\r?\n/)) {
      const trimmed = line.split('#')[0].trim();
      if (!trimmed) continue;
      const id = parseIdFromInput(trimmed);
      if (id) manualIDs.add(id);
    }
  }

  return { apiKey, boxes, outDir, radius, delayMs, mode, term, manualIDs };
}

function metersPerDegree(lat) {
  const mPerDegLat = 111_320; // approx
  const mPerDegLon = 111_320 * Math.cos((lat * Math.PI) / 180);
  return { mPerDegLat, mPerDegLon };
}

function gridCentersForBBox(b, radiusMeters) {
  // Overlap circles by 25% (step = 0.75 * radius) for reasonable coverage.
  const step = radiusMeters * 0.75;
  const midLat = (b.south + b.north) / 2;
  const { mPerDegLat, mPerDegLon } = metersPerDegree(midLat);
  const stepLatDeg = step / mPerDegLat;
  const stepLonDeg = step / mPerDegLon;

  const centers = [];
  for (let lat = b.south + stepLatDeg / 2; lat <= b.north; lat += stepLatDeg) {
    for (let lon = b.west + stepLonDeg / 2; lon <= b.east; lon += stepLonDeg) {
      centers.push({ latitude: +lat.toFixed(6), longitude: +lon.toFixed(6) });
    }
  }
  return centers;
}

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function fetchYelp({ apiKey, latitude, longitude, radius, offset, limit, term, useCategory }) {
  const url = new URL('https://api.yelp.com/v3/businesses/search');
  url.searchParams.set('latitude', String(latitude));
  url.searchParams.set('longitude', String(longitude));
  url.searchParams.set('radius', String(radius));
  if (useCategory) url.searchParams.set('categories', 'halal');
  if (term) url.searchParams.set('term', term);
  url.searchParams.set('limit', String(limit));
  if (offset) url.searchParams.set('offset', String(offset));

  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Yelp error ${resp.status}: ${text}`);
  }
  return await resp.json();
}

function normalizeBiz(b) {
  const address = Array.isArray(b.location?.display_address) ? b.location.display_address.join(', ') : '';
  return {
    id: b.id,
    name: b.name,
    alias: b.alias,
    url: b.url,
    rating: b.rating ?? null,
    review_count: b.review_count ?? null,
    is_closed: !!b.is_closed,
    phone: b.phone || b.display_phone || null,
    categories: Array.isArray(b.categories) ? b.categories.map(c => c.alias || c.title).filter(Boolean) : [],
    latitude: b.coordinates?.latitude ?? null,
    longitude: b.coordinates?.longitude ?? null,
    address,
    city: b.location?.city ?? null,
    state: b.location?.state ?? null,
    country: b.location?.country ?? null,
    zip_code: b.location?.zip_code ?? null,
  };
}

async function collectForBBox(apiKey, b, radius, delayMs, pageSize, maxWindow, mode, term) {
  const centers = gridCentersForBBox(b, radius);
  const aggregate = new Map(); // id -> { biz, match: Set<'category'|'term'> }

  for (const [i, c] of centers.entries()) {
    // Category=halal pass
    if (mode === 'category' || mode === 'both') {
      let offset = 0;
      for (;;) {
        if (offset >= maxWindow) break;
        const json = await fetchYelp({ apiKey, latitude: c.latitude, longitude: c.longitude, radius, offset, limit: pageSize, term: null, useCategory: true });
        const items = Array.isArray(json.businesses) ? json.businesses : [];
        for (const biz of items) {
          if (!biz || !biz.id) continue;
          const existing = aggregate.get(biz.id);
          if (existing) {
            existing.match.add('category');
          } else {
            aggregate.set(biz.id, { biz: normalizeBiz(biz), match: new Set(['category']) });
          }
        }
        if (items.length < pageSize) break;
        offset += pageSize;
        await sleep(delayMs);
      }
    }

    // Term-based pass (e.g., finds businesses that mention halal but lack the category)
    if (mode === 'term' || mode === 'both') {
      let offset = 0;
      for (;;) {
        if (offset >= maxWindow) break;
        const json = await fetchYelp({ apiKey, latitude: c.latitude, longitude: c.longitude, radius, offset, limit: pageSize, term, useCategory: false });
        const items = Array.isArray(json.businesses) ? json.businesses : [];
        for (const biz of items) {
          if (!biz || !biz.id) continue;
          const existing = aggregate.get(biz.id);
          if (existing) {
            existing.match.add('term');
          } else {
            aggregate.set(biz.id, { biz: normalizeBiz(biz), match: new Set(['term']) });
          }
        }
        if (items.length < pageSize) break;
        offset += pageSize;
        await sleep(delayMs);
      }
    }
    await sleep(delayMs);
  }

  // Flatten and annotate match type
  return Array.from(aggregate.values()).map(({ biz, match }) => ({ ...biz, match: Array.from(match).sort().join('+') }));
}

function writeOutputs(outDir, all, byArea) {
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const jsonPath = path.join(outDir, 'yelp_halal.json');
  const mdPath = path.join(outDir, 'yelp_halal.md');

  fs.writeFileSync(jsonPath, JSON.stringify({ total: all.length, generated_at: new Date().toISOString(), items: all }, null, 2));

  let md = `# Yelp Halal Places\n\n`;
  md += `Generated: ${new Date().toISOString()}\n\n`;
  for (const entry of byArea) {
    md += `## ${entry.label} — ${entry.items.length} places\n`;
    for (const it of entry.items) {
      const rating = it.rating != null ? `${it.rating}★ (${it.review_count ?? 0})` : 'n/a';
      const coords = (it.latitude != null && it.longitude != null) ? `${it.latitude}, ${it.longitude}` : 'n/a';
      const url = it.url ? ` [Yelp](${it.url})` : '';
      md += `- ${it.name} — ${it.address || 'No address'} — ${rating} — ${coords}${url}\n`;
    }
    md += `\n`;
  }
  fs.writeFileSync(mdPath, md);

  return { jsonPath, mdPath };
}

(async function main() {
  const { apiKey, boxes, outDir, radius, delayMs, mode, term, manualIDs } = parseArgs();
  const pageSize = 20; // safer default to avoid 240-window issues
  const maxWindow = 220; // keep (offset + limit) <= ~240
  console.log(`Fetching Yelp halal businesses for ${boxes.length} bbox(es); radius=${radius}m, delay=${delayMs}ms, mode=${mode}, term=${term}`);
  const globalMap = new Map();
  const byArea = [];

  for (const [idx, b] of boxes.entries()) {
    console.log(`\n[${idx + 1}/${boxes.length}] BBox ${b.label} — ${b.west},${b.south},${b.east},${b.north}`);
    const items = await collectForBBox(apiKey, b, radius, delayMs, pageSize, maxWindow, mode, term);
    console.log(`Collected ${items.length} unique businesses in area: ${b.label}`);
    byArea.push({ label: b.label, items });
    for (const it of items) {
      if (!globalMap.has(it.id)) globalMap.set(it.id, it);
    }
  }

  const all = Array.from(globalMap.values());
  // Manual include pass (ensures specific businesses are included)
  if (manualIDs.size) {
    console.log(`\nFetching ${manualIDs.size} manual business id(s)…`);
    for (const id of manualIDs) {
      if (globalMap.has(id)) continue;
      try {
        const details = await fetchBusinessDetails(apiKey, id);
        globalMap.set(details.id, { ...details, match: 'manual' });
        all.push({ ...details, match: 'manual' });
      } catch (e) {
        console.warn(`Manual include failed for ${id}:`, e.message);
      }
      await sleep(delayMs);
    }
  }
  const { jsonPath, mdPath } = writeOutputs(outDir, all, byArea);
  console.log(`\nWrote ${all.length} total unique businesses.`);
  console.log(`JSON: ${jsonPath}`);
  console.log(`Markdown: ${mdPath}`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
function parseIdFromInput(value) {
  // Accept raw id or Yelp URL. Examples:
  //  - fevys-chicken-elmhurst-4
  //  - https://www.yelp.com/biz/fevys-chicken-elmhurst-4
  try {
    if (/^https?:\/\//i.test(value)) {
      const u = new URL(value);
      const parts = u.pathname.split('/').filter(Boolean);
      const bizIdx = parts.findIndex(p => p.toLowerCase() === 'biz');
      if (bizIdx >= 0 && parts.length > bizIdx + 1) return parts[bizIdx + 1];
      return null;
    }
    return value;
  } catch {
    return null;
  }
}

async function fetchBusinessDetails(apiKey, id) {
  const url = `https://api.yelp.com/v3/businesses/${encodeURIComponent(id)}`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${apiKey}` } });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Yelp details error ${resp.status} for ${id}: ${text}`);
  }
  const json = await resp.json();
  return normalizeBiz(json);
}
