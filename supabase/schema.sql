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

-- -----------------------------------------------------------
-- Community Top Rated materialized view and helpers
-- -----------------------------------------------------------

create or replace function public.community_region_for_place(
    lat double precision,
    lon double precision,
    address text
)
returns text as $$
declare
    normalized_address text := lower(coalesce(address, ''));
    zip_matches text[];
    zip_code text;
begin
    if lat between 40.68 and 40.90 and lon between -74.03 and -73.92 then
        return 'manhattan';
    end if;
    if lat between 40.56 and 40.74 and lon between -74.05 and -73.83 then
        return 'brooklyn';
    end if;
    if lat between 40.54 and 40.81 and lon between -73.96 and -73.70 then
        return 'queens';
    end if;
    if lat between 40.79 and 40.93 and lon between -73.93 and -73.76 then
        return 'bronx';
    end if;
    if lat between 40.48 and 40.65 and lon between -74.27 and -74.05 then
        return 'statenIsland';
    end if;
    if lat between 40.55 and 41.20 and lon between -73.95 and -71.75 then
        if normalized_address not like '%long island city%' then
            return 'longIsland';
        end if;
    end if;

    if normalized_address = '' then
        return null;
    end if;

    select regexp_match(normalized_address, '\m(\d{5})\M') into zip_matches;
    if array_length(zip_matches, 1) = 1 then
        zip_code := zip_matches[1];
        if zip_code like '100%' or zip_code like '101%' or zip_code like '102%' then
            return 'manhattan';
        elsif zip_code like '112%' then
            return 'brooklyn';
        elsif zip_code like '111%' or zip_code like '113%' or zip_code like '114%' or zip_code like '116%' then
            return 'queens';
        elsif zip_code like '104%' then
            return 'bronx';
        elsif zip_code like '103%' then
            return 'statenIsland';
        elsif zip_code like '110%' or zip_code like '115%' or zip_code like '117%' or zip_code like '118%' then
            if normalized_address not like '%long island city%' then
                return 'longIsland';
            end if;
        end if;
    end if;

    if normalized_address like '% manhattan%' or normalized_address like '% new york, ny%' then
        return 'manhattan';
    elsif normalized_address like '% brooklyn%' then
        return 'brooklyn';
    elsif normalized_address like '% bronx%' then
        return 'bronx';
    elsif normalized_address like '% staten island%' then
        return 'statenIsland';
    elsif normalized_address like '% queens%' or normalized_address like '% astoria%' or normalized_address like '% lic %' then
        return 'queens';
    elsif normalized_address like '% long island%' and normalized_address not like '%long island city%' then
        return 'longIsland';
    end if;

    return null;
end;
$$ language plpgsql stable;

drop materialized view if exists public.community_top_rated_v1;

create materialized view public.community_top_rated_v1 as
with base as (
    select
        pl.id,
        pl.name,
        pl.category,
        pl.lat,
        pl.lon,
        pl.address,
        pl.display_location,
        pl.halal_status,
        pl.rating,
        pl.rating_count,
        pl.confidence,
        pl.source,
        pl.apple_place_id,
        pl.note,
        pl.source_raw,
        photo.image_url as primary_image_url,
        community_region_for_place(pl.lat, pl.lon, pl.address) as region
    from public.place pl
    left join lateral (
        select ph.image_url
        from public.place_photo ph
        where ph.place_id = pl.id
        order by coalesce(ph.priority, 999), ph.id
        limit 1
    ) photo on true
    where pl.status = 'published'
      and pl.category = 'restaurant'
      and pl.halal_status in ('yes', 'only')
      and coalesce(pl.rating, 0) > 0
      and coalesce(pl.rating_count, 0) >= 3
)
, regional as (
    select
        base.region,
        base.id,
        base.name,
        base.category,
        base.lat,
        base.lon,
        base.address,
        base.display_location,
        base.halal_status,
        base.rating,
        base.rating_count,
        base.confidence,
        base.source,
        base.apple_place_id,
        base.note,
        base.source_raw,
        base.primary_image_url,
        row_number() over (
            partition by base.region
            order by
                coalesce(base.rating, 0) desc,
                coalesce(base.rating_count, 0) desc,
                base.name asc,
                base.id
        ) as region_rank
    from base
    where base.region is not null
)
, global as (
    select
        'all'::text as region,
        base.id,
        base.name,
        base.category,
        base.lat,
        base.lon,
        base.address,
        base.display_location,
        base.halal_status,
        base.rating,
        base.rating_count,
        base.confidence,
        base.source,
        base.apple_place_id,
        base.note,
        base.source_raw,
        base.primary_image_url,
        row_number() over (
            order by
                coalesce(base.rating, 0) desc,
                coalesce(base.rating_count, 0) desc,
                base.name asc,
                base.id
        ) as region_rank
    from base
)
select
    ranked.region,
    ranked.region_rank,
    ranked.id,
    ranked.name,
    ranked.category,
    ranked.lat,
    ranked.lon,
    ranked.address,
    ranked.display_location,
    ranked.halal_status,
    ranked.rating,
    ranked.rating_count,
    ranked.confidence,
    ranked.source,
    ranked.apple_place_id,
    ranked.note,
    ranked.source_raw,
    ranked.primary_image_url
from (
    select * from regional where region_rank <= 40
    union all
    select * from global where region_rank <= 80
) ranked
order by
    case ranked.region when 'all' then 0 else 1 end,
    ranked.region,
    ranked.region_rank;

create unique index if not exists community_top_rated_v1_region_rank_idx
    on public.community_top_rated_v1 (region, region_rank);

create or replace function public.refresh_community_top_rated_v1()
returns void as $$
begin
    refresh materialized view concurrently public.community_top_rated_v1;
end;
$$ language plpgsql;

create or replace function public.get_community_top_rated(
    limit_per_region integer default 20
)
returns table (
    region text,
    region_rank integer,
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
    source_raw jsonb,
    primary_image_url text
)
as $$
    select
        ctr.region,
        ctr.region_rank,
        ctr.id,
        ctr.name,
        ctr.category,
        ctr.lat::double precision,
        ctr.lon::double precision,
        ctr.address,
        ctr.display_location,
        ctr.halal_status::text,
        ctr.rating::double precision,
        ctr.rating_count::integer,
        ctr.confidence::double precision,
        ctr.source,
        ctr.apple_place_id,
        ctr.note,
        ctr.source_raw,
        ctr.primary_image_url
    from public.community_top_rated_v1 ctr
    where ctr.region_rank <= least(greatest(limit_per_region, 1), 80)
    order by case ctr.region when 'all' then 0 else 1 end, ctr.region, ctr.region_rank;
$$ language sql stable;
