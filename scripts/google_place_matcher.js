#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");

async function main() {
    const args = parseArgs(process.argv.slice(2));
    const env = loadEnv([path.join(process.cwd(), ".env.local"), path.join(process.cwd(), ".env")]);

    const SUPABASE_URL = readEnv(env, "SUPABASE_URL");
    const SUPABASE_KEY =
        readEnv(env, "SUPABASE_SERVICE_ROLE_KEY") ||
        readEnv(env, "SERVICE_ROLE_KEY") ||
        readEnv(env, "SUPABASE_ANON_KEY");
    const GOOGLE_API_KEY = readEnv(env, "GOOGLE_MAPS_API_KEY") || readEnv(env, "google_maps_api_key");

    const CONFIG = {
        limit: asNumber(args.limit, 0),
        offset: asNumber(args.offset, 0),
        pageSize: asNumber(args.pageSize, 500),
        radius: asNumber(args.radius, 120),
        fallbackRadius: asNumber(args.fallbackRadius, 300),
        delayMs: asNumber(args.delayMs, 180),
        maxCandidates: asNumber(args.maxCandidates, 6),
        minScore: asNumber(args.minScore, 6),
        farDistanceMeters: asNumber(args.farDistanceMeters, 1000),
        apply: Boolean(args.apply),
        state: normalizeStateFilter(args.state ?? "NY"),
        status: normalizeStatusFilter(args.status ?? "all"),
        idsFile: args.idsFile ? String(args.idsFile) : null,
        out: args.out ? String(args.out) : path.join("reports", "google_place_matches.csv"),
        review: args.review ? String(args.review) : path.join("reports", "google_place_review.csv"),
        unmatched: args.unmatched ? String(args.unmatched) : path.join("reports", "google_place_unmatched.csv"),
    };

    if (!SUPABASE_URL || !SUPABASE_KEY) {
        console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY/SUPABASE_ANON_KEY.");
        process.exit(1);
    }
    if (!GOOGLE_API_KEY) {
        console.error("Missing GOOGLE_MAPS_API_KEY (or google_maps_api_key).");
        process.exit(1);
    }
    if (CONFIG.apply && !readEnv(env, "SUPABASE_SERVICE_ROLE_KEY") && !readEnv(env, "SERVICE_ROLE_KEY")) {
        console.error("Refusing to apply updates without SUPABASE_SERVICE_ROLE_KEY/SERVICE_ROLE_KEY.");
        process.exit(1);
    }

    globalThis.__PLACE_MATCHER_CONFIG__ = CONFIG;
    globalThis.__PLACE_MATCHER_ENV__ = { SUPABASE_URL, SUPABASE_KEY, GOOGLE_API_KEY };

    const idsFilter = CONFIG.idsFile ? loadIds(CONFIG.idsFile) : null;
    globalThis.__PLACE_MATCHER_IDS__ = idsFilter;

    ensureDirectory(path.dirname(CONFIG.out));
    ensureDirectory(path.dirname(CONFIG.review));
    ensureDirectory(path.dirname(CONFIG.unmatched));

    const matchStream = fs.createWriteStream(CONFIG.out, { flags: "w" });
    const reviewStream = fs.createWriteStream(CONFIG.review, { flags: "w" });
    const unmatchedStream = fs.createWriteStream(CONFIG.unmatched, { flags: "w" });

    matchStream.write(csvRow([
        "place_id",
        "place_name",
        "place_address",
        "place_state",
        "place_lat",
        "place_lon",
        "google_place_id",
        "google_name",
        "google_address",
        "distance_m",
        "score",
        "method",
        "reasons",
        "maps_url",
    ]));
    reviewStream.write(csvRow([
        "place_id",
        "place_name",
        "place_address",
        "place_state",
        "place_lat",
        "place_lon",
        "google_place_id",
        "google_name",
        "google_address",
        "distance_m",
        "score",
        "method",
        "reasons",
        "maps_url",
    ]));
    unmatchedStream.write(csvRow([
        "place_id",
        "place_name",
        "place_address",
        "place_state",
        "place_lat",
        "place_lon",
        "reason",
    ]));

    let processed = 0;
    let matched = 0;
    let review = 0;
    let unmatched = 0;
    let errors = 0;
    const googleIdCollisions = new Map();

    const places = await fetchPlaces();
    for (const place of places) {
        processed += 1;
        try {
            const result = await matchPlace(place);
            if (result.status === "matched") {
                matched += 1;
                matchStream.write(csvRow([
                    place.id,
                    place.name,
                    place.address,
                    place.state,
                    place.lat,
                    place.lon,
                    result.candidate.placeId,
                    result.candidate.name,
                    result.candidate.address,
                    result.distanceMeters,
                    result.score,
                    result.method,
                    result.reasons.join("|"),
                    mapsUrlForPlaceId(result.candidate.placeId),
                ]));
                trackCollision(googleIdCollisions, result.candidate.placeId, place.id);
                if (CONFIG.apply) {
                    await updatePlaceMatch(place.id, buildMatchPayload(result));
                }
            } else if (result.status === "review") {
                review += 1;
                reviewStream.write(csvRow([
                    place.id,
                    place.name,
                    place.address,
                    place.state,
                    place.lat,
                    place.lon,
                    result.candidate?.placeId ?? "",
                    result.candidate?.name ?? "",
                    result.candidate?.address ?? "",
                    result.distanceMeters ?? "",
                    result.score ?? "",
                    result.method ?? "",
                    (result.reasons ?? []).join("|"),
                    result.candidate?.placeId ? mapsUrlForPlaceId(result.candidate.placeId) : "",
                ]));
                if (CONFIG.apply) {
                    await updatePlaceMatch(place.id, buildMatchPayload(result));
                }
            } else {
                unmatched += 1;
                unmatchedStream.write(csvRow([
                    place.id,
                    place.name,
                    place.address,
                    place.state,
                    place.lat,
                    place.lon,
                    result.reason ?? "no-match",
                ]));
                if (CONFIG.apply) {
                    await updatePlaceMatch(place.id, buildMatchPayload(result));
                }
            }
        } catch (error) {
            errors += 1;
            const errorMessage = `error:${error?.message || "unknown"}`;
            unmatchedStream.write(csvRow([
                place.id,
                place.name,
                place.address,
                place.state,
                place.lat,
                place.lon,
                errorMessage,
            ]));
            if (CONFIG.apply) {
                await updatePlaceMatch(
                    place.id,
                    buildErrorPayload(errorMessage)
                );
            }
        }

        if (CONFIG.delayMs > 0) {
            await sleep(CONFIG.delayMs);
        }
    }

    matchStream.end();
    reviewStream.end();
    unmatchedStream.end();

    const collisions = Array.from(googleIdCollisions.entries())
        .filter(([, ids]) => ids.length > 1)
        .map(([googleId, ids]) => `${googleId}=${ids.join("|")}`);

    console.log("Done.");
    console.log(`Processed: ${processed}`);
    console.log(`Matched: ${matched}`);
    console.log(`Review: ${review}`);
    console.log(`Unmatched: ${unmatched}`);
    console.log(`Errors: ${errors}`);
    if (collisions.length > 0) {
        console.log(`Potential duplicates (google_place_id mapped to multiple places): ${collisions.length}`);
    }
}

