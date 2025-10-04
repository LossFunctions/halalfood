-- Idempotent schema for `place` table and RPC used by the iOS app.
-- Safe to run multiple times; it will add any missing columns/indexes/policies.

-- Enable pgcrypto for gen_random_uuid if not enabled
create extension if not exists pgcrypto;
create extension if not exists postgis;
create extension if not exists pg_trgm;
create extension if not exists unaccent;

create or replace function public.normalize_text(input text)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        when input is null then ''
        else lower(regexp_replace(unaccent(input), '[^a-z0-9]', '', 'g'))
    end;
$$;

do $$
begin
  if to_regclass('public.place') is null then
    create table public.place (
      id uuid primary key default gen_random_uuid(),
      name text not null,
      category text not null check (category in ('restaurant','mosque')),
      lat double precision not null,
      lon double precision not null,
      address text,
      name_normalized text generated always as (
        public.normalize_text(name)
      ) stored,
      address_normalized text generated always as (
        nullif(public.normalize_text(address), '')
      ) stored,
      halal_status text check (halal_status in ('unknown','yes','only','no')),
      rating double precision,
      rating_count integer,
      confidence double precision,
      source text default 'osm' not null,
      apple_place_id text,
      external_id text not null,
      source_raw jsonb,
      status text default 'published' not null,
      geog geography(Point,4326) generated always as (
        ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography
      ) stored
    );
  else
    -- Add any missing columns to an existing table
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='name') then
      alter table public.place add column name text not null default '(Unnamed)';
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='category') then
      alter table public.place add column category text not null default 'restaurant';
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='lat') then
      alter table public.place add column lat double precision;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='lon') then
      alter table public.place add column lon double precision;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='address') then
      alter table public.place add column address text;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='name_normalized') then
      alter table public.place add column name_normalized text generated always as (
        public.normalize_text(name)
      ) stored;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='address_normalized') then
      alter table public.place add column address_normalized text generated always as (
        nullif(public.normalize_text(address), '')
      ) stored;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='halal_status') then
      alter table public.place add column halal_status text;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='rating') then
      alter table public.place add column rating double precision;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='rating_count') then
      alter table public.place add column rating_count integer;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='confidence') then
      alter table public.place add column confidence double precision;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='source') then
      alter table public.place add column source text not null default 'seed';
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='apple_place_id') then
      alter table public.place add column apple_place_id text;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='external_id') then
      alter table public.place add column external_id text;
      update public.place set external_id = 'seed:' || id::text where external_id is null;
      alter table public.place alter column external_id set not null;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='source_raw') then
      alter table public.place add column source_raw jsonb;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='status') then
      alter table public.place add column status text not null default 'published';
    end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='place' and column_name='geog') then
      execute 'alter table public.place add column geog geography(Point,4326) generated always as (
        ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography
      ) stored';
    end if;
  end if;
end$$;

create unique index if not exists place_source_external_uidx on public.place (source, external_id);
create unique index if not exists place_apple_place_id_uidx on public.place (apple_place_id) where apple_place_id is not null;
create index if not exists place_geog_gix on public.place using gist (geog);
create index if not exists place_category_idx on public.place (category);
create index if not exists place_status_idx on public.place (status);
create index if not exists place_name_normalized_trgm_idx on public.place using gin (name_normalized gin_trgm_ops);
create index if not exists place_address_normalized_trgm_idx on public.place using gin (address_normalized gin_trgm_ops);

-- Basic RLS: readable by anon, writable by service role only
alter table public.place enable row level security;
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='place' and policyname='place_read_published'
  ) then
    create policy place_read_published on public.place for select
      using (status = 'published');
  end if;
end$$;

