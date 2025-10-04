#!/usr/bin/env node
// Append a single Yelp business by ID or URL into an existing JSON dataset
// Usage: node scripts/yelp_add_manual_id.js <id-or-url> [jsonPath]

const fs = require('fs');
const path = require('path');

function usage() {
  console.error('Usage: YELP_API_KEY=... node scripts/yelp_add_manual_id.js <id-or-url> [jsonPath]');
  process.exit(2);
}

const apiKey = process.env.YELP_API_KEY;
if (!apiKey) { console.error('YELP_API_KEY is required'); process.exit(2); }

const arg = process.argv[2];
if (!arg) usage();
const jsonPath = process.argv[3] || path.join('data', 'yelp_halal.json');

function parseId(input) {
  if (/^https?:\/\//i.test(input)) {
    try {
      const u = new URL(input);
      const parts = u.pathname.split('/').filter(Boolean);
      const bizIdx = parts.findIndex(p => p.toLowerCase() === 'biz');
      if (bizIdx >= 0 && parts.length > bizIdx + 1) return parts[bizIdx + 1];
    } catch { /* ignore */ }
    return null;
  }
  return input;
}

async function fetchDetails(id) {
  const url = `https://api.yelp.com/v3/businesses/${encodeURIComponent(id)}`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${apiKey}` } });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Yelp error ${resp.status}: ${text}`);
  }
  return await resp.json();
}

function normalize(b) {
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
    match: 'manual'
  };
}

(async function main() {
  const id = parseId(arg);
  if (!id) { console.error('Could not parse Yelp id from input'); process.exit(2); }

  const details = await fetchDetails(id);
  const item = normalize(details);

  if (!fs.existsSync(jsonPath)) {
    fs.mkdirSync(path.dirname(jsonPath), { recursive: true });
    fs.writeFileSync(jsonPath, JSON.stringify({ total: 1, generated_at: new Date().toISOString(), items: [item] }, null, 2));
    console.log('Created', jsonPath, 'with one manual item.');
    return;
  }

  const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  const items = Array.isArray(data.items) ? data.items : [];
  if (items.some(x => x.id === item.id)) {
    console.log('Item already present in dataset:', item.id, '-', item.name);
  } else {
    items.push(item);
    data.items = items;
    data.total = items.length;
    data.generated_at = new Date().toISOString();
    fs.writeFileSync(jsonPath, JSON.stringify(data, null, 2));
    console.log('Appended manual item:', item.id, '-', item.name);
  }
})();

