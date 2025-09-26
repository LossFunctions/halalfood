-- Idempotent schema for `place` table and RPC used by the iOS app.
-- Safe to run multiple times; it will add any missing columns/indexes/policies.

-- Enable pgcrypto for gen_random_uuid if not enabled
create extension if not exists pgcrypto;
create extension if not exists postgis;

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
      halal_status text check (halal_status in ('unknown','yes','only','no')),
      rating double precision,
      rating_count integer,
      confidence double precision,
      source text default 'osm' not null,
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
      execute $$alter table public.place add column geog geography(Point,4326) generated always as (
        ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography
      ) stored$$;
    end if;
  end if;
end$$;

create unique index if not exists place_source_external_uidx on public.place (source, external_id);
create index if not exists place_geog_gix on public.place using gist (geog);
create index if not exists place_category_idx on public.place (category);
create index if not exists place_status_idx on public.place (status);

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
  source text
)
language sql stable parallel safe as $$
  select p.id, p.name, p.category, p.lat, p.lon, p.address, p.halal_status,
         p.rating, p.rating_count, p.confidence, p.source
  from public.place as p
  where p.status = 'published'
    and (cat = 'all' or p.category = cat)
    and ST_Intersects(p.geog::geometry, ST_MakeEnvelope(west, south, east, north, 4326))
  order by p.rating desc nulls last, p.confidence desc nulls last, p.name asc
  limit greatest(1, least(max_count, 1000));
$$;

grant execute on function public.get_places_in_bbox(double precision,double precision,double precision,double precision,text,integer)
  to anon, authenticated;

-- Optional: convenience view for manual browsing
create or replace view public.place_preview as
  select id, name, category, lat, lon, address, halal_status, rating, rating_count, source, status
  from public.place;
