-- Add state/region to places for easier filtering.

alter table public.place
  add column state text;

comment on column public.place.state is 'Two-letter state/region code (e.g. NY, NJ, CT).';

create index place_state_idx on public.place using btree (state);