main().catch((error) => {
    console.error("Fatal error:", error?.message || error);
    process.exit(1);
});

async function matchPlace(place) {
    const config = getConfig();
    const phone = extractPhone(place.source_raw);
    let candidates = [];
    const hasCoords = Number.isFinite(place.lat) && Number.isFinite(place.lon);
    let usedText = false;
    if (phone) {
        candidates = candidates.concat(await findByPhone(phone));
    }

    if (candidates.length === 0 && hasCoords) {
        candidates = candidates.concat(await findNearby(place, config.radius));
    }

    if (candidates.length === 0 && hasCoords && config.fallbackRadius > config.radius) {
        candidates = candidates.concat(await findNearby(place, config.fallbackRadius));
    }

    if (candidates.length === 0) {
        usedText = true;
        candidates = candidates.concat(await findByText(place));
    }

    if (candidates.length === 0) {
        return { status: "unmatched", reason: "no-candidates" };
    }

    let scored = scoreCandidates(place, candidates);
    scored.sort((a, b) => b.score - a.score);
    const bestBefore = scored[0];
    if (!usedText && bestBefore && bestBefore.score < config.minScore) {
        const textCandidates = await findByText(place);
        if (textCandidates.length > 0) {
            candidates = candidates.concat(textCandidates);
            scored = scoreCandidates(place, candidates);
        }
    }

    scored.sort((a, b) => b.score - a.score);
    const best = scored[0];
    const second = scored[1];
    if (!best || best.score < config.minScore) {
        const reason = `low-score:${best?.score ?? 0}`;
        return {
            status: "unmatched",
            candidate: best?.candidate,
            score: best?.score ?? null,
            distanceMeters: best?.distanceMeters ?? null,
            method: best?.method ?? null,
            reasons: best?.reasons ?? null,
            reason,
        };
    }

    const ambiguous = second && (best.score - second.score) < 2;
    const far = best.distanceMeters != null && best.distanceMeters > config.farDistanceMeters;

    if (ambiguous || far) {
        return {
            status: "review",
            candidate: best.candidate,
            score: best.score,
            distanceMeters: best.distanceMeters,
            method: best.method,
            reasons: best.reasons,
        };
    }

    return {
        status: "matched",
        candidate: best.candidate,
        score: best.score,
        distanceMeters: best.distanceMeters,
        method: best.method,
        reasons: best.reasons,
    };
}

