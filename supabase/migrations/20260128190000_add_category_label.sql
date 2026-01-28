-- Add normalized category label derived from source_raw categories.

alter table public.place
    add column if not exists category_label text;

create or replace function public.normalize_category_label(input text)
returns text
language sql
immutable
set search_path = public
as $$
    select case
        when input is null then null
        when btrim(input) = '' then null
        when lower(input) = 'breakfast_brunch' then 'Breakfast / Brunch'
        when lower(input) = 'thai' then 'Thai'
        when lower(input) = 'lebanese' then 'Lebanese'
        when lower(input) = 'mediterranean' then 'Mediterranean'
        when lower(input) = 'turkish' then 'Turkish'
        when lower(input) = 'middleeastern' then 'Middle Eastern'
        when lower(input) = 'arabian' then 'Middle Eastern'
        when lower(input) = 'indpak' then 'Indian'
        when lower(input) = 'indian' then 'Indian'
        when lower(input) = 'pakistani' then 'Pakistani'
        when lower(input) = 'bangladeshi' then 'Bangladeshi'
        when lower(input) = 'afghani' then 'Afghan'
        when lower(input) = 'himalayan' then 'Himalayan'
        when lower(input) = 'nepalese' then 'Nepalese'
        when lower(input) = 'chinese' then 'Chinese'
        when lower(input) = 'japanese' then 'Japanese'
        when lower(input) = 'korean' then 'Korean'
        when lower(input) = 'vietnamese' then 'Vietnamese'
        when lower(input) = 'italian' then 'Italian'
        when lower(input) = 'mexican' then 'Mexican'
        when lower(input) = 'ethiopian' then 'Ethiopian'
        when lower(input) = 'persian' then 'Persian'
        when lower(input) = 'iranian' then 'Persian'
        when lower(input) = 'uzbek' then 'Uzbek'
        when lower(input) = 'bbq' then 'BBQ'
        when lower(input) = 'pizza' then 'Pizza'
        when lower(input) = 'burgers' then 'Burgers'
        when lower(input) = 'sandwiches' then 'Sandwiches'
        when lower(input) = 'seafood' then 'Seafood'
        when lower(input) = 'chicken_wings' then 'Chicken Wings'
        else initcap(replace(replace(lower(input), '-', ' '), '_', ' / '))
    end;
$$;

