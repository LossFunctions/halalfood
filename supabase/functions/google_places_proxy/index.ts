import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
    Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    "";
const GOOGLE_API_KEY =
    Deno.env.get("GOOGLE_MAPS_SERVER_KEY") ??
    Deno.env.get("GOOGLE_MAPS_API_KEY") ??
    Deno.env.get("google_maps_api_key") ??
    "";

const CACHE_TTL_MS = 1000 * 60 * (60 * 23 + 55);
const MAX_PHOTOS = 6;
const DEFAULT_PHOTO_WIDTH = 1200;
const MAX_PHOTO_WIDTH = 1600;

const corsHeaders = {
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "authorization, content-type, apikey",
    "access-control-allow-methods": "GET, POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
    return new Response(JSON.stringify(body), {
        status,
        headers: {
            "content-type": "application/json; charset=utf-8",
            ...corsHeaders,
        },
    });
}

function validatePlaceId(placeId: string | null): string | null {
    if (!placeId) {
        return null;
    }

    const trimmed = placeId.trim();
    if (!trimmed || trimmed.length > 256) {
        return null;
    }

    if (!/^[A-Za-z0-9_-]+$/.test(trimmed)) {
        return null;
    }

    return trimmed;
}

function validatePhotoReference(reference: string | null): string | null {
    if (!reference) {
        return null;
    }

    const trimmed = reference.trim();
    if (!trimmed || trimmed.length > 2048) {
        return null;
    }

    const legacyPattern = /^[A-Za-z0-9_-]+$/;
    const v1Pattern = /^places\/[A-Za-z0-9_-]+\/photos\/[A-Za-z0-9_-]+$/;
    if (!legacyPattern.test(trimmed) && !v1Pattern.test(trimmed)) {
        return null;
    }

    return trimmed;
}

function clampPhotoWidth(rawWidth: string | null): number {
    const parsed = rawWidth ? Number(rawWidth) : NaN;
    if (!Number.isFinite(parsed)) {
        return DEFAULT_PHOTO_WIDTH;
    }
    const clamped = Math.min(Math.max(Math.round(parsed), 200), MAX_PHOTO_WIDTH);
    return clamped;
}

function stripHtml(raw: string): string {
    return raw.replace(/<[^>]+>/g, "");
}

