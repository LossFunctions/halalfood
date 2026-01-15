-- Remove legacy confidence column and strip it from RPCs/views.

drop materialized view if exists public.community_top_rated_v1;

alter table public.place
    drop column if exists confidence;

drop function if exists public.get_community_top_rated(integer);
drop function if exists public.get_places_in_bbox_v3(double precision, double precision, double precision, double precision, text, integer);
drop function if exists public.get_place_details(uuid);
drop function if exists public.get_place_details_by_ids(uuid[]);
drop function if exists public.search_places(text, text, integer);
drop function if exists public.search_places_v2(text, text, integer);

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
        ctr.source,
        ctr.apple_place_id,
        ctr.note,
        ctr.source_raw,
        ctr.primary_image_url
    from public.community_top_rated_v1 ctr
    where ctr.region_rank <= least(greatest(limit_per_region, 1), 80)
    order by case ctr.region when 'all' then 0 else 1 end, ctr.region, ctr.region_rank;
$$ language sql stable;

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
    note text
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
        pl.note
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
    p.serves_alcohol,
    p.source,
    p.apple_place_id,
    p.note,
    p.source_raw
  from public.place as p
  where p.id = p_place_id
    and p.status = 'published';
$function$;

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
    p.serves_alcohol,
    p.source,
    p.apple_place_id,
    p.note,
    p.source_raw
  from public.place as p
  where p.id = any(p_place_ids)
    and p.status = 'published';
$function$;

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
    apple_place_id text,
    note text
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
         p.source, p.apple_place_id, p.note
  from public.place as p
  cross join input as i
  where p.status = 'published'
    and p.halal_status in ('yes', 'only')
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
    apple_place_id text,
    note text
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
         p.source, p.apple_place_id, p.note
  from public.place as p
  cross join input as i
  where p.status = 'published'
    and p.halal_status in ('yes', 'only')
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

drop function if exists public.upsert_apple_place(
  text, text, double precision, double precision, text, text, text, double precision, integer, double precision
);
drop function if exists public.upsert_apple_place(
  text, text, double precision, double precision, text, text, double precision, integer, double precision
);

create or replace function public.upsert_apple_place(
  p_apple_place_id text,
  p_name text,
  p_lat double precision,
  p_lon double precision,
  p_address text default null,
  p_display_location text default null,
  p_halal_status text default 'unknown',
  p_rating double precision default null,
  p_rating_count integer default null
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
  source text,
  apple_place_id text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_external_id text;
  v_halal text;
  v_trimmed_address text;
  v_display_location text;
begin
  if coalesce(trim(p_apple_place_id), '') = '' then
    raise exception 'apple_place_id must be provided';
  end if;

  if coalesce(trim(p_name), '') = '' then
    raise exception 'name must be provided';
  end if;

  v_external_id := 'apple:' || lower(trim(p_apple_place_id));
  v_halal := lower(coalesce(p_halal_status, 'unknown'));
  if v_halal not in ('unknown', 'yes', 'only', 'no') then
    v_halal := 'unknown';
  end if;

  v_trimmed_address := nullif(trim(p_address), '');
  v_display_location := public.normalize_display_location(p_display_location);

  return query
    insert into public.place as tgt (
      name,
      category,
      lat,
      lon,
      address,
      display_location,
      halal_status,
      rating,
      rating_count,
      source,
      apple_place_id,
      external_id,
      status
    ) values (
      p_name,
      'restaurant',
      p_lat,
      p_lon,
      v_trimmed_address,
      v_display_location,
      v_halal,
      p_rating,
      p_rating_count,
      'apple',
      trim(p_apple_place_id),
      v_external_id,
      'published'
    )
    on conflict (source, external_id) do update
      set name = excluded.name,
          lat = excluded.lat,
          lon = excluded.lon,
          address = coalesce(excluded.address, tgt.address),
          display_location = coalesce(excluded.display_location, tgt.display_location),
          halal_status = excluded.halal_status,
          rating = coalesce(excluded.rating, tgt.rating),
          rating_count = coalesce(excluded.rating_count, tgt.rating_count),
          apple_place_id = excluded.apple_place_id,
          source = 'apple',
          status = 'published'
    returning tgt.id, tgt.name, tgt.category, tgt.lat, tgt.lon, tgt.address,
              tgt.display_location, tgt.halal_status, tgt.rating, tgt.rating_count,
              tgt.source, tgt.apple_place_id;
end;
$$;

grant execute on function public.upsert_apple_place(
  text, text, double precision, double precision, text, text, text, double precision, integer
) to anon, authenticated;
