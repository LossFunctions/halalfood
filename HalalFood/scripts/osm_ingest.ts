// deno run --allow-net --allow-env scripts/osm_ingest.ts \
//   --bbox=-74.25909,40.477399,-73.700181,40.917577 --category=restaurant
// Requires env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

// Minimal Overpass → Supabase upsert for halal restaurants and mosques.
// Designed for seeding your Supabase `place` table so the iOS app
// can fetch via the `get_places_in_bbox` RPC without hitting OSM at runtime.

import { resolveDisplayLocation } from "./lib/display_location.ts";

type BBox = { west: number; south: number; east: number; north: number };
type BBoxTask = { bbox: BBox; label?: string };

function parseBBoxString(value: string): BBox {
  const parts = value.split(',').map((part) => part.trim());
  if (parts.length !== 4) {
    throw new Error(`Invalid bbox string "${value}". Expected format west,south,east,north`);
  }
  const numbers = parts.map(Number);
  if (numbers.some((n) => Number.isNaN(n))) {
    throw new Error(`BBox contains non-numeric values: "${value}"`);
  }
  const [west, south, east, north] = numbers;
  return { west, south, east, north };
}

function parseArgs() {
  const singleArgs = new Map<string, string>();
  const bboxInputs: Array<{ raw: string; label?: string }> = [];

  for (const arg of Deno.args) {
    const [rawKey, rawValue] = arg.split('=');
    if (!rawValue) continue;
    const key = rawKey.replace(/^--/, '');
    if (key === 'bbox') {
      bboxInputs.push({ raw: rawValue });
      continue;
    }
    singleArgs.set(key, rawValue);
  }

  const bboxFilePath = singleArgs.get('bboxFile');
  if (bboxFilePath) {
    const text = Deno.readTextFileSync(bboxFilePath);
    const lines = text.split(/\r?\n/);
    for (const line of lines) {
      const withoutComment = line.split('#')[0]?.trim();
      if (!withoutComment) continue;
      const [coordsPart, labelPart] = withoutComment.split('|').map((part) => part.trim());
      if (!coordsPart) continue;
      bboxInputs.push({ raw: coordsPart, label: labelPart && labelPart.length ? labelPart : undefined });
    }
  }

  if (!bboxInputs.length) {
    throw new Error('Provide at least one --bbox=west,south,east,north or a --bboxFile=path with bounding boxes.');
  }

  const seen = new Set<string>();
  const bboxes: BBoxTask[] = [];
  bboxInputs.forEach((entry, index) => {
    const bbox = parseBBoxString(entry.raw);
    const key = `${bbox.west},${bbox.south},${bbox.east},${bbox.north}`;
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    bboxes.push({ bbox, label: entry.label ?? `bbox ${index + 1}` });
  });

  if (!bboxes.length) {
    throw new Error('No valid bounding boxes provided.');
  }

  const category = (singleArgs.get('category') ?? 'restaurant') as 'restaurant' | 'mosque';
  const SUPABASE_URL = singleArgs.get('supabaseUrl') ?? Deno.env.get('SUPABASE_URL');
  const SERVICE_KEY = singleArgs.get('serviceKey') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!SUPABASE_URL || !SERVICE_KEY) {
    throw new Error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars or pass them via --supabaseUrl/--serviceKey.');
  }

  return { bboxes, category, SUPABASE_URL, SERVICE_KEY };
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
  display_location?: string|null;
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
  const { bboxes, category, SUPABASE_URL, SERVICE_KEY } = parseArgs();
  const aggregate = new Map<string, UpsertRow>();
  let totalElements = 0;

  for (const [index, task] of bboxes.entries()) {
    const label = task.label ?? `bbox ${index + 1}`;
    console.log(`Fetching from Overpass for ${category} (${index + 1}/${bboxes.length}) — ${label}`);

    try {
      const query = overpassQuery(task.bbox, category);
      const json = await fetchOverpass(query);
      const els = (json.elements ?? []) as OverpassElement[];
      totalElements += els.length;
      console.log(`Overpass returned ${els.length} elements for ${label}`);

      for (const el of els) {
        const coord = el.type === 'node' ? { lat: el.lat!, lon: el.lon! } : el.center;
        if (!coord) continue;
        const tags = el.tags ?? {};
        const halal = normalizeHalalStatus(tags);
        const address = addressFrom(tags);
        const displayLocation = resolveDisplayLocation({ address });
        const sourceRaw = { ...tags };
        if (displayLocation) {
          // Preserve display_location inside source_raw during rollout.
          (sourceRaw as Record<string, unknown>).display_location = displayLocation;
        }
        const row: UpsertRow = {
          external_id: `${el.type}:${el.id}`,
          source: 'osm',
          name: tags['name'] ?? '(Unnamed)',
          category,
          lat: coord.lat,
          lon: coord.lon,
          address,
          display_location: displayLocation ?? null,
          halal_status: halal,
          rating: null,
          rating_count: null,
          confidence: null,
          source_raw: sourceRaw,
          status: 'published',
        };
        aggregate.set(row.external_id, row);
      }
    } catch (error) {
      console.error(`Failed to fetch Overpass data for ${label}:`, error);
    }
  }

  const rows = Array.from(aggregate.values());
  if (!rows.length) {
    console.log('Nothing to upsert.');
    return;
  }

  console.log(`Aggregated ${rows.length} unique places from ${totalElements} Overpass elements.`);
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
