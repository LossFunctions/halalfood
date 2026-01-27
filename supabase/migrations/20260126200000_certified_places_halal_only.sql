-- Set halal_status to 'only' for all certified places
-- Rationale: Any place with a halal certification (HMS, SBNY, HFSAA)
-- should be marked as having a full halal menu

UPDATE public.place
SET halal_status = 'only'
WHERE cc_certifier_org IS NOT NULL
AND status = 'published';

-- Also update the materialized view after this migration
-- Run: REFRESH MATERIALIZED VIEW public.community_top_rated_v1;
