-- Extend pins export with address so clients can apply NY-only geofilters.

create or replace view public.place_pins as
select
  id,
  lat,
  lon,
  halal_status,
  updated_at,
  address
from public.place
where status = 'published'
  and category = 'restaurant'
  and halal_status in ('yes', 'only');

grant select on table public.place_pins to anon, authenticated, service_role;
