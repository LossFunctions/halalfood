-- Add cc_certifier_org to all RPC functions and views that return place data

-- Drop existing functions to recreate with new column
drop function if exists public.get_places_in_bbox_v3(
    double precision,
    double precision,
    double precision,
    double precision,
    text,
    integer
);
drop function if exists public.get_place_details(uuid);
drop function if exists public.get_place_details_by_ids(uuid[]);
drop function if exists public.search_places(text, text, integer);
drop function if exists public.search_places_v2(text, text, integer);
drop function if exists public.get_community_top_rated(integer);
drop materialized view if exists public.community_top_rated_v1;

-- Recreate materialized view with cc_certifier_org
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
        pl.serves_alcohol,
        pl.source,
        pl.google_place_id,
        pl.google_match_status,
        pl.google_maps_url,
        pl.google_business_status,
        pl.apple_place_id,
        pl.note,
        pl.cc_certifier_org,
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
      and pl.google_match_status = 'matched'
      and pl.google_place_id is not null
      and (pl.google_business_status is null or pl.google_business_status = 'OPERATIONAL')
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
        base.serves_alcohol,
        base.source,
        base.google_place_id,
        base.google_match_status,
        base.google_maps_url,
        base.google_business_status,
        base.apple_place_id,
        base.note,
        base.cc_certifier_org,
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
        base.serves_alcohol,
        base.source,
        base.google_place_id,
        base.google_match_status,
        base.google_maps_url,
        base.google_business_status,
        base.apple_place_id,
        base.note,
        base.cc_certifier_org,
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
    ranked.serves_alcohol,
    ranked.source,
    ranked.google_place_id,
    ranked.google_match_status,
    ranked.google_maps_url,
    ranked.google_business_status,
    ranked.apple_place_id,
    ranked.note,
    ranked.cc_certifier_org,
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

grant select on public.community_top_rated_v1 to anon, authenticated, service_role;

-- Recreate get_community_top_rated with cc_certifier_org
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
    serves_alcohol boolean,
    source text,
    google_place_id text,
    google_match_status text,
    google_maps_url text,
    google_business_status text,
    apple_place_id text,
    note text,
    cc_certifier_org text,
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
        ctr.serves_alcohol,
        ctr.source,
        ctr.google_place_id,
        ctr.google_match_status,
        ctr.google_maps_url,
        ctr.google_business_status,
        ctr.apple_place_id,
        ctr.note,
        ctr.cc_certifier_org,
        ctr.source_raw,
        ctr.primary_image_url
    from public.community_top_rated_v1 ctr
    where ctr.region_rank <= least(greatest(limit_per_region, 1), 80)
    order by case ctr.region when 'all' then 0 else 1 end, ctr.region, ctr.region_rank;
$$ language sql stable;

-- Recreate get_places_in_bbox_v3 with cc_certifier_org
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
    serves_alcohol boolean,
    source text,
    source_id text,
    external_id text,
    google_place_id text,
    google_match_status text,
    google_maps_url text,
    google_business_status text,
    note text,
    cc_certifier_org text
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
        pl.serves_alcohol,
        pl.source,
        pl.source_id,
        pl.external_id,
        pl.google_place_id,
        pl.google_match_status,
        pl.google_maps_url,
        pl.google_business_status,
        pl.note,
        pl.cc_certifier_org
    from public.place pl
    where pl.lat between south and north
      and pl.lon between west and east
      and pl.status = 'published'
      and (cat = 'all' or pl.category = cat)
      and pl.halal_status in ('yes', 'only')
      and pl.google_match_status = 'matched'
      and pl.google_place_id is not null
      and (pl.google_business_status is null or pl.google_business_status = 'OPERATIONAL')
    order by
        coalesce(pl.rating, 0) desc,
        coalesce(pl.rating_count, 0) desc,
        pl.id
    limit v_limit;
end;
$$ language plpgsql stable;

-- Recreate get_place_details with cc_certifier_org
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
  serves_alcohol boolean,
  source text,
  source_id text,
  external_id text,
  google_place_id text,
  google_match_status text,
  google_maps_url text,
  google_business_status text,
  apple_place_id text,
  note text,
  cc_certifier_org text,
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
    p.serves_alcohol,
    p.source,
    p.source_id,
    p.external_id,
    p.google_place_id,
    p.google_match_status,
    p.google_maps_url,
    p.google_business_status,
    p.apple_place_id,
    p.note,
    p.cc_certifier_org,
    p.source_raw
  from public.place as p
  where p.id = p_place_id
    and p.status = 'published'
    and p.google_match_status = 'matched'
    and p.google_place_id is not null
    and (p.google_business_status is null or p.google_business_status = 'OPERATIONAL');
$function$;