function decodeHtmlEntities(raw: string): string {
    return raw
        .replace(/&amp;/g, "&")
        .replace(/&quot;/g, "\"")
        .replace(/&#39;/g, "'")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">");
}

function extractAttribution(entry: unknown): string | null {
    if (typeof entry === "string") {
        const cleaned = decodeHtmlEntities(stripHtml(entry)).trim();
        return cleaned.length > 0 ? cleaned : null;
    }

    if (entry && typeof entry === "object") {
        const record = entry as Record<string, unknown>;
        const displayName = typeof record.displayName === "string"
            ? record.displayName.trim()
            : "";
        if (displayName.length > 0) {
            return displayName;
        }
        const uri = typeof record.uri === "string" ? record.uri.trim() : "";
        if (uri.length > 0) {
            return uri;
        }
    }

    return null;
}

function normalizeAttribution(attributions: unknown): string | null {
    if (!Array.isArray(attributions)) {
        return null;
    }

    const cleaned = attributions
        .map(extractAttribution)
        .filter((entry): entry is string => Boolean(entry));

    if (cleaned.length === 0) {
        return null;
    }

    const unique = Array.from(new Set(cleaned));
    if (unique.length === 1) {
        return unique[0];
    }
    return unique.join(", ");
}

function buildPhotoProxyURL(baseURL: URL, reference: string, width?: number): string {
    const origin = SUPABASE_URL || baseURL.toString();
    const url = new URL(origin);
    let path = url.pathname;
    if (!path.endsWith("/")) {
        path += "/";
    }
    path += "functions/v1/google_places_proxy/photo";
    url.pathname = path.replace(/\/{2,}/g, "/");
    url.search = "";
    const resolvedWidth = Math.min(
        Math.max(width ?? DEFAULT_PHOTO_WIDTH, 200),
        MAX_PHOTO_WIDTH,
    );
    url.searchParams.set("photo_reference", reference);
    url.searchParams.set("maxwidth", String(resolvedWidth));
    return url.toString();
}

async function updatePlaceStatus(
    supabase: ReturnType<typeof createClient>,
    placeId: string,
    businessStatus: string | null,
    mapsUrl: string | null,
    updatedAt: string,
) {
    const updates: Record<string, unknown> = {};
    if (businessStatus) {
        updates.google_business_status = businessStatus;
        updates.google_business_status_updated_at = updatedAt;
    }
    if (mapsUrl) {
        updates.google_maps_url = mapsUrl;
    }
    if (Object.keys(updates).length === 0) {
        return;
    }

    const { error } = await supabase
        .from("place")
        .update(updates)
        .eq("google_place_id", placeId);

    if (error) {
        console.error("place status update failed", error);
    }
}

async function handlePhotoRequest(req: Request): Promise<Response> {
    if (!GOOGLE_API_KEY) {
        return jsonResponse({ error: "Missing server configuration." }, 500);
    }

    const url = new URL(req.url);
    const reference = validatePhotoReference(url.searchParams.get("photo_reference"));
    if (!reference) {
        return jsonResponse({ error: "Invalid photo_reference." }, 400);
    }

    const width = clampPhotoWidth(url.searchParams.get("maxwidth"));
    let photoResponse: Response;
    if (reference.startsWith("places/")) {
        const photoURL = new URL(`https://places.googleapis.com/v1/${reference}/media`);
        photoURL.searchParams.set("maxWidthPx", String(width));
        photoResponse = await fetch(photoURL, {
            redirect: "follow",
            headers: { "X-Goog-Api-Key": GOOGLE_API_KEY },
        });
    } else {
        const photoURL = new URL("https://maps.googleapis.com/maps/api/place/photo");
        photoURL.searchParams.set("maxwidth", String(width));
        photoURL.searchParams.set("photo_reference", reference);
        photoURL.searchParams.set("key", GOOGLE_API_KEY);
        photoResponse = await fetch(photoURL, { redirect: "follow" });
    }
    if (!photoResponse.ok) {
        const status = photoResponse.status === 404 ? 404 : 502;
        return jsonResponse({ error: "Failed to fetch Google photo." }, status);
    }

    const headers = new Headers(photoResponse.headers);
    headers.set("cache-control", "public, max-age=3600");
    for (const [key, value] of Object.entries(corsHeaders)) {
        headers.set(key, value);
    }

    return new Response(photoResponse.body, {
        status: photoResponse.status,
        headers,
    });
}

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    const url = new URL(req.url);
    if (url.pathname.endsWith("/photo")) {
        if (req.method !== "GET") {
            return jsonResponse({ error: "Method not allowed." }, 405);
        }
        return await handlePhotoRequest(req);
    }

    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !GOOGLE_API_KEY) {
        return jsonResponse({ error: "Missing server configuration." }, 500);
    }

    if (req.method !== "GET" && req.method !== "POST") {
        return jsonResponse({ error: "Method not allowed." }, 405);
    }

    let placeId: string | null = null;
    if (req.method === "GET") {
        placeId = validatePlaceId(url.searchParams.get("place_id"));
        if (!placeId) {
            placeId = validatePlaceId(url.searchParams.get("google_place_id"));
        }
    } else {
        try {
            const payload = await req.json();
            placeId = validatePlaceId(payload?.place_id ?? null) ??
                validatePlaceId(payload?.google_place_id ?? null);
        } catch (_) {
            return jsonResponse({ error: "Invalid JSON body." }, 400);
        }
    }

    if (!placeId) {
        return jsonResponse({ error: "Invalid place_id." }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        auth: { persistSession: false },
        global: { headers: { "x-client-info": "google-places-proxy" } },
    });

    const now = new Date();
    const nowIso = now.toISOString();

    const { data: cachedPlace, error: cachedPlaceError } = await supabase
        .from("google_place_cache")
        .select("google_place_id, rating, review_count, business_status, maps_url, fetched_at, expires_at")
        .eq("google_place_id", placeId)
        .gt("expires_at", nowIso)
        .maybeSingle();

    if (cachedPlaceError) {
        console.error("cache lookup failed", cachedPlaceError);
    }

    if (cachedPlace) {
        const { data: cachedPhotos, error: cachedPhotosError } = await supabase
            .from("google_photo_cache")
            .select("position, photo_reference, attribution, width, height, fetched_at, expires_at")
            .eq("google_place_id", placeId)
            .gt("expires_at", nowIso)
            .order("position", { ascending: true });

        if (cachedPhotosError) {
            console.error("photo cache lookup failed", cachedPhotosError);
        }

        await updatePlaceStatus(
            supabase,
            placeId,
            cachedPlace.business_status ?? null,
            cachedPlace.maps_url ?? null,
            nowIso,
        );

        return jsonResponse({
            place_id: cachedPlace.google_place_id,
            rating: cachedPlace.rating,
            review_count: cachedPlace.review_count,
            business_status: cachedPlace.business_status,
            maps_url: cachedPlace.maps_url,
            fetched_at: cachedPlace.fetched_at,
            expires_at: cachedPlace.expires_at,
            photos: (cachedPhotos ?? []).map((photo) => ({
                position: photo.position,
                url: buildPhotoProxyURL(url, photo.photo_reference, photo.width ?? undefined),
                attribution: photo.attribution ?? "Google",
                reference: photo.photo_reference,
                width: photo.width,
                height: photo.height,
            })),
            cache_status: "hit",
        });
    }

    const detailsURL = new URL(`https://places.googleapis.com/v1/places/${placeId}`);
    const googleResponse = await fetch(detailsURL, {
        headers: {
            "X-Goog-Api-Key": GOOGLE_API_KEY,
            "X-Goog-FieldMask": "id,rating,userRatingCount,photos,googleMapsUri,businessStatus",
        },
    });

    const googlePayload = await googleResponse.json().catch(() => null);
    if (!googleResponse.ok) {
        const message = googlePayload?.error?.message ?? "Failed to fetch Google Places data.";
        const status = googleResponse.status === 404 ? 404 : 502;
        return jsonResponse({ error: message }, status);
    }

    if (googlePayload?.error) {
        const message = googlePayload.error?.message ?? "Failed to fetch Google Places data.";
        return jsonResponse({ error: message }, 502);
    }

    const result = googlePayload ?? {};
    const rating = typeof result.rating === "number" ? result.rating : null;
    const reviewCount = typeof result.userRatingCount === "number"
        ? result.userRatingCount
        : null;
    const mapsUrl = typeof result.googleMapsUri === "string" ? result.googleMapsUri : null;
    const businessStatus = typeof result.businessStatus === "string" ? result.businessStatus : null;
    const photos = Array.isArray(result.photos) ? result.photos : [];

    const fetchedAt = nowIso;
    const expiresAt = new Date(now.getTime() + CACHE_TTL_MS).toISOString();

    const { error: upsertError } = await supabase
        .from("google_place_cache")
        .upsert({
            google_place_id: placeId,
            rating,
            review_count: reviewCount,
            business_status: businessStatus,
            maps_url: mapsUrl,
            fetched_at: fetchedAt,
            expires_at: expiresAt,
        });

    if (upsertError) {
        console.error("cache upsert failed", upsertError);
    }

    const { error: deletePhotosError } = await supabase
        .from("google_photo_cache")
        .delete()
        .eq("google_place_id", placeId);

    if (deletePhotosError) {
        console.error("photo cache cleanup failed", deletePhotosError);
    }

    type CachedPhoto = {
        google_place_id: string;
        position: number;
        photo_reference: string;
        attribution: string;
        width: number | null;
        height: number | null;
        fetched_at: string;
        expires_at: string;
    };

    const photoPayload = photos
        .map((photo: Record<string, unknown>, index: number): CachedPhoto | null => {
            const reference = typeof photo.name === "string"
                ? photo.name
                : typeof photo.photo_reference === "string"
                ? photo.photo_reference
                : null;
            if (!reference) {
                return null;
            }
            const attribution = normalizeAttribution(
                photo.authorAttributions ?? photo.html_attributions,
            ) ?? "Google";
            const width = typeof photo.widthPx === "number"
                ? Math.round(photo.widthPx)
                : typeof photo.width === "number"
                ? Math.round(photo.width)
                : null;
            const height = typeof photo.heightPx === "number"
                ? Math.round(photo.heightPx)
                : typeof photo.height === "number"
                ? Math.round(photo.height)
                : null;
            return {
                google_place_id: placeId,
                position: index,
                photo_reference: reference,
                attribution,
                width,
                height,
                fetched_at: fetchedAt,
                expires_at: expiresAt,
            };
        })
        .filter((photo): photo is CachedPhoto => photo !== null)
        .slice(0, MAX_PHOTOS);

    if (photoPayload.length > 0) {
        const { error: insertPhotosError } = await supabase
            .from("google_photo_cache")
            .insert(photoPayload);

        if (insertPhotosError) {
            console.error("photo cache insert failed", insertPhotosError);
        }
    }

    await updatePlaceStatus(
        supabase,
        placeId,
        businessStatus,
        mapsUrl,
        nowIso,
    );

    return jsonResponse({
        place_id: placeId,
        rating,
        review_count: reviewCount,
        business_status: businessStatus,
        maps_url: mapsUrl,
        fetched_at: fetchedAt,
        expires_at: expiresAt,
        photos: photoPayload.map((photo) => ({
            position: photo.position,
            url: buildPhotoProxyURL(url, photo.photo_reference, photo.width ?? undefined),
            attribution: photo.attribution ?? "Google",
            reference: photo.photo_reference,
            width: photo.width,
            height: photo.height,
        })),
        cache_status: "miss",
    });
});
