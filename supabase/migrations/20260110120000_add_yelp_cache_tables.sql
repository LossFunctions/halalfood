create schema if not exists extensions;
create extension if not exists pg_cron with schema extensions;

create table if not exists public.yelp_business_cache (
    yelp_id text primary key,
    rating numeric(3, 1),
    review_count integer,
    yelp_url text,
    fetched_at timestamptz not null,
    expires_at timestamptz not null,
    check (expires_at > fetched_at)
);

create table if not exists public.yelp_photo_cache (
    yelp_id text not null references public.yelp_business_cache (yelp_id) on delete cascade,
    position integer not null,
    photo_url text not null,
    attribution text,
    fetched_at timestamptz not null,
    expires_at timestamptz not null,
    primary key (yelp_id, position),
    check (expires_at > fetched_at)
);

create index if not exists yelp_business_cache_expires_at_idx
    on public.yelp_business_cache (expires_at);

create index if not exists yelp_photo_cache_expires_at_idx
    on public.yelp_photo_cache (expires_at);

alter table public.yelp_business_cache enable row level security;
alter table public.yelp_photo_cache enable row level security;

create policy "Allow read of non-expired yelp business cache"
    on public.yelp_business_cache
    for select
    using (expires_at > now());

create policy "Allow read of non-expired yelp photo cache"
    on public.yelp_photo_cache
    for select
    using (expires_at > now());

grant select on table public.yelp_business_cache to anon, authenticated;
grant select on table public.yelp_photo_cache to anon, authenticated;
grant all on table public.yelp_business_cache to service_role;
grant all on table public.yelp_photo_cache to service_role;

create or replace function public.purge_expired_yelp_cache()
returns void
language plpgsql
security definer
as $$
begin
    delete from public.yelp_photo_cache where expires_at < now();
    delete from public.yelp_business_cache where expires_at < now();
end;
$$;

do $$
begin
    if not exists (
        select 1 from cron.job where jobname = 'purge_expired_yelp_cache'
    ) then
        perform cron.schedule(
            'purge_expired_yelp_cache',
            '0 * * * *',
            'select public.purge_expired_yelp_cache();'
        );
    end if;
end $$;