-- Recreate get_place_details_by_ids with cc_certifier_org
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
  serves_alcohol boolean,
  source text,
  source_id text,
  external_id text,
  google_place_id text,
  google_match_status text,
  google_maps_url text,
  google_business_status text,
  apple_place_id text,
  note text,
  cc_certifier_org text,
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
    p.serves_alcohol,
    p.source,
    p.source_id,
    p.external_id,
    p.google_place_id,
    p.google_match_status,
    p.google_maps_url,
    p.google_business_status,
    p.apple_place_id,
    p.note,
    p.cc_certifier_org,
    p.source_raw
  from public.place as p
  where p.id = any(p_place_ids)
    and p.status = 'published'
    and p.google_match_status = 'matched'
    and p.google_place_id is not null
    and (p.google_business_status is null or p.google_business_status = 'OPERATIONAL');
$function$;

-- Recreate search_places with cc_certifier_org
create or replace function public.search_places(
    p_query text,
    p_normalized_query text default null::text,
    p_limit integer default 40
)
returns table(
    id uuid,
    name text,
    category text,
    lat double precision,
    lon double precision,
    address text,
    halal_status text,
    rating double precision,
    rating_count integer,
    serves_alcohol boolean,
    source text,
    source_id text,
    external_id text,
    google_place_id text,
    google_match_status text,
    google_maps_url text,
    google_business_status text,
    apple_place_id text,
    note text,
    cc_certifier_org text
)
language sql
stable parallel safe
set search_path to 'public'
as $function$
  with input as (
    select
      coalesce(trim(p_query), '') as raw_query,
      case
        when coalesce(trim(p_normalized_query), '') <> '' then lower(trim(p_normalized_query))
        else public.normalize_text(p_query)
      end as norm_query,
      greatest(1, least(coalesce(p_limit, 40), 1000)) as resolved_limit
  )
  select p.id, p.name, p.category, p.lat, p.lon, p.address,
         p.halal_status, p.rating, p.rating_count, p.serves_alcohol,
         p.source, p.source_id, p.external_id, p.google_place_id,
         p.google_match_status, p.google_maps_url, p.google_business_status,
         p.apple_place_id, p.note, p.cc_certifier_org
  from public.place as p
  cross join input as i
  where p.status = 'published'
    and p.halal_status in ('yes', 'only')
    and p.google_match_status = 'matched'
    and p.google_place_id is not null
    and (p.google_business_status is null or p.google_business_status = 'OPERATIONAL')
    and (
      (i.raw_query <> '' and (
        p.name ilike '%' || i.raw_query || '%' or
        (p.address is not null and p.address ilike '%' || i.raw_query || '%')
      ))
      or (i.norm_query <> '' and (
        p.name_normalized like '%' || i.norm_query || '%' or
        (p.address_normalized is not null and p.address_normalized like '%' || i.norm_query || '%')
      ))
    )
  order by p.rating desc nulls last,
           p.rating_count desc nulls last,
           p.name asc
  limit (select resolved_limit from input);
$function$;

-- Recreate search_places_v2 with cc_certifier_org
create or replace function public.search_places_v2(
    p_query text,
    p_normalized_query text default null::text,
    p_limit integer default 40
)
returns table(
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
    serves_alcohol boolean,
    source text,
    source_id text,
    external_id text,
    google_place_id text,
    google_match_status text,
    google_maps_url text,
    google_business_status text,
    apple_place_id text,
    note text,
    cc_certifier_org text
)
language sql
stable parallel safe
set search_path to 'public'
as $function$
  with input as (
    select
      coalesce(trim(p_query), '') as raw_query,
      case
        when coalesce(trim(p_normalized_query), '') <> '' then lower(trim(p_normalized_query))
        else public.normalize_text(p_query)
      end as norm_query,
      greatest(1, least(coalesce(p_limit, 40), 1000)) as resolved_limit
  )
  select p.id, p.name, p.category, p.lat, p.lon, p.address, p.display_location,
         p.halal_status, p.rating, p.rating_count, p.serves_alcohol,
         p.source, p.source_id, p.external_id, p.google_place_id,
         p.google_match_status, p.google_maps_url, p.google_business_status,
         p.apple_place_id, p.note, p.cc_certifier_org
  from public.place as p
  cross join input as i
  where p.status = 'published'
    and p.halal_status in ('yes', 'only')
    and p.google_match_status = 'matched'
    and p.google_place_id is not null
    and (p.google_business_status is null or p.google_business_status = 'OPERATIONAL')
    and (
      (i.raw_query <> '' and (
        p.name ilike '%' || i.raw_query || '%' or
        (p.address is not null and p.address ilike '%' || i.raw_query || '%')
      ))
      or (i.norm_query <> '' and (
        p.name_normalized like '%' || i.norm_query || '%' or
        (p.address_normalized is not null and p.address_normalized like '%' || i.norm_query || '%')
      ))
    )
  order by p.rating desc nulls last,
           p.rating_count desc nulls last,
           p.name asc
  limit (select resolved_limit from input);
$function$;