-- Function used by the app: rest/v1/rpc/get_places_in_bbox
drop function if exists public.get_places_in_bbox(double precision,double precision,double precision,double precision,text,integer);
create or replace function public.get_places_in_bbox(
  west double precision,
  south double precision,
  east double precision,
  north double precision,
  cat text default 'all',
  max_count integer default 500
)
returns table (
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
  source text,
  apple_place_id text
)
language sql stable parallel safe as $$
  select p.id, p.name, p.category, p.lat, p.lon, p.address, p.halal_status,
         p.rating, p.rating_count, p.confidence, p.source, p.apple_place_id
  from public.place as p
  where p.status = 'published'
    and (cat = 'all' or p.category = cat)
    and ST_Intersects(p.geog::geometry, ST_MakeEnvelope(west, south, east, north, 4326))
  -- Sort by distance to the viewport center first to prioritize nearby places,
  -- then by rating/confidence for stability.
  order by
    ST_Distance(
      p.geog,
      ST_SetSRID(ST_MakePoint((west + east) / 2.0, (south + north) / 2.0), 4326)::geography
    ) asc,
    p.rating desc nulls last,
    p.confidence desc nulls last,
    p.name asc
  limit greatest(1, least(max_count, 1000));
$$;

grant execute on function public.get_places_in_bbox(double precision,double precision,double precision,double precision,text,integer)
  to anon, authenticated;

drop function if exists public.search_places(text, text, integer);
create or replace function public.search_places(
  p_query text,
  p_normalized_query text default null,
  p_limit integer default 40
)
returns table (
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
  source text,
  apple_place_id text
)
language sql
stable
parallel safe
set search_path = public
as $$
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
         p.halal_status, p.rating, p.rating_count, p.confidence, p.source, p.apple_place_id
  from public.place as p
  cross join input as i
  where p.status = 'published'
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
$$;

grant execute on function public.search_places(text, text, integer)
  to anon, authenticated;

-- Optional: convenience view for manual browsing
create or replace view public.place_preview as
  select id, name, category, lat, lon, address, halal_status, rating, rating_count, source, status
  from public.place;

-- Allow clients to persist Place IDs provided by Apple without exposing other writable fields.
create or replace function public.save_apple_place_id(
  p_place_id uuid,
  p_apple_place_id text
)
returns table (id uuid, apple_place_id text)
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_id text;
begin
  if p_apple_place_id is null or length(p_apple_place_id) = 0 then
    raise exception 'apple_place_id must be provided';
  end if;

  if p_apple_place_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'apple_place_id contains invalid characters';
  end if;

  trimmed_id := btrim(p_apple_place_id);

  return query
    update public.place as tgt
       set apple_place_id = trimmed_id
     where tgt.id = p_place_id
       and (tgt.apple_place_id is null or tgt.apple_place_id = trimmed_id)
     returning tgt.id, tgt.apple_place_id;
end;
$$;

grant execute on function public.save_apple_place_id(uuid, text) to anon, authenticated;

drop function if exists public.upsert_apple_place(text, text, double precision, double precision, text, text, double precision, integer, double precision);
create or replace function public.upsert_apple_place(
  p_apple_place_id text,
  p_name text,
  p_lat double precision,
  p_lon double precision,
  p_address text default null,
  p_halal_status text default 'unknown',
  p_rating double precision default null,
  p_rating_count integer default null,
  p_confidence double precision default null
)
returns table (
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

  return query
    insert into public.place as tgt (
      name,
      category,
      lat,
      lon,
      address,
      halal_status,
      rating,
      rating_count,
      confidence,
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
      v_halal,
      p_rating,
      p_rating_count,
      p_confidence,
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
          halal_status = excluded.halal_status,
          rating = coalesce(excluded.rating, tgt.rating),
          rating_count = coalesce(excluded.rating_count, tgt.rating_count),
          confidence = coalesce(excluded.confidence, tgt.confidence),
          apple_place_id = excluded.apple_place_id,
          source = 'apple',
          status = 'published'
    returning tgt.id, tgt.name, tgt.category, tgt.lat, tgt.lon, tgt.address,
              tgt.halal_status, tgt.rating, tgt.rating_count, tgt.confidence,
              tgt.source, tgt.apple_place_id;
end;
$$;

grant execute on function public.upsert_apple_place(text, text, double precision, double precision, text, text, double precision, integer, double precision)
  to anon, authenticated;
