#!/usr/bin/env node
/**
 * Backfill source_raw.display_location for places in Supabase.
 *
 * Usage:
 *   node scripts/backfill_display_location.js --supabaseUrl=$SUPABASE_URL --serviceKey=$SUPABASE_SERVICE_ROLE_KEY [--limit=0]
 */

const fetch = globalThis.fetch;

function parseArgs() {
  const args = new Map();
  for (const a of process.argv.slice(2)) { const [k, v] = a.split('='); if (v) args.set(k.replace(/^--/, ''), v); }
  const SUPABASE_URL = args.get('supabaseUrl') || process.env.SUPABASE_URL;
  const SERVICE_KEY = args.get('serviceKey') || process.env.SUPABASE_SERVICE_ROLE_KEY;
  const limit = parseInt(args.get('limit') || '0', 10);
  if (!SUPABASE_URL || !SERVICE_KEY) throw new Error('Provide --supabaseUrl and --serviceKey');
  return { SUPABASE_URL, SERVICE_KEY, limit };
}

function extractZip(address) {
  if (!address) return null;
  const m = String(address).match(/(\d{5})(?:[-\s]\d{4})?$/);
  return m ? m[1] : null;
}

function boroughFromZip(zip) {
  if (!zip) return null;
  if (/^112/.test(zip)) return 'Brooklyn';
  if (/^(111|113|114|116)/.test(zip)) return 'Queens';
  if (/^104/.test(zip)) return 'Bronx';
  if (/^103/.test(zip)) return 'Staten Island';
  if (/^(100|101|102)/.test(zip)) return 'Manhattan';
  if (/^(110|115|117|118|119)/.test(zip)) return 'Long Island';
  return null;
}

const zipNeighborhood = new Map(Object.entries({
  // Queens
  11101: 'Long Island City', 11106: 'Long Island City', 11109: 'Long Island City', 11104: 'Sunnyside',
  11377: 'Woodside', 11372: 'Jackson Heights', 11354: 'Flushing', 11368: 'Corona',
  // Manhattan core
  10001: 'Chelsea', 10002: 'Lower East Side', 10003: 'East Village', 10004: 'Financial District', 10005: 'Financial District', 10006: 'Financial District',
  10007: 'Tribeca', 10009: 'East Village', 10010: 'Gramercy', 10011: 'Chelsea', 10012: 'SoHo', 10013: 'Tribeca', 10014: 'West Village',
  10016: 'Murray Hill', 10017: 'Midtown East', 10018: 'Garment District', 10019: 'Midtown West', 10020: 'Midtown', 10021: 'Upper East Side', 10022: 'Midtown East',
  10023: 'Upper West Side', 10024: 'Upper West Side', 10025: 'Upper West Side', 10026: 'Harlem', 10027: 'Harlem', 10030: 'Harlem', 10031: 'Hamilton Heights',
  10032: 'Washington Heights', 10033: 'Washington Heights', 10034: 'Inwood', 10035: 'East Harlem', 10036: 'Hell\'s Kitchen', 10037: 'Harlem', 10039: 'Harlem', 10040: 'Inwood'
}));

function detectNeighborhood(addr, zip) {
  const z = zipNeighborhood.get(String(zip));
  if (z) return z;
  const lower = String(addr || '').toLowerCase();
  const tokens = [
    ['tribeca','Tribeca'],['soho','SoHo'],['greenwich village','Greenwich Village'],['west village','West Village'],['east village','East Village'],
    ['chelsea','Chelsea'],['lower east side','Lower East Side'],['midtown','Midtown'],['murray hill','Murray Hill'],['gramercy','Gramercy'],
    ['financial district','Financial District'],['battery park','Battery Park City'],['harlem','Harlem'],['washington heights','Washington Heights'],
    ['inwood','Inwood'],['hell\'s kitchen','Hell\'s Kitchen'],['lincoln square','Lincoln Square'],
    // Queens
    ['long island city','Long Island City'],[' lic ','Long Island City'],['sunnyside','Sunnyside'],['woodside','Woodside'],['jackson heights','Jackson Heights'],
    ['elmhurst','Elmhurst'],['flushing','Flushing'],['rego park','Rego Park'],['forest hills','Forest Hills'],['jamaica','Jamaica']
  ];
  for (const [t, label] of tokens) if (lower.includes(t)) return label;
  return null;
}

async function listPlaces(SUPABASE_URL, SERVICE_KEY, limit) {
  let url = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place`);
  url.searchParams.set('select','id,address')
  url.searchParams.set('status','eq.published')
  if (limit>0) url.searchParams.set('limit', String(limit));
  const resp = await fetch(url, { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } });
  if (!resp.ok) throw new Error(`list failed ${resp.status}`);
  return await resp.json();
}

async function patchDisplay(SUPABASE_URL, SERVICE_KEY, id, value) {
  const url = new URL(`${SUPABASE_URL.replace(/\/$/, '')}/rest/v1/place`);
  url.searchParams.set('id', `eq.${id}`);
  const body = { source_raw: { display_location: value } };
  const resp = await fetch(url, { method: 'PATCH', headers: { 'Content-Type':'application/json', apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, Prefer: 'return=representation' }, body: JSON.stringify(body) });
  if (!resp.ok) throw new Error(`patch failed ${resp.status}`);
  await resp.json();
}

(async function main(){
  const { SUPABASE_URL, SERVICE_KEY, limit } = parseArgs();
  const places = await listPlaces(SUPABASE_URL, SERVICE_KEY, limit);
  let updated=0, skipped=0;
  for (const p of places) {
    const zip = extractZip(p.address);
    const borough = boroughFromZip(zip) || '';
    const n = detectNeighborhood(p.address, zip);
    const display = n && borough ? `${n}, ${borough}` : (borough || null);
    if (!display) { skipped++; continue; }
    try { await patchDisplay(SUPABASE_URL, SERVICE_KEY, p.id, display); updated++; }
    catch { skipped++; }
  }
  console.log(`Updated ${updated} places with display_location; skipped ${skipped}.`);
})();
