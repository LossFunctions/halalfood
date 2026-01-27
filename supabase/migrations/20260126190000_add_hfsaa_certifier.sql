-- Add HFSAA (Halal Food Standards Alliance of America) as certifier for known HFSAA-certified places
-- Source: HFSAA certified restaurant list (provided January 2026)
-- Note: Only updates places that don't already have a certifier

UPDATE public.place
SET cc_certifier_org = 'HFSAA'
WHERE (
  -- Restaurants
  name ILIKE 'Zabiha Burger%' OR
  name ILIKE 'Guac Time%' OR
  name ILIKE 'Gyro King%' OR
  name ILIKE 'Halal Bros Kabab%' OR
  name ILIKE 'Just Halal%' OR
  name ILIKE 'Kandahar Grill%' OR
  name ILIKE 'Sizzlings%' OR
  name ILIKE 'Sunshine Hicksville%' OR
  name ILIKE 'Uncle''s Fried Chicken%' OR
  name ILIKE 'YAAAS TEA%' OR
  -- Butcher/Market Departments
  name ILIKE 'Alladin Halal Meat%' OR
  name ILIKE 'Aladin Halal Meat%' OR
  name ILIKE 'Barakat Halal%' OR
  name ILIKE 'Farmingdale Grocery%' OR
  name ILIKE 'Hamza Meat%' OR
  name ILIKE 'Jamaica Live Poultry%' OR
  name ILIKE 'Mach Bazar%'
)
AND cc_certifier_org IS NULL
AND status = 'published';

-- Also update the materialized view after this migration
-- Run: REFRESH MATERIALIZED VIEW public.community_top_rated_v1;
