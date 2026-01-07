-- Ensure bbox RPC matches published-only filters used by pins/search.

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
    serves_alcohol boolean,
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
        pl.serves_alcohol,
        pl.source
    from public.place pl
    where pl.lat between south and north
      and pl.lon between west and east
      and pl.status = 'published'
      and (cat = 'all' or pl.category = cat)
    order by
        coalesce(pl.rating, 0) desc,
        coalesce(pl.rating_count, 0) desc,
        pl.id
    limit v_limit;
end;
$$ language plpgsql stable;