create or replace function public.derive_category_label(source_raw jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
    cat text;
begin
    if source_raw is null or coalesce(jsonb_typeof(source_raw->'categories'), '') <> 'array' then
        return null;
    end if;

    for cat in select value from jsonb_array_elements_text(source_raw->'categories') as value loop
        cat := lower(trim(both from cat));
        if cat is null or cat = '' then
            continue;
        end if;
        if cat = any (array[
            'halal','gluten_free','vegan','vegetarian',
            'coffee','cafes','coffeeandtea','tea','bubbletea',
            'desserts','donuts','bakeries','icecream',
            'bars','cocktailbars','beerbar','wine_bars'
        ]) then
            continue;
        end if;
        return public.normalize_category_label(cat);
    end loop;

    return null;
end;
$$;

create or replace function public.set_category_label_if_missing()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if new.category_label is null or btrim(new.category_label) = '' then
        new.category_label := public.derive_category_label(new.source_raw);
    end if;
    return new;
end;
$$;

drop trigger if exists place_category_label_fill on public.place;
create trigger place_category_label_fill
before insert or update of source_raw, category_label on public.place
for each row
execute function public.set_category_label_if_missing();

update public.place
set category_label = public.derive_category_label(source_raw)
where category_label is null or btrim(category_label) = '';

-- Drop existing RPCs/views so return types can change safely.
drop function if exists public.get_places_in_bbox_v3(
    double precision,
    double precision,
    double precision,
    double precision,
    text,
    integer
);
drop function if exists public.search_places(text, text, integer);
drop function if exists public.search_places_v2(text, text, integer);
drop function if exists public.get_place_details(uuid);
drop function if exists public.get_place_details_by_ids(uuid[]);
drop function if exists public.get_community_top_rated(integer);
drop materialized view if exists public.community_top_rated_v1;

create materialized view public.community_top_rated_v1 as
with region_places as (
    select
        case
            when p.address ilike '%New York%' or p.address ilike '%NY %' or p.address ilike '%, NY' then 'nyc'
            when p.address ilike '%New Jersey%' or p.address ilike '%NJ %' or p.address ilike '%, NJ' then 'nj'
            when p.address ilike '%Connecticut%' or p.address ilike '%CT %' or p.address ilike '%, CT' then 'ct'
            else 'other'
        end as region,
        p.id,
        p.name,
        p.category,
        p.category_label,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
        p.serves_alcohol,
        p.source,
        p.google_place_id,
        p.google_match_status,
        p.google_maps_url,
        p.google_business_status,
        p.apple_place_id,
        p.note,
        p.cc_certifier_org,
        p.source_raw,
        row_number() over (
            partition by
                case
                    when p.address ilike '%New York%' or p.address ilike '%NY %' or p.address ilike '%, NY' then 'nyc'
                    when p.address ilike '%New Jersey%' or p.address ilike '%NJ %' or p.address ilike '%, NJ' then 'nj'
                    when p.address ilike '%Connecticut%' or p.address ilike '%CT %' or p.address ilike '%, CT' then 'ct'
                    else 'other'
                end
            order by p.rating desc nulls last, p.rating_count desc nulls last
        ) as region_rank
    from public.place p
    where p.status = 'published'
      and p.halal_status in ('yes', 'only')
      and p.category = 'restaurant'
      and p.rating is not null
      and p.rating >= 4.0
      and (p.google_business_status is null or p.google_business_status <> 'CLOSED_PERMANENTLY')
)
select
    region,
    region_rank::integer,
    id,
    name,
    category,
    category_label,
    lat,
    lon,
    address,
    display_location,
    halal_status,
    rating,
    rating_count,
    serves_alcohol,
    source,
    google_place_id,
    google_match_status,
    google_maps_url,
    google_business_status,
    apple_place_id,
    note,
    cc_certifier_org,
    source_raw,
    null::text as primary_image_url
from region_places
where region_rank <= 100;

create index if not exists idx_community_top_rated_v1_region
on public.community_top_rated_v1 (region, region_rank);

grant select on public.community_top_rated_v1 to anon, authenticated, service_role;

create or replace function public.get_community_top_rated(
    limit_per_region integer default 20
)
returns table (
    region text,
    region_rank integer,
    id uuid,
    name text,
    category text,
    category_label text,
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
language sql stable
as $$
    select
        ctr.region,
        ctr.region_rank,
        ctr.id,
        ctr.name,
        ctr.category,
        ctr.category_label,
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
$$;

create or replace function public.get_places_in_bbox_v3(
    west double precision,
    south double precision,
    east double precision,
    north double precision,
    cat text default 'all',
    max_count integer default 200
)
returns table (
    id uuid,
    name text,
    category text,
    category_label text,
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
language sql stable
as $$
    select
        p.id,
        p.name,
        p.category,
        p.category_label,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
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
    from public.place p
    where p.status = 'published'
      and p.halal_status in ('yes', 'only')
      and (p.google_business_status is null or p.google_business_status <> 'CLOSED_PERMANENTLY')
      and p.lon between west and east
      and p.lat between south and north
      and (cat = 'all' or p.category = cat)
    order by p.rating desc nulls last
    limit max_count;
$$;

create or replace function public.search_places(
    p_query text,
    p_normalized_query text,
    p_limit integer default 40
)
returns table (
    id uuid,
    name text,
    category text,
    category_label text,
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
language sql stable
as $$
    select
        p.id,
        p.name,
        p.category,
        p.category_label,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
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
        p.cc_certifier_org
    from public.place p
    where p.status = 'published'
      and p.halal_status in ('yes', 'only')
      and (p.google_business_status is null or p.google_business_status <> 'CLOSED_PERMANENTLY')
      and (
          p.name ilike '%' || p_query || '%'
          or p.address ilike '%' || p_query || '%'
      )
    order by p.rating desc nulls last
    limit p_limit;
$$;

create or replace function public.search_places_v2(
    p_query text,
    p_normalized_query text,
    p_limit integer default 40
)
returns table (
    id uuid,
    name text,
    category text,
    category_label text,
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
language sql stable
as $$
    select
        p.id,
        p.name,
        p.category,
        p.category_label,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
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
        p.cc_certifier_org
    from public.place p
    where p.status = 'published'
      and p.halal_status in ('yes', 'only')
      and (p.google_business_status is null or p.google_business_status <> 'CLOSED_PERMANENTLY')
      and (
          p.name ilike '%' || p_query || '%'
          or p.address ilike '%' || p_query || '%'
          or p.display_location ilike '%' || p_query || '%'
      )
    order by p.rating desc nulls last
    limit p_limit;
$$;

create or replace function public.get_place_details(p_place_id uuid)
returns table(
    id uuid,
    name text,
    category text,
    category_label text,
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
language sql stable
as $$
    select
        p.id,
        p.name,
        p.category,
        p.category_label,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
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
        p.cc_certifier_org
    from public.place p
    where p.id = p_place_id
      and p.status = 'published'
      and (p.google_business_status is null or p.google_business_status <> 'CLOSED_PERMANENTLY');
$$;

create or replace function public.get_place_details_by_ids(p_place_ids uuid[])
returns table(
    id uuid,
    name text,
    category text,
    category_label text,
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
language sql stable
as $$
    select
        p.id,
        p.name,
        p.category,
        p.category_label,
        p.lat,
        p.lon,
        p.address,
        p.display_location,
        p.halal_status,
        p.rating,
        p.rating_count,
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
        p.cc_certifier_org
    from public.place p
    where p.id = any(p_place_ids)
      and p.status = 'published'
      and (p.google_business_status is null or p.google_business_status <> 'CLOSED_PERMANENTLY');
$$;

refresh materialized view public.community_top_rated_v1;

grant execute on function public.get_places_in_bbox_v3(
    double precision,
    double precision,
    double precision,
    double precision,
    text,
    integer
) to anon, authenticated, service_role;

grant execute on function public.search_places(text, text, integer)
    to anon, authenticated, service_role;

grant execute on function public.search_places_v2(text, text, integer)
    to anon, authenticated, service_role;

grant execute on function public.get_place_details(uuid)
    to anon, authenticated, service_role;

grant execute on function public.get_place_details_by_ids(uuid[])
    to anon, authenticated, service_role;

grant execute on function public.get_community_top_rated(integer)
    to anon, authenticated, service_role;
