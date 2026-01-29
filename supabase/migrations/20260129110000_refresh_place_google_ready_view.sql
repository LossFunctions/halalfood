-- Refresh place_google_ready view to pick up new columns like category_label.

create or replace view public.place_google_ready as
select *
from public.place
where status = 'published'
  and category = 'restaurant'
  and halal_status in ('yes', 'only')
  and google_match_status = 'matched'
  and google_place_id is not null
  and (google_business_status is null or google_business_status = 'OPERATIONAL');

grant select on table public.place_google_ready to anon, authenticated, service_role;
