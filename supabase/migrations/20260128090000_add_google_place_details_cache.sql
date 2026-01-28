alter table public.google_place_cache
    add column if not exists phone_number text,
    add column if not exists website_url text,
    add column if not exists formatted_address text,
    add column if not exists opening_hours jsonb,
    add column if not exists details_version smallint default 1;
