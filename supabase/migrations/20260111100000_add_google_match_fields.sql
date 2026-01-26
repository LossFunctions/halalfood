-- Add Google matching metadata columns for review/QA.
alter table public.place
    add column if not exists google_place_id text,
    add column if not exists google_match_place_id text,
    add column if not exists google_match_status text,
    add column if not exists google_match_score numeric,
    add column if not exists google_match_distance_m integer,
    add column if not exists google_match_method text,
    add column if not exists google_match_reasons text,
    add column if not exists google_match_name text,
    add column if not exists google_match_address text,
    add column if not exists google_maps_url text,
    add column if not exists google_match_updated_at timestamp with time zone;

comment on column public.place.google_place_id is 'Verified Google Place ID (final match).';
comment on column public.place.google_match_place_id is 'Best candidate Google Place ID from matching.';
comment on column public.place.google_match_status is 'Match status: matched, review, unmatched, error.';
comment on column public.place.google_match_score is 'Heuristic score from matching script.';
comment on column public.place.google_match_distance_m is 'Distance in meters between place coords and candidate.';
comment on column public.place.google_match_method is 'Matching method (phone, nearby, text).';
comment on column public.place.google_match_reasons is 'Match rationale or error details.';
comment on column public.place.google_match_name is 'Candidate Google place name for review.';
comment on column public.place.google_match_address is 'Candidate Google formatted address for review.';
comment on column public.place.google_maps_url is 'Google Maps URL for candidate place.';
comment on column public.place.google_match_updated_at is 'Last time matching data was updated.';

create index if not exists place_google_place_id_idx on public.place (google_place_id);
create index if not exists place_google_match_status_idx on public.place (google_match_status);
