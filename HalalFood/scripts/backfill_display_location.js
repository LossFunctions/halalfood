#!/usr/bin/env node
/**
 * Backfill display_location for places in Supabase, syncing both the column and source_raw field.
 *
 * Usage:
 *   node scripts/backfill_display_location.js --supabaseUrl=$SUPABASE_URL --serviceKey=$SUPABASE_SERVICE_ROLE_KEY [--limit=0]
 */

const fetch = globalThis.fetch;
const {
  resolveDisplayLocation,
  normalizeLabel,
} = require('./lib/display_location');

function parseArgs() {
  const args = new Map();
  for (const a of process.argv.slice(2)) { const [k, v] = a.split('='); if (v) args.set(k.replace(/^--/, ''), v); }
  const SUPABASE_URL = args.get('supabaseUrl') || process.env.SUPABASE_URL;
  const SERVICE_KEY = args.get('serviceKey') || process.env.SUPABASE_SERVICE_ROLE_KEY;
  const limit = parseInt(args.get('limit') || '0', 10);
  if (!SUPABASE_URL || !SERVICE_KEY) throw new Error('Provide --supabaseUrl and --serviceKey');
  return { SUPABASE_URL, SERVICE_KEY, limit };
}

async function listPlaces(SUPABASE_URL, SERVICE_KEY, rangeStart, pageSize, limit) {
  const url = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place`);
  url.searchParams.set('select', 'id,address,display_location,source_raw');
  url.searchParams.set('status', 'eq.published');
  if (limit > 0) {
    url.searchParams.set('limit', String(Math.min(pageSize, limit - rangeStart)));
  }
  const headers = {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    Prefer: 'count=exact'
  };
  headers['Range-Unit'] = 'items';
  headers.Range = `${rangeStart}-${rangeStart + pageSize - 1}`;
  const resp = await fetch(url, { headers });
  if (!resp.ok) throw new Error(`list failed ${resp.status}`);
  const totalHeader = resp.headers.get('content-range');
  let total = null;
  if (totalHeader) {
    const parts = totalHeader.split('/');
    if (parts.length === 2) {
      const maybeTotal = parseInt(parts[1], 10);
      if (!Number.isNaN(maybeTotal)) {
        total = maybeTotal;
      }
    }
  }
  const rows = await resp.json();
  return { rows, total };
}

function mergeSourceRaw(sourceRaw, display) {
  const next = sourceRaw && typeof sourceRaw === 'object' && !Array.isArray(sourceRaw)
    ? { ...sourceRaw }
    : {};
  if (display) {
    next.display_location = display;
  } else {
    delete next.display_location;
  }
  return next;
}

async function patchDisplay(SUPABASE_URL, SERVICE_KEY, id, display, sourceRaw) {
  const url = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place`);
  url.searchParams.set('id', `eq.${id}`);
  const body = {
    display_location: display,
    source_raw: mergeSourceRaw(sourceRaw, display)
  };
  const resp = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Content-Type':'application/json',
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      Prefer: 'return=representation'
    },
    body: JSON.stringify(body)
  });
  if (!resp.ok) throw new Error(`patch failed ${resp.status}`);
  await resp.json();
}

(async function main(){
  const { SUPABASE_URL, SERVICE_KEY, limit } = parseArgs();
  let updated=0, skipped=0;
  const pageSize = 1000;
  let offset = 0;
  let total = null;
  while (total === null || offset < total) {
    const { rows, total: reportedTotal } = await listPlaces(SUPABASE_URL, SERVICE_KEY, offset, pageSize, limit);
    if (reportedTotal !== null) {
      total = reportedTotal;
    } else if (rows.length < pageSize) {
      total = offset + rows.length;
    }
    if (!rows.length) { break; }
    for (const p of rows) {
      const existingColumn = normalizeLabel(p.display_location);
      const existingSource = normalizeLabel(p.source_raw && p.source_raw.display_location);
      const computed = resolveDisplayLocation({ address: p.address });
      const final = normalizeLabel(computed || existingColumn || existingSource);
      if (!final) { skipped++; continue; }
      if (existingColumn === final && existingSource === final) { continue; }
      try {
        await patchDisplay(SUPABASE_URL, SERVICE_KEY, p.id, final, p.source_raw);
        updated++;
      } catch {
        skipped++;
      }
    }
    offset += rows.length;
    if (limit > 0 && offset >= limit) { break; }
  }
  console.log(`Updated ${updated} places with display_location; skipped ${skipped}.`);
})();