function scoreCandidates(place, candidates) {
    const deduped = new Map();
    for (const candidate of candidates) {
        if (!candidate.placeId) { continue; }
        const existing = deduped.get(candidate.placeId);
        if (!existing) {
            deduped.set(candidate.placeId, candidate);
        } else if (isBetterCandidate(candidate, existing)) {
            deduped.set(candidate.placeId, candidate);
        }
    }

    const scored = [];
    const placeZip = extractZip(place.address) || extractZip(place.display_location);
    const placeNumber = extractAddressNumber(place.address);
    for (const candidate of deduped.values()) {
        const distanceMeters = (candidate.lat != null && candidate.lon != null)
            ? haversineMeters(place.lat, place.lon, candidate.lat, candidate.lon)
            : null;
        const nameScore = nameSimilarity(place.name, candidate.name);
        const addressScore = addressSimilarity(place.address, candidate.address);
        const candidateZip = extractZip(candidate.address);
        const candidateNumber = extractAddressNumber(candidate.address);

        let score = 0;
        const reasons = [];

        if (candidate.method === "phone") {
            score += 3;
            reasons.push("phone");
        }

        if (distanceMeters != null) {
            if (distanceMeters < 50) { score += 4; reasons.push("dist<50m"); }
            else if (distanceMeters < 100) { score += 3; reasons.push("dist<100m"); }
            else if (distanceMeters < 250) { score += 2; reasons.push("dist<250m"); }
            else if (distanceMeters < 500) { score += 1; reasons.push("dist<500m"); }
        }

        if (nameScore >= 0.95) { score += 4; reasons.push("name=exact"); }
        else if (nameScore >= 0.85) { score += 3; reasons.push("name~high"); }
        else if (nameScore >= 0.7) { score += 2; reasons.push("name~med"); }
        else if (nameScore >= 0.55) { score += 1; reasons.push("name~low"); }

        if (addressScore >= 0.7) { score += 2; reasons.push("addr~high"); }
        else if (addressScore >= 0.5) { score += 1; reasons.push("addr~med"); }

        if (placeNumber && candidateNumber && placeNumber === candidateNumber) {
            score += 2;
            reasons.push("addr-num");
        }

        if (placeZip && candidateZip && placeZip === candidateZip) {
            score += 2;
            reasons.push("zip");
        }

        scored.push({
            candidate,
            score,
            distanceMeters,
            method: candidate.method,
            reasons,
        });
    }

    return scored;
}

