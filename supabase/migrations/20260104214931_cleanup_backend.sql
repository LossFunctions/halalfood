-- Cleanup redundant backend definitions.
-- Drop duplicate index and policy, and remove unused RPCs.

DROP INDEX IF EXISTS public.place_cat_idx;

DROP POLICY IF EXISTS "Public read published places" ON public.place;

DROP FUNCTION IF EXISTS public.get_places_in_bbox(
    double precision,
    double precision,
    double precision,
    double precision,
    text,
    integer
);

DROP FUNCTION IF EXISTS public.get_places_in_bbox_v2(
    double precision,
    double precision,
    double precision,
    double precision,
    text,
    integer
);
