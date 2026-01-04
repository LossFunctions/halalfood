drop extension if exists "pg_net";

create extension if not exists "pg_trgm" with schema "public";

create extension if not exists "postgis" with schema "public";

create extension if not exists "unaccent" with schema "public";

create type "public"."halal_status" as enum ('unknown', 'yes', 'only', 'no');

CREATE OR REPLACE FUNCTION public.normalize_text(input text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
    select case
        when input is null then ''
        else lower(regexp_replace(unaccent(input), '[^a-z0-9]', '', 'g'))
    end;
$function$
;


  create table "public"."place" (
    "id" uuid not null default gen_random_uuid(),
    "name" text not null,
    "category" text not null,
    "lat" double precision not null,
    "lon" double precision not null,
    "geom" public.geometry(Point,4326) generated always as (public.st_setsrid(public.st_makepoint(lon, lat), 4326)) stored,
    "address" text,
    "halal_status" public.halal_status default 'unknown'::public.halal_status,
    "open_hours_json" jsonb,
    "rating" numeric,
    "rating_count" integer,
    "price_tier" integer,
    "source" text,
    "source_id" text,
    "confidence" numeric default 0.5,
    "status" text default 'published'::text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now(),
    "geog" public.geography(Point,4326) generated always as ((public.st_setsrid(public.st_makepoint(lon, lat), 4326))::public.geography) stored,
    "external_id" text not null,
    "source_raw" jsonb,
    "name_normalized" text generated always as (public.normalize_text(name)) stored,
    "address_normalized" text generated always as (NULLIF(public.normalize_text(address), ''::text)) stored,
    "apple_place_id" text,
    "note" text,
    "display_location" text
      );


alter table "public"."place" enable row level security;


  create table "public"."place_photo" (
    "id" uuid not null default gen_random_uuid(),
    "place_id" uuid not null,
    "src" text not null,
    "external_id" text,
    "image_url" text not null,
    "width" integer,
    "height" integer,
    "priority" integer default 0,
    "attribution" text,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."place_photo" enable row level security;


  create table "public"."submission" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid,
    "payload" jsonb not null,
    "created_at" timestamp with time zone default now(),
    "status" text default 'pending'::text
      );


alter table "public"."submission" enable row level security;

CREATE INDEX place_address_normalized_trgm_idx ON public.place USING gin (address_normalized public.gin_trgm_ops);

CREATE UNIQUE INDEX place_apple_place_id_uidx ON public.place USING btree (apple_place_id) WHERE (apple_place_id IS NOT NULL);

CREATE INDEX place_cat_idx ON public.place USING btree (category);

CREATE INDEX place_category_idx ON public.place USING btree (category);

CREATE INDEX place_geog_gix ON public.place USING gist (geog);

CREATE INDEX place_gix ON public.place USING gist (geom);

CREATE INDEX place_halal_status_idx ON public.place USING btree (halal_status);

CREATE INDEX place_lat_lon_idx ON public.place USING btree (lat, lon);

CREATE INDEX place_name_normalized_trgm_idx ON public.place USING gin (name_normalized public.gin_trgm_ops);

CREATE UNIQUE INDEX place_photo_pkey ON public.place_photo USING btree (id);

CREATE INDEX place_photo_place_idx ON public.place_photo USING btree (place_id);

CREATE UNIQUE INDEX place_photo_src_ext_uidx ON public.place_photo USING btree (src, external_id) WHERE (external_id IS NOT NULL);

CREATE UNIQUE INDEX place_pkey ON public.place USING btree (id);

CREATE UNIQUE INDEX place_source_external_uidx ON public.place USING btree (source, external_id);

CREATE INDEX place_status_idx ON public.place USING btree (status);

CREATE UNIQUE INDEX submission_pkey ON public.submission USING btree (id);

alter table "public"."place" add constraint "place_pkey" PRIMARY KEY using index "place_pkey";

alter table "public"."place_photo" add constraint "place_photo_pkey" PRIMARY KEY using index "place_photo_pkey";

alter table "public"."submission" add constraint "submission_pkey" PRIMARY KEY using index "submission_pkey";

alter table "public"."place" add constraint "place_category_check" CHECK ((category = ANY (ARRAY['restaurant'::text, 'mosque'::text]))) not valid;

alter table "public"."place" validate constraint "place_category_check";

alter table "public"."place_photo" add constraint "place_photo_place_id_fkey" FOREIGN KEY (place_id) REFERENCES public.place(id) ON DELETE CASCADE not valid;

alter table "public"."place_photo" validate constraint "place_photo_place_id_fkey";

alter table "public"."place_photo" add constraint "place_photo_src_check" CHECK ((src = ANY (ARRAY['yelp'::text, 'apple'::text, 'user'::text]))) not valid;

alter table "public"."place_photo" validate constraint "place_photo_src_check";

alter table "public"."submission" add constraint "submission_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL not valid;

alter table "public"."submission" validate constraint "submission_user_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.community_region_for_place(lat double precision, lon double precision, address text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$
;

create materialized view "public"."community_top_rated_v1" as  WITH base AS (
         SELECT pl.id,
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
            photo.image_url AS primary_image_url,
            public.community_region_for_place(pl.lat, pl.lon, pl.address) AS region
           FROM (public.place pl
             LEFT JOIN LATERAL ( SELECT ph.image_url
                   FROM public.place_photo ph
                  WHERE (ph.place_id = pl.id)
                  ORDER BY COALESCE(ph.priority, 999), ph.id
                 LIMIT 1) photo ON (true))
          WHERE ((pl.status = 'published'::text) AND (pl.category = 'restaurant'::text) AND (pl.halal_status = ANY (ARRAY['yes'::public.halal_status, 'only'::public.halal_status])) AND (COALESCE(pl.rating, (0)::numeric) > (0)::numeric) AND (COALESCE(pl.rating_count, 0) >= 3))
        ), regional AS (
         SELECT base.region,
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
            row_number() OVER (PARTITION BY base.region ORDER BY COALESCE(base.rating, (0)::numeric) DESC, COALESCE(base.rating_count, 0) DESC, base.name, base.id) AS region_rank
           FROM base
          WHERE (base.region IS NOT NULL)
        ), global AS (
         SELECT 'all'::text AS region,
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
            row_number() OVER (ORDER BY COALESCE(base.rating, (0)::numeric) DESC, COALESCE(base.rating_count, 0) DESC, base.name, base.id) AS region_rank
           FROM base
        )
 SELECT region,
    region_rank,
    id,
    name,
    category,
    lat,
    lon,
    address,
    display_location,
    halal_status,
    rating,
    rating_count,
    confidence,
    source,
    apple_place_id,
    note,
    source_raw,
    primary_image_url
   FROM ( SELECT regional.region,
            regional.id,
            regional.name,
            regional.category,
            regional.lat,
            regional.lon,
            regional.address,
            regional.display_location,
            regional.halal_status,
            regional.rating,
            regional.rating_count,
            regional.confidence,
            regional.source,
            regional.apple_place_id,
            regional.note,
            regional.source_raw,
            regional.primary_image_url,
            regional.region_rank
           FROM regional
          WHERE (regional.region_rank <= 40)
        UNION ALL
         SELECT global.region,
            global.id,
            global.name,
            global.category,
            global.lat,
            global.lon,
            global.address,
            global.display_location,
            global.halal_status,
            global.rating,
            global.rating_count,
            global.confidence,
            global.source,
            global.apple_place_id,
            global.note,
            global.source_raw,
            global.primary_image_url,
            global.region_rank
           FROM global
          WHERE (global.region_rank <= 80)) ranked
  ORDER BY
        CASE region
            WHEN 'all'::text THEN 0
            ELSE 1
        END, region, region_rank;


CREATE OR REPLACE FUNCTION public.get_community_top_rated(limit_per_region integer DEFAULT 20)
 RETURNS TABLE(region text, region_rank integer, id uuid, name text, category text, lat double precision, lon double precision, address text, display_location text, halal_status text, rating double precision, rating_count integer, confidence double precision, source text, apple_place_id text, note text, source_raw jsonb, primary_image_url text)
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.get_places_in_bbox(west double precision, south double precision, east double precision, north double precision, cat text DEFAULT 'all'::text, max_count integer DEFAULT 500)
 RETURNS TABLE(id uuid, name text, category text, lat double precision, lon double precision, address text, halal_status text, rating double precision, rating_count integer, confidence double precision, source text, apple_place_id text, note text)
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
  select p.id, p.name, p.category, p.lat, p.lon, p.address, p.halal_status,
         p.rating, p.rating_count, p.confidence, p.source, p.apple_place_id, p.note
  from public.place as p
  where p.status = 'published'
    and p.halal_status in ('yes', 'only')
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
$function$
;

CREATE OR REPLACE FUNCTION public.get_places_in_bbox_v2(west double precision, south double precision, east double precision, north double precision, cat text DEFAULT 'all'::text, max_count integer DEFAULT 500)
 RETURNS TABLE(id uuid, name text, category text, lat double precision, lon double precision, address text, display_location text, halal_status text, rating double precision, rating_count integer, confidence double precision, source text, apple_place_id text, note text)
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
  select p.id, p.name, p.category, p.lat, p.lon, p.address, p.display_location, p.halal_status,
         p.rating, p.rating_count, p.confidence, p.source, p.apple_place_id, p.note
  from public.place as p
  where p.status = 'published'
    and p.halal_status in ('yes', 'only')
    and (cat = 'all' or p.category = cat)
    and ST_Intersects(p.geog::geometry, ST_MakeEnvelope(west, south, east, north, 4326))
  order by
    ST_Distance(
      p.geog,
      ST_SetSRID(ST_MakePoint((west + east) / 2.0, (south + north) / 2.0), 4326)::geography
    ) asc,
    p.rating desc nulls last,
    p.confidence desc nulls last,
    p.name asc
  limit greatest(1, least(max_count, 1000));
$function$
;

CREATE OR REPLACE FUNCTION public.get_places_in_bbox_v3(west double precision, south double precision, east double precision, north double precision, cat text DEFAULT 'all'::text, max_count integer DEFAULT 300)
 RETURNS TABLE(id uuid, name text, category text, lat double precision, lon double precision, address text, display_location text, halal_status text, rating double precision, rating_count integer, confidence double precision, source text)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.normalize_display_location(input text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
    select case
        when input is null then null
        else nullif(regexp_replace(trim(input), '\s+', ' ', 'g'), '')
    end;
$function$
;

CREATE OR REPLACE FUNCTION public.place_display_location_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_display text;
begin
  v_display := public.normalize_display_location(
    coalesce(new.display_location, (new.source_raw ->> 'display_location'))
  );
  new.display_location := v_display;

  if v_display is not null then
    new.source_raw := coalesce(new.source_raw, '{}'::jsonb);
    new.source_raw := jsonb_set(new.source_raw, '{display_location}', to_jsonb(v_display), true);
  elsif new.source_raw ? 'display_location' then
    new.source_raw := new.source_raw - 'display_location';
  end if;

  return new;
end;
$function$
;

create or replace view "public"."place_preview" as  SELECT id,
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
    status,
    note
   FROM public.place;


CREATE OR REPLACE FUNCTION public.refresh_community_top_rated_v1()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
begin
    refresh materialized view concurrently public.community_top_rated_v1;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.save_apple_place_id(p_place_id uuid, p_apple_place_id text)
 RETURNS TABLE(id uuid, apple_place_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.search_places(p_query text, p_normalized_query text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS TABLE(id uuid, name text, category text, lat double precision, lon double precision, address text, halal_status text, rating double precision, rating_count integer, confidence double precision, source text, apple_place_id text, note text)
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
         p.halal_status, p.rating, p.rating_count, p.confidence, p.source, p.apple_place_id, p.note
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
$function$
;

CREATE OR REPLACE FUNCTION public.search_places_v2(p_query text, p_normalized_query text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS TABLE(id uuid, name text, category text, lat double precision, lon double precision, address text, display_location text, halal_status text, rating double precision, rating_count integer, confidence double precision, source text, apple_place_id text, note text)
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
         p.halal_status, p.rating, p.rating_count, p.confidence, p.source, p.apple_place_id, p.note
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
$function$
;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.upsert_apple_place(p_apple_place_id text, p_name text, p_lat double precision, p_lon double precision, p_address text DEFAULT NULL::text, p_display_location text DEFAULT NULL::text, p_halal_status text DEFAULT 'unknown'::text, p_rating double precision DEFAULT NULL::double precision, p_rating_count integer DEFAULT NULL::integer, p_confidence double precision DEFAULT NULL::double precision)
 RETURNS TABLE(id uuid, name text, category text, lat double precision, lon double precision, address text, display_location text, halal_status text, rating double precision, rating_count integer, confidence double precision, source text, apple_place_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      v_display_location,
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
          display_location = coalesce(excluded.display_location, tgt.display_location),
          halal_status = excluded.halal_status,
          rating = coalesce(excluded.rating, tgt.rating),
          rating_count = coalesce(excluded.rating_count, tgt.rating_count),
          confidence = coalesce(excluded.confidence, tgt.confidence),
          apple_place_id = excluded.apple_place_id,
          source = 'apple',
          status = 'published'
    returning tgt.id, tgt.name, tgt.category, tgt.lat, tgt.lon, tgt.address,
              tgt.display_location, tgt.halal_status, tgt.rating, tgt.rating_count, tgt.confidence,
              tgt.source, tgt.apple_place_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.upsert_apple_place(p_apple_place_id text, p_name text, p_lat double precision, p_lon double precision, p_address text DEFAULT NULL::text, p_halal_status text DEFAULT 'unknown'::text, p_rating double precision DEFAULT NULL::double precision, p_rating_count integer DEFAULT NULL::integer, p_confidence double precision DEFAULT NULL::double precision)
 RETURNS TABLE(id uuid, name text, category text, lat double precision, lon double precision, address text, halal_status text, rating double precision, rating_count integer, confidence double precision, source text, apple_place_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;

CREATE UNIQUE INDEX community_top_rated_v1_region_rank_idx ON public.community_top_rated_v1 USING btree (region, region_rank);

grant delete on table "public"."place" to "anon";

grant insert on table "public"."place" to "anon";

grant references on table "public"."place" to "anon";

grant select on table "public"."place" to "anon";

grant trigger on table "public"."place" to "anon";

grant truncate on table "public"."place" to "anon";

grant update on table "public"."place" to "anon";

grant delete on table "public"."place" to "authenticated";

grant insert on table "public"."place" to "authenticated";

grant references on table "public"."place" to "authenticated";

grant select on table "public"."place" to "authenticated";

grant trigger on table "public"."place" to "authenticated";

grant truncate on table "public"."place" to "authenticated";

grant update on table "public"."place" to "authenticated";

grant delete on table "public"."place" to "service_role";

grant insert on table "public"."place" to "service_role";

grant references on table "public"."place" to "service_role";

grant select on table "public"."place" to "service_role";

grant trigger on table "public"."place" to "service_role";

grant truncate on table "public"."place" to "service_role";

grant update on table "public"."place" to "service_role";

grant delete on table "public"."place_photo" to "anon";

grant insert on table "public"."place_photo" to "anon";

grant references on table "public"."place_photo" to "anon";

grant select on table "public"."place_photo" to "anon";

grant trigger on table "public"."place_photo" to "anon";

grant truncate on table "public"."place_photo" to "anon";

grant update on table "public"."place_photo" to "anon";

grant delete on table "public"."place_photo" to "authenticated";

grant insert on table "public"."place_photo" to "authenticated";

grant references on table "public"."place_photo" to "authenticated";

grant select on table "public"."place_photo" to "authenticated";

grant trigger on table "public"."place_photo" to "authenticated";

grant truncate on table "public"."place_photo" to "authenticated";

grant update on table "public"."place_photo" to "authenticated";

grant delete on table "public"."place_photo" to "service_role";

grant insert on table "public"."place_photo" to "service_role";

grant references on table "public"."place_photo" to "service_role";

grant select on table "public"."place_photo" to "service_role";

grant trigger on table "public"."place_photo" to "service_role";

grant truncate on table "public"."place_photo" to "service_role";

grant update on table "public"."place_photo" to "service_role";

grant delete on table "public"."spatial_ref_sys" to "anon";

grant insert on table "public"."spatial_ref_sys" to "anon";

grant references on table "public"."spatial_ref_sys" to "anon";

grant select on table "public"."spatial_ref_sys" to "anon";

grant trigger on table "public"."spatial_ref_sys" to "anon";

grant truncate on table "public"."spatial_ref_sys" to "anon";

grant update on table "public"."spatial_ref_sys" to "anon";

grant delete on table "public"."spatial_ref_sys" to "authenticated";

grant insert on table "public"."spatial_ref_sys" to "authenticated";

grant references on table "public"."spatial_ref_sys" to "authenticated";

grant select on table "public"."spatial_ref_sys" to "authenticated";

grant trigger on table "public"."spatial_ref_sys" to "authenticated";

grant truncate on table "public"."spatial_ref_sys" to "authenticated";

grant update on table "public"."spatial_ref_sys" to "authenticated";

grant delete on table "public"."spatial_ref_sys" to "postgres";

grant insert on table "public"."spatial_ref_sys" to "postgres";

grant references on table "public"."spatial_ref_sys" to "postgres";

grant select on table "public"."spatial_ref_sys" to "postgres";

grant trigger on table "public"."spatial_ref_sys" to "postgres";

grant truncate on table "public"."spatial_ref_sys" to "postgres";

grant update on table "public"."spatial_ref_sys" to "postgres";

grant delete on table "public"."spatial_ref_sys" to "service_role";

grant insert on table "public"."spatial_ref_sys" to "service_role";

grant references on table "public"."spatial_ref_sys" to "service_role";

grant select on table "public"."spatial_ref_sys" to "service_role";

grant trigger on table "public"."spatial_ref_sys" to "service_role";

grant truncate on table "public"."spatial_ref_sys" to "service_role";

grant update on table "public"."spatial_ref_sys" to "service_role";

grant delete on table "public"."submission" to "anon";

grant insert on table "public"."submission" to "anon";

grant references on table "public"."submission" to "anon";

grant select on table "public"."submission" to "anon";

grant trigger on table "public"."submission" to "anon";

grant truncate on table "public"."submission" to "anon";

grant update on table "public"."submission" to "anon";

grant delete on table "public"."submission" to "authenticated";

grant insert on table "public"."submission" to "authenticated";

grant references on table "public"."submission" to "authenticated";

grant select on table "public"."submission" to "authenticated";

grant trigger on table "public"."submission" to "authenticated";

grant truncate on table "public"."submission" to "authenticated";

grant update on table "public"."submission" to "authenticated";

grant delete on table "public"."submission" to "service_role";

grant insert on table "public"."submission" to "service_role";

grant references on table "public"."submission" to "service_role";

grant select on table "public"."submission" to "service_role";

grant trigger on table "public"."submission" to "service_role";

grant truncate on table "public"."submission" to "service_role";

grant update on table "public"."submission" to "service_role";


  create policy "Public read published places"
  on "public"."place"
  as permissive
  for select
  to public
using ((status = 'published'::text));



  create policy "place_read_published"
  on "public"."place"
  as permissive
  for select
  to public
using ((status = 'published'::text));



  create policy "place_photo_read"
  on "public"."place_photo"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.place p
  WHERE ((p.id = place_photo.place_id) AND (p.status = 'published'::text)))));



  create policy "Insert own submissions"
  on "public"."submission"
  as permissive
  for insert
  to public
with check ((auth.uid() = user_id));



  create policy "Read own submissions"
  on "public"."submission"
  as permissive
  for select
  to public
using ((auth.uid() = user_id));


CREATE TRIGGER place_display_location_sync BEFORE INSERT OR UPDATE ON public.place FOR EACH ROW EXECUTE FUNCTION public.place_display_location_sync();

CREATE TRIGGER trg_place_set_updated_at BEFORE UPDATE ON public.place FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
