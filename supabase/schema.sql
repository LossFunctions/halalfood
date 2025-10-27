-- Spatial index and lightweight viewport query for map pins.
-- Run this file against the Supabase database (psql or Supabase CLI).

-- Ensure we have an index that supports bounding-box lookups.
create index if not exists place_lat_lon_idx
    on public.place using btree (lat, lon);

-- Lightweight map query: returns only the fields needed for pins,
-- applies a hard cap of 300 rows, and orders by rating density.
create or replace function public.get_places_in_bbox_v3(
    west double precision,
    south double precision,
    east double precision,
    north double precision,
    cat text default 'all',
    max_count integer default 300
)
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
    source text
) as $$
declare
    v_limit integer := least(coalesce(max_count, 300), 300);
begin
    return query
    select
        pl.id,
        pl.name,
        pl.category,
        pl.lat::double precision,
        pl.lon::double precision,
        pl.address,
        pl.display_location,
        pl.halal_status::text,
        pl.rating::double precision,
        pl.rating_count::integer,
        pl.confidence::double precision,
        pl.source
    from public.place pl
    where pl.lat between south and north
      and pl.lon between west and east
      and (cat = 'all' or pl.category = cat)
    order by
        coalesce(pl.rating, 0) desc,
        coalesce(pl.rating_count, 0) desc,
        pl.id
    limit v_limit;
end;
$$ language plpgsql stable;
