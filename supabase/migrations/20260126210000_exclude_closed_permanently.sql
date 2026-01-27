-- Exclude permanently closed places from all API responses
-- Places with google_business_status = 'CLOSED_PERMANENTLY' will not appear in the app

-- Update get_places_in_bbox_v3 to exclude closed places
CREATE OR REPLACE FUNCTION public.get_places_in_bbox_v3(
    west double precision,
    south double precision,
    east double precision,
    north double precision,
    cat text DEFAULT 'all',
    max_count integer DEFAULT 200
)
RETURNS TABLE(
    id uuid,
    name text,
    category text,
    lat double precision,
    lon double precision,
    address text,
    display_location text,
    halal_status text,
    rating double precision,
    rating_count integer,
    serves_alcohol boolean,
    source text,
    source_id text,
    external_id text,
    google_place_id text,
    google_match_status text,
    google_maps_url text,
    google_business_status text,
    apple_place_id text,
    note text,
    cc_certifier_org text,
    source_raw jsonb
)
LANGUAGE sql STABLE
AS $$
    SELECT
        p.id,
        p.name,
        p.category,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
        p.serves_alcohol,
        p.source,
        p.source_id,
        p.external_id,
        p.google_place_id,
        p.google_match_status,
        p.google_maps_url,
        p.google_business_status,
        p.apple_place_id,
        p.note,
        p.cc_certifier_org,
        p.source_raw
    FROM public.place p
    WHERE p.status = 'published'
      AND p.halal_status IN ('yes', 'only')
      AND (p.google_business_status IS NULL OR p.google_business_status <> 'CLOSED_PERMANENTLY')
      AND p.lon BETWEEN west AND east
      AND p.lat BETWEEN south AND north
      AND (cat = 'all' OR p.category = cat)
    ORDER BY p.rating DESC NULLS LAST
    LIMIT max_count;
$$;

-- Update search_places to exclude closed places
CREATE OR REPLACE FUNCTION public.search_places(
    p_query text,
    p_normalized_query text,
    p_limit integer DEFAULT 40
)
RETURNS TABLE(
    id uuid,
    name text,
    category text,
    lat double precision,
    lon double precision,
    address text,
    display_location text,
    halal_status text,
    rating double precision,
    rating_count integer,
    serves_alcohol boolean,
    source text,
    source_id text,
    external_id text,
    google_place_id text,
    google_match_status text,
    google_maps_url text,
    google_business_status text,
    apple_place_id text,
    note text,
    cc_certifier_org text
)
LANGUAGE sql STABLE
AS $$
    SELECT
        p.id,
        p.name,
        p.category,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
        p.serves_alcohol,
        p.source,
        p.source_id,
        p.external_id,
        p.google_place_id,
        p.google_match_status,
        p.google_maps_url,
        p.google_business_status,
        p.apple_place_id,
        p.note,
        p.cc_certifier_org
    FROM public.place p
    WHERE p.status = 'published'
      AND p.halal_status IN ('yes', 'only')
      AND (p.google_business_status IS NULL OR p.google_business_status <> 'CLOSED_PERMANENTLY')
      AND (
          p.name ILIKE '%' || p_query || '%'
          OR p.address ILIKE '%' || p_query || '%'
      )
    ORDER BY p.rating DESC NULLS LAST
    LIMIT p_limit;
$$;

-- Update search_places_v2 to exclude closed places
CREATE OR REPLACE FUNCTION public.search_places_v2(
    p_query text,
    p_normalized_query text,
    p_limit integer DEFAULT 40
)
RETURNS TABLE(
    id uuid,
    name text,
    category text,
    lat double precision,
    lon double precision,
    address text,
    display_location text,
    halal_status text,
    rating double precision,
    rating_count integer,
    serves_alcohol boolean,
    source text,
    source_id text,
    external_id text,
    google_place_id text,
    google_match_status text,
    google_maps_url text,
    google_business_status text,
    apple_place_id text,
    note text,
    cc_certifier_org text
)
LANGUAGE sql STABLE
AS $$
    SELECT
        p.id,
        p.name,
        p.category,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
        p.serves_alcohol,
        p.source,
        p.source_id,
        p.external_id,
        p.google_place_id,
        p.google_match_status,
        p.google_maps_url,
        p.google_business_status,
        p.apple_place_id,
        p.note,
        p.cc_certifier_org
    FROM public.place p
    WHERE p.status = 'published'
      AND p.halal_status IN ('yes', 'only')
      AND (p.google_business_status IS NULL OR p.google_business_status <> 'CLOSED_PERMANENTLY')
      AND (
          p.name ILIKE '%' || p_query || '%'
          OR p.address ILIKE '%' || p_query || '%'
          OR p.display_location ILIKE '%' || p_query || '%'
      )
    ORDER BY p.rating DESC NULLS LAST
    LIMIT p_limit;
$$;