async function findByPhone(phone) {
    const config = getConfig();
    const env = getEnv();
    const url = new URL("https://maps.googleapis.com/maps/api/place/findplacefromtext/json");
    url.searchParams.set("input", phone);
    url.searchParams.set("inputtype", "phonenumber");
    url.searchParams.set("fields", "place_id,name,formatted_address,geometry");
    url.searchParams.set("key", env.GOOGLE_API_KEY);

    const payload = await fetchWithRetry(url);
    if (payload.status === "ZERO_RESULTS") {
        return [];
    }
    if (payload.status !== "OK") {
        throw new Error(`Google findByPhone status: ${payload.status}`);
    }

    return (payload.candidates || []).map((candidate) => ({
        placeId: candidate.place_id,
        name: candidate.name,
        address: candidate.formatted_address ?? null,
        lat: candidate.geometry?.location?.lat ?? null,
        lon: candidate.geometry?.location?.lng ?? null,
        method: "phone",
    })).slice(0, config.maxCandidates);
}

async function findNearby(place, radiusMeters) {
    const config = getConfig();
    const env = getEnv();
    const url = new URL("https://maps.googleapis.com/maps/api/place/nearbysearch/json");
    url.searchParams.set("location", `${place.lat},${place.lon}`);
    url.searchParams.set("radius", `${radiusMeters}`);
    url.searchParams.set("keyword", place.name);
    url.searchParams.set("key", env.GOOGLE_API_KEY);

    const payload = await fetchWithRetry(url);
    if (payload.status === "ZERO_RESULTS") {
        return [];
    }
    if (payload.status !== "OK") {
        throw new Error(`Google findNearby status: ${payload.status}`);
    }

    return (payload.results || []).map((candidate) => ({
        placeId: candidate.place_id,
        name: candidate.name,
        address: candidate.vicinity ?? candidate.formatted_address ?? null,
        lat: candidate.geometry?.location?.lat ?? null,
        lon: candidate.geometry?.location?.lng ?? null,
        method: "nearby",
    })).slice(0, config.maxCandidates);
}

async function findByText(place) {
    const config = getConfig();
    const env = getEnv();
    const query = buildTextQuery(place);
    if (!query) { return []; }
    const hasCoords = Number.isFinite(place.lat) && Number.isFinite(place.lon);

    const url = new URL("https://maps.googleapis.com/maps/api/place/findplacefromtext/json");
    url.searchParams.set("input", query);
    url.searchParams.set("inputtype", "textquery");
    url.searchParams.set("fields", "place_id,name,formatted_address,geometry");
    if (hasCoords) {
        url.searchParams.set("locationbias", `point:${place.lat},${place.lon}`);
    }
    url.searchParams.set("key", env.GOOGLE_API_KEY);

    const payload = await fetchWithRetry(url);
    if (payload.status === "ZERO_RESULTS") {
        return [];
    }
    if (payload.status !== "OK") {
        throw new Error(`Google findByText status: ${payload.status}`);
    }

    return (payload.candidates || []).map((candidate) => ({
        placeId: candidate.place_id,
        name: candidate.name,
        address: candidate.formatted_address ?? null,
        lat: candidate.geometry?.location?.lat ?? null,
        lon: candidate.geometry?.location?.lng ?? null,
        method: "text",
    })).slice(0, config.maxCandidates);
}

function buildTextQuery(place) {
    const name = place.name?.trim();
    if (!name) { return null; }
    const address = place.address?.trim() || place.display_location?.trim();
    if (!address) { return name; }
    return `${name} ${address}`;
}

function extractPhone(sourceRaw) {
    if (!sourceRaw || typeof sourceRaw !== "object") { return null; }
    const candidates = [
        sourceRaw.phone,
        sourceRaw.display_phone,
        sourceRaw.displayPhone,
        sourceRaw.phone_number,
        sourceRaw.phoneNumber,
        sourceRaw.contact?.phone,
    ];
    for (const candidate of candidates) {
        const normalized = normalizePhone(candidate);
        if (normalized) { return normalized; }
    }
    return null;
}

