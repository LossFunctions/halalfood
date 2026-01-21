import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
    Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    "";
const YELP_API_KEY = Deno.env.get("YELP_API_KEY") ?? "";

const CACHE_TTL_MS = 1000 * 60 * (60 * 23 + 55);
const MAX_PHOTOS = 5;

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

function validateYelpId(yelpId: string | null): string | null {
    if (!yelpId) {
        return null;
    }

    const trimmed = yelpId.trim();
    if (!trimmed || trimmed.length > 128) {
        return null;
    }

    if (!/^[A-Za-z0-9_-]+$/.test(trimmed)) {
        return null;
    }

    return trimmed;
}

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !YELP_API_KEY) {
        return jsonResponse({ error: "Missing server configuration." }, 500);
    }

    if (req.method !== "GET" && req.method !== "POST") {
        return jsonResponse({ error: "Method not allowed." }, 405);
    }

    let yelpId: string | null = null;
    if (req.method === "GET") {
        const url = new URL(req.url);
        yelpId = validateYelpId(url.searchParams.get("yelp_id"));
    } else {
        try {
            const payload = await req.json();
            yelpId = validateYelpId(payload?.yelp_id ?? null);
        } catch (_) {
            return jsonResponse({ error: "Invalid JSON body." }, 400);
        }
    }

    if (!yelpId) {
        return jsonResponse({ error: "Invalid yelp_id." }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        auth: { persistSession: false },
        global: { headers: { "x-client-info": "yelp-proxy" } },
    });

    const now = new Date();
    const nowIso = now.toISOString();

    const { data: cachedBusiness, error: cachedBusinessError } = await supabase
        .from("yelp_business_cache")
        .select("yelp_id, rating, review_count, yelp_url, fetched_at, expires_at")
        .eq("yelp_id", yelpId)
        .gt("expires_at", nowIso)
        .maybeSingle();

    if (cachedBusinessError) {
        console.error("cache lookup failed", cachedBusinessError);
    }

    if (cachedBusiness) {
        const { data: cachedPhotos, error: cachedPhotosError } = await supabase
            .from("yelp_photo_cache")
            .select("position, photo_url, attribution, fetched_at, expires_at")
            .eq("yelp_id", yelpId)
            .gt("expires_at", nowIso)
            .order("position", { ascending: true });

        if (cachedPhotosError) {
            console.error("photo cache lookup failed", cachedPhotosError);
        }

        return jsonResponse({
            yelp_id: cachedBusiness.yelp_id,
            rating: cachedBusiness.rating,
            review_count: cachedBusiness.review_count,
            yelp_url: cachedBusiness.yelp_url,
            fetched_at: cachedBusiness.fetched_at,
            expires_at: cachedBusiness.expires_at,
            photos: (cachedPhotos ?? []).map((photo) => ({
                position: photo.position,
                url: photo.photo_url,
                attribution: photo.attribution,
            })),
            cache_status: "hit",
        });
    }

    const yelpResponse = await fetch(
        `https://api.yelp.com/v3/businesses/${encodeURIComponent(yelpId)}`,
        {
            headers: {
                Authorization: `Bearer ${YELP_API_KEY}`,
                Accept: "application/json",
            },
        },
    );

    if (!yelpResponse.ok) {
        const errorPayload = await yelpResponse.json().catch(() => ({}));
        const errorMessage =
            errorPayload?.error?.description ?? "Failed to fetch Yelp data.";
        const status = yelpResponse.status === 404 ? 404 : 502;
        return jsonResponse({ error: errorMessage }, status);
    }

    const yelpPayload = await yelpResponse.json();
    const rating = typeof yelpPayload.rating === "number"
        ? yelpPayload.rating
        : null;
    const reviewCount = typeof yelpPayload.review_count === "number"
        ? yelpPayload.review_count
        : null;
    const yelpUrl = typeof yelpPayload.url === "string" ? yelpPayload.url : null;
    const imageUrl = typeof yelpPayload.image_url === "string"
        ? yelpPayload.image_url
        : null;
    const photos = Array.isArray(yelpPayload.photos)
        ? yelpPayload.photos.filter((photo: unknown) => typeof photo === "string")
        : [];
    const resolvedPhotos = photos.length > 0
        ? photos
        : (imageUrl ? [imageUrl] : []);

    const fetchedAt = nowIso;
    const expiresAt = new Date(now.getTime() + CACHE_TTL_MS).toISOString();

    const { error: upsertError } = await supabase
        .from("yelp_business_cache")
        .upsert({
            yelp_id: yelpId,
            rating,
            review_count: reviewCount,
            yelp_url: yelpUrl,
            fetched_at: fetchedAt,
            expires_at: expiresAt,
        });

    if (upsertError) {
        console.error("cache upsert failed", upsertError);
    }

    const { error: deletePhotosError } = await supabase
        .from("yelp_photo_cache")
        .delete()
        .eq("yelp_id", yelpId);

    if (deletePhotosError) {
        console.error("photo cache cleanup failed", deletePhotosError);
    }

    const photoPayload = resolvedPhotos.slice(0, MAX_PHOTOS).map((photoUrl, index) => ({
        yelp_id: yelpId,
        position: index,
        photo_url: photoUrl,
        attribution: "Yelp",
        fetched_at: fetchedAt,
        expires_at: expiresAt,
    }));

    if (photoPayload.length > 0) {
        const { error: insertPhotosError } = await supabase
            .from("yelp_photo_cache")
            .insert(photoPayload);

        if (insertPhotosError) {
            console.error("photo cache insert failed", insertPhotosError);
        }
    }

    return jsonResponse({
        yelp_id: yelpId,
        rating,
        review_count: reviewCount,
        yelp_url: yelpUrl,
        fetched_at: fetchedAt,
        expires_at: expiresAt,
        photos: photoPayload.map((photo) => ({
            position: photo.position,
            url: photo.photo_url,
            attribution: photo.attribution,
        })),
        cache_status: "miss",
    });
});
