#!/usr/bin/env node
// Convert data/yelp_halal.json to CSV for Supabase import
// Usage: node scripts/yelp_to_csv.js [inJson] [outCsv]

const fs = require('fs');
const path = require('path');

function csvEscape(value) {
  if (value == null) return '';
  const s = String(value);
  if (/[",\n]/.test(s)) return '"' + s.replace(/"/g, '""') + '"';
  return s;
}

const inPath = process.argv[2] || path.join('data', 'yelp_halal.json');
const outPath = process.argv[3] || path.join('data', 'yelp_halal.csv');

const json = JSON.parse(fs.readFileSync(inPath, 'utf8'));
const items = Array.isArray(json.items) ? json.items : [];

const headers = [
  'id','name','lat','lon','address','rating','rating_count','confidence','url','match','city','state','country','zip_code'
];

const lines = [headers.join(',')];
for (const it of items) {
  const row = [
    it.id,
    it.name,
    typeof it.latitude === 'number' ? it.latitude : '',
    typeof it.longitude === 'number' ? it.longitude : '',
    it.address || '',
    it.rating != null ? it.rating : '',
    it.review_count != null ? it.review_count : '',
    it.confidence != null ? it.confidence : '',
    it.url || '',
    it.match || '',
    it.city || '',
    it.state || '',
    it.country || '',
    it.zip_code || ''
  ].map(csvEscape).join(',');
  lines.push(row);
}

fs.writeFileSync(outPath, lines.join('\n'));
console.log('Wrote CSV', outPath, 'rows:', items.length);

