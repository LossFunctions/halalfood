create schema if not exists extensions;
create extension if not exists pg_cron with schema extensions;

create table if not exists public.google_place_cache (
    google_place_id text primary key,
    rating numeric(3, 1),
    review_count integer,
    business_status text,
    maps_url text,
    fetched_at timestamptz not null,
    expires_at timestamptz not null,
    check (expires_at > fetched_at)
);

create table if not exists public.google_photo_cache (
    google_place_id text not null references public.google_place_cache (google_place_id) on delete cascade,
    position integer not null,
    photo_reference text not null,
    attribution text,
    width integer,
    height integer,
    fetched_at timestamptz not null,
    expires_at timestamptz not null,
    primary key (google_place_id, position),
    check (expires_at > fetched_at)
);

create index if not exists google_place_cache_expires_at_idx
    on public.google_place_cache (expires_at);

create index if not exists google_photo_cache_expires_at_idx
    on public.google_photo_cache (expires_at);

alter table public.google_place_cache enable row level security;
alter table public.google_photo_cache enable row level security;

create policy "Allow read of non-expired google place cache"
    on public.google_place_cache
    for select
    using (expires_at > now());

create policy "Allow read of non-expired google photo cache"
    on public.google_photo_cache
    for select
    using (expires_at > now());

grant select on table public.google_place_cache to anon, authenticated;
grant select on table public.google_photo_cache to anon, authenticated;
grant all on table public.google_place_cache to service_role;
grant all on table public.google_photo_cache to service_role;

create or replace function public.purge_expired_google_cache()
returns void
language plpgsql
security definer
as $$
begin
    delete from public.google_photo_cache where expires_at < now();
    delete from public.google_place_cache where expires_at < now();
end;
$$;

do $$
begin
    if not exists (
        select 1 from cron.job where jobname = 'purge_expired_google_cache'
    ) then
        perform cron.schedule(
            'purge_expired_google_cache',
            '0 * * * *',
            'select public.purge_expired_google_cache();'
        );
    end if;
end $$;