function extractZip(address) {
    if (!address) { return null; }
    const match = String(address).match(/\b(\d{5})\b/);
    return match ? match[1] : null;
}

function extractAddressNumber(address) {
    if (!address) { return null; }
    const match = String(address).match(/\b(\d{1,5}(?:[-\s]\d{1,4})?)\b/);
    if (!match) { return null; }
    return match[1].replace(/[^0-9]/g, "");
}

function normalizePhone(raw) {
    if (!raw) { return null; }
    const trimmed = String(raw).trim();
    if (!trimmed) { return null; }
    let value = trimmed.replace(/[^0-9+]/g, "");
    if (value.startsWith("00")) {
        value = `+${value.slice(2)}`;
    }
    if (value.includes("+") && !value.startsWith("+")) {
        value = `+${value.replace(/\+/g, "")}`;
    }
    const digits = value.replace(/\D/g, "");
    if (digits.length < 7) { return null; }
    return value;
}

function nameSimilarity(a, b) {
    if (!a || !b) { return 0; }
    const normA = normalizeText(a);
    const normB = normalizeText(b);
    if (!normA || !normB) { return 0; }
    if (normA === normB) { return 1; }
    if (normA.includes(normB) || normB.includes(normA)) { return 0.9; }
    return jaccardSimilarity(tokenize(a), tokenize(b));
}

function addressSimilarity(a, b) {
    if (!a || !b) { return 0; }
    const normA = normalizeText(a);
    const normB = normalizeText(b);
    if (!normA || !normB) { return 0; }
    if (normA === normB) { return 1; }
    const tokensA = tokenize(a);
    const tokensB = tokenize(b);
    return jaccardSimilarity(tokensA, tokensB);
}

function tokenize(value) {
    return new Set(
        value
            .toLowerCase()
            .replace(/[^a-z0-9\s]/g, " ")
            .split(/\s+/)
            .filter(Boolean)
    );
}

function normalizeText(value) {
    return value
        .toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]/g, "");
}

function jaccardSimilarity(setA, setB) {
    if (!setA.size || !setB.size) { return 0; }
    let intersection = 0;
    for (const item of setA) {
        if (setB.has(item)) { intersection += 1; }
    }
    const union = setA.size + setB.size - intersection;
    return union === 0 ? 0 : intersection / union;
}

function haversineMeters(lat1, lon1, lat2, lon2) {
    const toRad = (value) => (value * Math.PI) / 180;
    const earthRadius = 6371000;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return earthRadius * c;
}

function isBetterCandidate(next, current) {
    const priority = (method) => {
        switch (method) {
        case "phone": return 3;
        case "text": return 2;
        case "nearby": return 1;
        default: return 0;
        }
    };
    const nextPriority = priority(next.method);
    const currentPriority = priority(current.method);
    if (nextPriority !== currentPriority) {
        return nextPriority > currentPriority;
    }
    const nextAddressLen = (next.address || "").length;
    const currentAddressLen = (current.address || "").length;
    if (nextAddressLen !== currentAddressLen) {
        return nextAddressLen > currentAddressLen;
    }
    const nextHasCoords = Number.isFinite(next.lat) && Number.isFinite(next.lon);
    const currentHasCoords = Number.isFinite(current.lat) && Number.isFinite(current.lon);
    return nextHasCoords && !currentHasCoords;
}

