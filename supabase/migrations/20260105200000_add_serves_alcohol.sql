-- Add serves_alcohol to place and expose it in core RPCs.

alter table public.place
    add column if not exists serves_alcohol boolean;

drop function if exists public.get_places_in_bbox_v3(double precision, double precision, double precision, double precision, text, integer);
drop function if exists public.get_place_details(uuid);
drop function if exists public.get_place_details_by_ids(uuid[]);
drop function if exists public.search_places(text, text, integer);
drop function if exists public.search_places_v2(text, text, integer);

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
  confidence double precision,
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
    p.confidence::double precision,
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
  confidence double precision,
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
    p.confidence::double precision,
    p.serves_alcohol,
    p.source,
    p.apple_place_id,
    p.note,
    p.source_raw
  from public.place as p
  where p.id = any(p_place_ids)
    and p.status = 'published';
$function$;

CREATE OR REPLACE FUNCTION public.search_places(
    p_query text,
    p_normalized_query text DEFAULT NULL::text,
    p_limit integer DEFAULT 40
)
RETURNS TABLE(
    id uuid,
    name text,
    category text,
    lat double precision,
    lon double precision,
    address text,
    halal_status text,
    rating double precision,
    rating_count integer,
    confidence double precision,
    serves_alcohol boolean,
    source text,
    apple_place_id text,
    note text
)
LANGUAGE sql
STABLE PARALLEL SAFE
SET search_path TO 'public'
AS $function$
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
         p.halal_status, p.rating, p.rating_count, p.confidence, p.serves_alcohol,
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
           p.confidence desc nulls last,
           p.name asc
  limit (select resolved_limit from input);
$function$;

CREATE OR REPLACE FUNCTION public.search_places_v2(
    p_query text,
    p_normalized_query text DEFAULT NULL::text,
    p_limit integer DEFAULT 40
)
RETURNS TABLE(
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
    source text,
    apple_place_id text,
    note text
)
LANGUAGE sql
STABLE PARALLEL SAFE
SET search_path TO 'public'
AS $function$
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
         p.halal_status, p.rating, p.rating_count, p.confidence, p.serves_alcohol,
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
           p.confidence desc nulls last,
           p.name asc
  limit (select resolved_limit from input);
$function$;
