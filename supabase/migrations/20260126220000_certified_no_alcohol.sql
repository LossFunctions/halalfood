-- Set serves_alcohol to false for all certified places
-- Rationale: Any place with a halal certification (HMS, SBNY, HFSAA)
-- would not serve alcohol

UPDATE public.place
SET serves_alcohol = false
WHERE cc_certifier_org IS NOT NULL
AND status = 'published';