async function fetchPlaces() {
    const config = getConfig();
    const idsFilter = getIdsFilter();
    const select = [
        "id",
        "name",
        "address",
        "state",
        "display_location",
        "lat",
        "lon",
        "source",
        "source_id",
        "external_id",
        "source_raw",
    ].join(",");

    const items = [
        ["select", select],
        ["status", "eq.published"],
        ["category", "eq.restaurant"],
        ["order", "id.asc"],
    ];

    if (config.state) {
        items.push(["state", `eq.${config.state}`]);
    }

    if (config.status && config.status !== "all") {
        const normalized = String(config.status).toLowerCase();
        if (normalized === "unmatched") {
            items.push(["or", "(google_match_status.is.null,google_match_status.eq.unmatched)"]);
        } else {
            items.push(["google_match_status", `eq.${normalized}`]);
        }
    }

    if (idsFilter && idsFilter.length > 0) {
        const filter = idsFilter.map((id) => `"${id}"`).join(",");
        items.push(["id", `in.(${filter})`]);
    }

    let start = config.offset;
    let remaining = config.limit > 0 ? config.limit : Number.POSITIVE_INFINITY;
    const results = [];

    while (remaining > 0) {
        const pageSize = Math.min(config.pageSize, remaining === Number.POSITIVE_INFINITY ? config.pageSize : remaining);
        const end = start + pageSize - 1;
        const url = buildSupabaseURL("rest/v1/place", items);
        const headers = supabaseHeaders();
        headers["Range-Unit"] = "items";
        headers.Range = `${start}-${end}`;

        const response = await fetch(url, { headers });
        if (response.status === 416) { break; }
        if (!response.ok) {
            const body = await response.text();
            throw new Error(`Supabase fetch failed: ${response.status} ${body}`);
        }
        const rows = await response.json();
        if (!Array.isArray(rows) || rows.length === 0) { break; }
        for (const row of rows) {
            if (remaining <= 0) { break; }
            results.push(row);
            remaining = remaining === Number.POSITIVE_INFINITY ? remaining : remaining - 1;
        }
        if (rows.length < pageSize) { break; }
        start += pageSize;
    }

    return results;
}

async function updatePlaceMatch(placeId, payload) {
    if (!payload || Object.keys(payload).length === 0) { return; }
    const url = buildSupabaseURL("rest/v1/place", [["id", `eq.${placeId}`]]);
    const headers = supabaseHeaders();
    headers["Content-Type"] = "application/json";
    headers.Prefer = "return=minimal";
    const response = await fetch(url, {
        method: "PATCH",
        headers,
        body: JSON.stringify(payload),
    });
    if (!response.ok) {
        const body = await response.text();
        throw new Error(`Update failed: ${response.status} ${body}`);
    }
}

function buildSupabaseURL(endpoint, queryItems) {
    const env = getEnv();
    const base = new URL(env.SUPABASE_URL);
    const pathSuffix = base.pathname.endsWith("/") ? "" : "/";
    base.pathname = `${base.pathname}${pathSuffix}${endpoint}`;
    base.search = "";
    for (const [key, value] of queryItems) {
        base.searchParams.append(key, value);
    }
    return base.toString();
}

function supabaseHeaders() {
    const env = getEnv();
    return {
        apikey: env.SUPABASE_KEY,
        Authorization: `Bearer ${env.SUPABASE_KEY}`,
        Accept: "application/json",
        "Accept-Profile": "public",
    };
}

async function fetchWithRetry(url, attempt = 1) {
    const response = await fetch(url.toString(), { headers: { Accept: "application/json" } });
    if (response.ok) {
        return await response.json();
    }
    if ([429, 500, 502, 503].includes(response.status) && attempt < 5) {
        await sleep(200 * attempt);
        return fetchWithRetry(url, attempt + 1);
    }
    const body = await response.text();
    throw new Error(`Google API error: ${response.status} ${body}`);
}

function trackCollision(map, googlePlaceId, placeId) {
    if (!googlePlaceId) { return; }
    const existing = map.get(googlePlaceId) ?? [];
    existing.push(placeId);
    map.set(googlePlaceId, existing);
}

function mapsUrlForPlaceId(placeId) {
    return `https://maps.google.com/?q=place_id:${encodeURIComponent(placeId)}`;
}

function csvRow(values) {
    return `${values.map(csvValue).join(",")}\n`;
}

function csvValue(value) {
    if (value == null) { return ""; }
    const raw = String(value);
    if (raw.includes(",") || raw.includes("\"") || raw.includes("\n")) {
        return `"${raw.replace(/"/g, "\"\"")}"`;
    }
    return raw;
}

function parseArgs(argv) {
    const parsed = {};
    for (const arg of argv) {
        if (!arg.startsWith("--")) { continue; }
        const [key, value] = arg.slice(2).split("=");
        parsed[key] = value === undefined ? true : value;
    }
    return parsed;
}

