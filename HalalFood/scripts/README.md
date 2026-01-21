# Yelp Workflow Cheatsheet

This app ingests Yelp places into Supabase for business IDs only. Use these scripts to add specific spots, enforce halal status, and manage IDs.

Compliance note: Yelp ratings/photos must not be stored beyond 24 hours. Generate Yelp datasets locally as needed, never commit them, and avoid ingesting Yelp photos into `place_photo`.

Prereqs
- Node 18+
- Env vars (private): `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `YELP_API_KEY`

Files
- `data/yelp_halal.json` – main dataset (generated locally; do not commit; delete within 24 hours)
- `scripts/manual_yelp_ids.txt` – convenience list of Yelp ids/URLs to force‑include
- `scripts/yelp_ingest.js` – upserts places into Supabase
- `scripts/yelp_hydrate_alcohol.js` – fetches Yelp details to set `serves_alcohol` for existing Yelp places
- `scripts/yelp_photos_ingest.js` – legacy (do not use; Yelp photos now load via the edge proxy/cache)
- `scripts/yelp_add_manual_id.js` – append one Yelp business to `data/yelp_halal.json`
- `scripts/yelp_halal_fetch.js` – fetches halal places across bbox tiles (can also accept `--idsFile`)

Mark certain brands as fully halal
- `scripts/yelp_ingest.js` contains `forcedFullyHalalPrefixes`. I added `kebabish` and `kebabishq` so KebabishQ is tagged `only` automatically.

Add KebabishQ (NYC)
1) Append to dataset (one‑off):
   - `cd HalalFood`
   - `YELP_API_KEY=... node scripts/yelp_add_manual_id.js https://www.yelp.com/biz/kebabishq-new-york data/yelp_halal.json`

   Alternative (batch via file):
   - `YELP_API_KEY=... node scripts/yelp_halal_fetch.js --bboxFile=overpass-bboxes.txt --idsFile=scripts/manual_yelp_ids.txt --outDir=data`

2) Upsert place into Supabase:
   - `node scripts/yelp_ingest.js --file=data/yelp_halal.json --supabaseUrl=$SUPABASE_URL --serviceKey=$SUPABASE_SERVICE_ROLE_KEY --batchSize=300`
   Photos now load via the edge proxy/cache; no photo ingest step.

Add to New Spots section
- After upsert, get the new place id:
  - `curl "$SUPABASE_URL/rest/v1/place?select=id,name,external_id&source=eq.yelp&external_id=eq.yelp:kebabishq-new-york" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"`
- Then add a `NewSpotConfig` in `ContentView.swift` with that UUID and a non-Yelp hero image (owned/licensed or app asset).

Notes
- Do not store Yelp photos in `place_photo`; fetch photos via the `yelp_proxy` edge function cache instead.
- `forcedFullyHalalPrefixes` sets halal_status = `only` for matching names; adjust if needed.
- If an entry already exists, `yelp_ingest.js` uses on_conflict merge.
- `yelp_hydrate_alcohol.js` uses one Yelp API call per place; start with a small `--limit` to avoid rate limits.

Add MOTW Coffee (Hicksville)
1) Append to dataset (one‑off):
   - `cd HalalFood`
   - `YELP_API_KEY=… node scripts/yelp_add_manual_id.js https://www.yelp.com/biz/motw-coffee-hicksville data/yelp_halal.json`

   Alternative (from the prefilled list):
   - Ensure `scripts/manual_yelp_ids.txt` contains the URL
   - `YELP_API_KEY=… node scripts/yelp_halal_fetch.js --bboxFile=overpass-bboxes.txt --idsFile=scripts/manual_yelp_ids.txt --outDir=data`

2) Upsert place into Supabase:
   - `node scripts/yelp_ingest.js --file=data/yelp_halal.json --supabaseUrl=$SUPABASE_URL --serviceKey=$SUPABASE_SERVICE_ROLE_KEY --batchSize=300`

3) Fetch the new place UUID:
   - `curl "$SUPABASE_URL/rest/v1/place?select=id,name,external_id,display_location&source=eq.yelp&external_id=eq.yelp:motw-coffee-hicksville" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | jq` 

4) Add to New Spots in `ContentView.swift`:
   Paste a new `NewSpotConfig` into the `newSpotConfigs` array, replacing placeholders with the UUID from step 3 and a non-Yelp hero image (owned/licensed or app asset).

   Example snippet (Fully halal; opening Nov 1):
   ```swift
   NewSpotConfig(
       placeID: UUID(uuidString: "<PASTE_UUID>")!,
       image: .asset("FinalAppImage"), // use owned/licensed imagery
       photoDescription: "MOTW Coffee signature latte",
       displayLocation: "Hicksville, Long Island",
       cuisine: "Coffee",
       halalStatusOverride: .only,
       openedOn: ("NOV", "01"),
       spotlightSummary: nil,
       spotlightDetails: "Fully halal"
   )
   ```

Env quick refs
- `SUPABASE_URL`: `https://<project>.supabase.co` (e.g., `https://qecnntkyxbcwtwyzlqku.supabase.co`)
- `SUPABASE_SERVICE_ROLE_KEY`: service role secret for the project
- `YELP_API_KEY`: Yelp Fusion API key
