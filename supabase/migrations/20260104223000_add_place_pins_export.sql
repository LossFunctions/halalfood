-- Create a stable pins export and detail RPCs for paging by id.

create or replace view public.place_pins as
select
  id,
  lat,
  lon,
  halal_status,
  updated_at
from public.place
where status = 'published'
  and category = 'restaurant'
  and halal_status in ('yes', 'only');

grant select on table public.place_pins to anon, authenticated, service_role;

create or replace function public.get_place_details(p_place_id uuid)
returns table (
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
  confidence double precision,
  source text,
  apple_place_id text,
  note text,
  source_raw jsonb
)
language sql
stable
as $function$
  select
    p.id,
    p.name,
    p.category,
    p.lat::double precision,
    p.lon::double precision,
    p.address,
    p.display_location,
    p.halal_status::text,
    p.rating::double precision,
    p.rating_count::integer,
    p.confidence::double precision,
    p.source,
    p.apple_place_id,
    p.note,
    p.source_raw
  from public.place as p
  where p.id = p_place_id
    and p.status = 'published';
$function$;

grant execute on function public.get_place_details(uuid)
  to anon, authenticated, service_role;

create or replace function public.get_place_details_by_ids(p_place_ids uuid[])
returns table (
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
  confidence double precision,
  source text,
  apple_place_id text,
  note text,
  source_raw jsonb
)
language sql
stable
as $function$
  select
    p.id,
    p.name,
    p.category,
    p.lat::double precision,
    p.lon::double precision,
    p.address,
    p.display_location,
    p.halal_status::text,
    p.rating::double precision,
    p.rating_count::integer,
    p.confidence::double precision,
    p.source,
    p.apple_place_id,
    p.note,
    p.source_raw
  from public.place as p
  where p.id = any(p_place_ids)
    and p.status = 'published';
$function$;

grant execute on function public.get_place_details_by_ids(uuid[])
  to anon, authenticated, service_role;