function asNumber(value, fallback) {
    if (value === undefined || value === null) { return fallback; }
    const number = Number(value);
    return Number.isFinite(number) ? number : fallback;
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function loadEnv(paths) {
    const envValues = { ...process.env };
    for (const filePath of paths) {
        if (!fs.existsSync(filePath)) { continue; }
        const content = fs.readFileSync(filePath, "utf8");
        for (const line of content.split(/\r?\n/)) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith("#")) { continue; }
            const index = trimmed.indexOf("=");
            if (index === -1) { continue; }
            const key = trimmed.slice(0, index).trim();
            const value = trimmed.slice(index + 1).trim();
            if (!(key in envValues)) {
                envValues[key] = value;
            }
        }
    }
    return envValues;
}

function readEnv(envValues, key) {
    const value = envValues[key];
    if (!value) { return null; }
    const trimmed = String(value).trim();
    if (!trimmed) { return null; }
    const quoted = trimmed.match(/^(['"])(.*)\1$/);
    const unquoted = quoted ? quoted[2] : trimmed;
    return unquoted.length > 0 ? unquoted : null;
}

function ensureDirectory(dirPath) {
    if (!dirPath || dirPath === ".") { return; }
    if (!fs.existsSync(dirPath)) {
        fs.mkdirSync(dirPath, { recursive: true });
    }
}

function loadIds(filePath) {
    const content = fs.readFileSync(filePath, "utf8");
    return content
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line.length > 0 && !line.startsWith("#"));
}

function buildMatchPayload(result) {
    const nowIso = new Date().toISOString();
    const payload = {
        google_match_status: result.status,
        google_match_updated_at: nowIso,
    };

    const candidate = result.candidate;
    if (candidate?.placeId) {
        payload.google_match_place_id = candidate.placeId;
        payload.google_match_name = candidate.name ?? null;
        payload.google_match_address = candidate.address ?? null;
        payload.google_maps_url = mapsUrlForPlaceId(candidate.placeId);
    } else {
        payload.google_match_place_id = null;
        payload.google_match_name = null;
        payload.google_match_address = null;
        payload.google_maps_url = null;
    }

    if (result.status === "matched") {
        payload.google_place_id = candidate?.placeId ?? null;
    }

    if (result.status === "matched" || result.status === "review" || result.status === "unmatched") {
        payload.google_match_score = result.score ?? null;
        payload.google_match_distance_m = Number.isFinite(result.distanceMeters)
            ? Math.round(result.distanceMeters)
            : null;
        payload.google_match_method = result.method ?? null;
        const reasons = Array.isArray(result.reasons) ? result.reasons : [];
        if (result.reason) {
            reasons.push(result.reason);
        }
        payload.google_match_reasons = reasons.length > 0 ? reasons.join("|") : null;
    } else {
        payload.google_match_score = null;
        payload.google_match_distance_m = null;
        payload.google_match_method = null;
        payload.google_match_reasons = result.reason ?? null;
    }

    return payload;
}

function buildErrorPayload(errorMessage) {
    return {
        google_match_status: "error",
        google_match_reasons: errorMessage,
        google_match_updated_at: new Date().toISOString(),
    };
}

function normalizeStateFilter(value) {
    if (value == null) { return null; }
    const trimmed = String(value).trim();
    if (!trimmed) { return null; }
    if (trimmed.toLowerCase() === "all") { return null; }
    return trimmed.toUpperCase();
}

function normalizeStatusFilter(value) {
    if (value == null) { return null; }
    const trimmed = String(value).trim().toLowerCase();
    if (!trimmed || trimmed === "all") { return null; }
    return trimmed;
}

function getConfig() {
    return globalThis.__PLACE_MATCHER_CONFIG__ || {};
}

function getEnv() {
    return globalThis.__PLACE_MATCHER_ENV__ || {};
}

function getIdsFilter() {
    return globalThis.__PLACE_MATCHER_IDS__ || null;
}
