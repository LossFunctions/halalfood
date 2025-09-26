// deno run --allow-net --allow-env scripts/osm_ingest.ts \
//   --bbox=-74.25909,40.477399,-73.700181,40.917577 --category=restaurant
// Requires env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

// Minimal Overpass → Supabase upsert for halal restaurants and mosques.
// Designed for seeding your Supabase `place` table so the iOS app
// can fetch via the `get_places_in_bbox` RPC without hitting OSM at runtime.

type BBox = { west: number; south: number; east: number; north: number };

function parseArgs() {
  const args = new Map<string, string>();
  for (const a of Deno.args) {
    const [k, v] = a.split("=");
    if (!v) continue;
    args.set(k.replace(/^--/, ''), v);
  }
  const bboxStr = args.get('bbox');
  if (!bboxStr) throw new Error("Missing --bbox=west,south,east,north");
  const [west, south, east, north] = bboxStr.split(',').map(Number);
  const category = (args.get('category') ?? 'restaurant') as 'restaurant'|'mosque';
  const SUPABASE_URL = args.get('supabaseUrl') ?? Deno.env.get('SUPABASE_URL');
  const SERVICE_KEY = args.get('serviceKey') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!SUPABASE_URL || !SERVICE_KEY) throw new Error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars.');
  const bbox: BBox = { west, south, east, north };
  return { bbox, category, SUPABASE_URL, SERVICE_KEY };
}

function overpassQuery(b: BBox, category: 'restaurant'|'mosque') {
  const bbox = `${b.south},${b.west},${b.north},${b.east}`; // south,west,north,east for Overpass
  if (category === 'restaurant') {
    // Restaurants likely to be halal: diet:halal/halal tags
    return `
      [out:json][timeout:60];
      (
        node["amenity"="restaurant"]["diet:halal"~"yes|only",i](${bbox});
        way["amenity"="restaurant"]["diet:halal"~"yes|only",i](${bbox});
        relation["amenity"="restaurant"]["diet:halal"~"yes|only",i](${bbox});
        node["amenity"="restaurant"]["halal"~"yes|only",i](${bbox});
        way["amenity"="restaurant"]["halal"~"yes|only",i](${bbox});
        relation["amenity"="restaurant"]["halal"~"yes|only",i](${bbox});
      );
      out center tags;`;
  }
  // Mosques
  return `
    [out:json][timeout:60];
    (
      node["amenity"="place_of_worship"]["religion"~"muslim|islam",i](${bbox});
      way["amenity"="place_of_worship"]["religion"~"muslim|islam",i](${bbox});
      relation["amenity"="place_of_worship"]["religion"~"muslim|islam",i](${bbox});
      node["amenity"="mosque"](${bbox});
      way["amenity"="mosque"](${bbox});
      relation["amenity"="mosque"](${bbox});
    );
    out center tags;`;
}

type OverpassElement = {
  type: 'node'|'way'|'relation';
  id: number;
  lat?: number; lon?: number; // nodes
  center?: { lat: number; lon: number }; // ways/relations
  tags?: Record<string, string>;
};

function normalizeHalalStatus(tags: Record<string,string>|undefined): 'yes'|'only'|'no'|'unknown' {
  if (!tags) return 'unknown';
  const v = (tags['diet:halal'] ?? tags['halal'] ?? '').toLowerCase();
  if (/(only|exclusive)/.test(v)) return 'only';
  if (/^(yes|true|1|permissible)$/.test(v)) return 'yes';
  if (/^no$/.test(v)) return 'no';
  return 'unknown';
}

function addressFrom(tags: Record<string,string>|undefined) {
  if (!tags) return null;
  const parts = [
    [tags['addr:housenumber'], tags['addr:street']].filter(Boolean).join(' '),
    tags['addr:city'],
    tags['addr:state'],
    tags['addr:postcode'],
    tags['addr:country']
  ].filter(Boolean);
  const full = tags['addr:full'];
  return (full && full.trim().length > 0) ? full : (parts.length ? parts.join(', ') : null);
}

async function fetchOverpass(query: string) {
  const resp = await fetch('https://overpass-api.de/api/interpreter', {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain' },
    body: query,
  });
  if (!resp.ok) throw new Error(`Overpass error ${resp.status}`);
  return await resp.json();
}

type UpsertRow = {
  external_id: string;
  source: string;
  name: string;
  category: string;
  lat: number;
  lon: number;
  address?: string|null;
  halal_status?: string|null;
  rating?: number|null;
  rating_count?: number|null;
  confidence?: number|null;
  source_raw?: unknown;
  status?: string;
};

async function upsertToSupabase(url: string, key: string, rows: UpsertRow[]) {
  if (rows.length === 0) return { inserted: 0 } as const;
  const endpoint = `${url.replace(/\/$/, '')}/rest/v1/place?on_conflict=source,external_id`;
  const resp = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Prefer': 'return=representation,resolution=merge-duplicates',
      'apikey': key,
      'Authorization': `Bearer ${key}`,
    },
    body: JSON.stringify(rows),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Supabase upsert failed ${resp.status}: ${text}`);
  }
  const data = await resp.json();
  return { inserted: Array.isArray(data) ? data.length : 0 } as const;
}

async function main() {
  const { bbox, category, SUPABASE_URL, SERVICE_KEY } = parseArgs();
  const query = overpassQuery(bbox, category);
  console.log('Fetching from Overpass for', category, '…');
  const json = await fetchOverpass(query);
  const els = (json.elements ?? []) as OverpassElement[];
  console.log('Overpass returned', els.length, 'elements');

  const rows: UpsertRow[] = [];
  for (const el of els) {
    const coord = el.type === 'node' ? { lat: el.lat!, lon: el.lon! } : el.center;
    if (!coord) continue;
    const tags = el.tags ?? {};
    const halal = normalizeHalalStatus(tags);
    const row: UpsertRow = {
      external_id: `${el.type}:${el.id}`,
      source: 'osm',
      name: tags['name'] ?? '(Unnamed)',
      category,
      lat: coord.lat,
      lon: coord.lon,
      address: addressFrom(tags),
      halal_status: halal,
      rating: null,
      rating_count: null,
      confidence: null,
      source_raw: tags,
      status: 'published',
    };
    rows.push(row);
  }

  if (!rows.length) {
    console.log('Nothing to upsert.');
    return;
  }
  console.log('Upserting', rows.length, 'rows to Supabase…');
  const res = await upsertToSupabase(SUPABASE_URL, SERVICE_KEY, rows);
  console.log('Done. Upserted', res.inserted, 'rows.');
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(e);
    Deno.exit(1);
  });
}