-- Update get_place_details to exclude closed places
CREATE OR REPLACE FUNCTION public.get_place_details(p_place_id uuid)
RETURNS TABLE(
    id uuid,
    name text,
    category text,
    lat double precision,
    lon double precision,
    address text,
    display_location text,
    halal_status text,
    rating double precision,
    rating_count integer,
    serves_alcohol boolean,
    source text,
    source_id text,
    external_id text,
    google_place_id text,
    google_match_status text,
    google_maps_url text,
    google_business_status text,
    apple_place_id text,
    note text,
    cc_certifier_org text
)
LANGUAGE sql STABLE
AS $$
    SELECT
        p.id,
        p.name,
        p.category,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
        p.serves_alcohol,
        p.source,
        p.source_id,
        p.external_id,
        p.google_place_id,
        p.google_match_status,
        p.google_maps_url,
        p.google_business_status,
        p.apple_place_id,
        p.note,
        p.cc_certifier_org
    FROM public.place p
    WHERE p.id = p_place_id
      AND p.status = 'published'
      AND (p.google_business_status IS NULL OR p.google_business_status <> 'CLOSED_PERMANENTLY');
$$;

-- Update get_place_details_by_ids to exclude closed places
CREATE OR REPLACE FUNCTION public.get_place_details_by_ids(p_place_ids uuid[])
RETURNS TABLE(
    id uuid,
    name text,
    category text,
    lat double precision,
    lon double precision,
    address text,
    display_location text,
    halal_status text,
    rating double precision,
    rating_count integer,
    serves_alcohol boolean,
    source text,
    source_id text,
    external_id text,
    google_place_id text,
    google_match_status text,
    google_maps_url text,
    google_business_status text,
    apple_place_id text,
    note text,
    cc_certifier_org text
)
LANGUAGE sql STABLE
AS $$
    SELECT
        p.id,
        p.name,
        p.category,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
        p.serves_alcohol,
        p.source,
        p.source_id,
        p.external_id,
        p.google_place_id,
        p.google_match_status,
        p.google_maps_url,
        p.google_business_status,
        p.apple_place_id,
        p.note,
        p.cc_certifier_org
    FROM public.place p
    WHERE p.id = ANY(p_place_ids)
      AND p.status = 'published'
      AND (p.google_business_status IS NULL OR p.google_business_status <> 'CLOSED_PERMANENTLY');
$$;

-- Update the materialized view to exclude closed places
DROP MATERIALIZED VIEW IF EXISTS public.community_top_rated_v1;

CREATE MATERIALIZED VIEW public.community_top_rated_v1 AS
WITH region_places AS (
    SELECT
        CASE
            WHEN p.address ILIKE '%New York%' OR p.address ILIKE '%NY %' OR p.address ILIKE '%, NY' THEN 'nyc'
            WHEN p.address ILIKE '%New Jersey%' OR p.address ILIKE '%NJ %' OR p.address ILIKE '%, NJ' THEN 'nj'
            WHEN p.address ILIKE '%Connecticut%' OR p.address ILIKE '%CT %' OR p.address ILIKE '%, CT' THEN 'ct'
            ELSE 'other'
        END AS region,
        p.id,
        p.name,
        p.category,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
        p.serves_alcohol,
        p.source,
        p.google_place_id,
        p.google_match_status,
        p.google_maps_url,
        p.google_business_status,
        p.apple_place_id,
        p.note,
        p.cc_certifier_org,
        p.source_raw,
        ROW_NUMBER() OVER (
            PARTITION BY
                CASE
                    WHEN p.address ILIKE '%New York%' OR p.address ILIKE '%NY %' OR p.address ILIKE '%, NY' THEN 'nyc'
                    WHEN p.address ILIKE '%New Jersey%' OR p.address ILIKE '%NJ %' OR p.address ILIKE '%, NJ' THEN 'nj'
                    WHEN p.address ILIKE '%Connecticut%' OR p.address ILIKE '%CT %' OR p.address ILIKE '%, CT' THEN 'ct'
                    ELSE 'other'
                END
            ORDER BY p.rating DESC NULLS LAST, p.rating_count DESC NULLS LAST
        ) AS region_rank
    FROM public.place p
    WHERE p.status = 'published'
      AND p.halal_status IN ('yes', 'only')
      AND p.category = 'restaurant'
      AND p.rating IS NOT NULL
      AND p.rating >= 4.0
      AND (p.google_business_status IS NULL OR p.google_business_status <> 'CLOSED_PERMANENTLY')
)
SELECT
    region,
    region_rank::integer,
    id,
    name,
    category,
    lat,
    lon,
    address,
    display_location,
    halal_status,
    rating,
    rating_count,
    serves_alcohol,
    source,
    google_place_id,
    google_match_status,
    google_maps_url,
    google_business_status,
    apple_place_id,
    note,
    cc_certifier_org,
    source_raw,
    NULL::text AS primary_image_url
FROM region_places
WHERE region_rank <= 100;

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_community_top_rated_v1_region
ON public.community_top_rated_v1 (region, region_rank);

-- Refresh the view
REFRESH MATERIALIZED VIEW public.community_top_rated_v1;
