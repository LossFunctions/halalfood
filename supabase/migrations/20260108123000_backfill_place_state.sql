-- Backfill state from address/display_location for existing places.

update public.place
set state = upper(coalesce(
  (regexp_match(address, '.*?,\\s*([A-Za-z]{2})\\s*(?:\\d{5}(?:-\\d{4})?)?\\s*(?:,|$)'))[1],
  (regexp_match(display_location, '.*?,\\s*([A-Za-z]{2})\\s*(?:\\d{5}(?:-\\d{4})?)?\\s*(?:,|$)'))[1],
  case
    when address ~* '\\bNew York\\b' or display_location ~* '\\bNew York\\b' then 'NY'
    when address ~* '\\bNew Jersey\\b' or display_location ~* '\\bNew Jersey\\b' then 'NJ'
    when address ~* '\\bConnecticut\\b' or display_location ~* '\\bConnecticut\\b' then 'CT'
    else null
  end
))
where state is null
  and (address is not null or display_location is not null);
