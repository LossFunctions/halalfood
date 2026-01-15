-- Add Claude Candidate columns for vetted halal signals.
alter table public.place
  add column if not exists cc_halal_status text,
  add column if not exists cc_halal_likelihood text,
  add column if not exists cc_halal_type text,
  add column if not exists cc_halal_confidence int,
  add column if not exists cc_note text,
  add column if not exists cc_reasoning_raw text,
  add column if not exists cc_is_zabiha boolean,
  add column if not exists cc_certifier_org text;
