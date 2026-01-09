-- Derive state from address/display_location/source_raw/lat/lon and keep it in sync.

create or replace function public.resolve_place_state(
  p_address text,
  p_display_location text,
  p_source_raw jsonb,
  p_lat double precision,
  p_lon double precision
)
returns text
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_state text;
  v_match text[];
  v_zip text;
  v_region text;
  v_address text := coalesce(p_address, '');
  v_display text := coalesce(p_display_location, '');
  v_address_lower text := lower(v_address);
  v_display_lower text := lower(v_display);
  v_source text;
begin
  if p_source_raw is not null then
    v_source := nullif(trim(both from p_source_raw->>'addr:state'), '');
    if v_source is null then
      v_source := nullif(trim(both from p_source_raw->>'state'), '');
    end if;
    if v_source is null then
      v_source := nullif(trim(both from p_source_raw->>'region'), '');
    end if;
    if v_source is not null then
      v_state := upper(v_source);
      if v_state in ('NY', 'NJ', 'CT') then
        return v_state;
      end if;
      if v_state in ('NEW YORK', 'NEW JERSEY', 'CONNECTICUT') then
        return case v_state
          when 'NEW YORK' then 'NY'
          when 'NEW JERSEY' then 'NJ'
          else 'CT'
        end;
      end if;
    end if;
  end if;

  v_match := regexp_match(v_address_lower, '\m(ny|nj|ct)\M');
  if array_length(v_match, 1) = 1 then
    return upper(v_match[1]);
  end if;
  v_match := regexp_match(v_display_lower, '\m(ny|nj|ct)\M');
  if array_length(v_match, 1) = 1 then
    return upper(v_match[1]);
  end if;

  if v_address_lower like '%new york%' or v_display_lower like '%new york%' then
    return 'NY';
  elsif v_address_lower like '%new jersey%' or v_display_lower like '%new jersey%' then
    return 'NJ';
  elsif v_address_lower like '%connecticut%' or v_display_lower like '%connecticut%' then
    return 'CT';
  end if;

  v_match := regexp_match(v_address, '\m(\d{5})\M');
  if array_length(v_match, 1) = 1 then
    v_zip := v_match[1];
  else
    v_match := regexp_match(v_display, '\m(\d{5})\M');
    if array_length(v_match, 1) = 1 then
      v_zip := v_match[1];
    end if;
  end if;

  if v_zip is not null then
    if v_zip like '06%' then
      return 'CT';
    elsif v_zip like '07%' or v_zip like '08%' then
      return 'NJ';
    elsif v_zip like '10%' or v_zip like '11%' or v_zip like '12%' or v_zip like '13%' or v_zip like '14%' then
      return 'NY';
    end if;
  end if;

  if p_lat is not null and p_lon is not null then
    v_region := public.community_region_for_place(p_lat, p_lon, p_address);
    if v_region is not null then
      return 'NY';
    end if;
    if p_lat between 40.98 and 42.06 and p_lon between -73.73 and -71.78 then
      return 'CT';
    end if;
    if p_lat between 38.93 and 41.36 and p_lon between -75.56 and -73.89 then
      return 'NJ';
    end if;
    if p_lat between 40.49 and 45.01 and p_lon between -79.76 and -71.85 then
      return 'NY';
    end if;
  end if;

  return null;
end;
$function$;

create or replace function public.place_state_sync()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if new.state is null then
    new.state := public.resolve_place_state(
      new.address,
      new.display_location,
      new.source_raw,
      new.lat,
      new.lon
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists place_state_sync on public.place;
create trigger place_state_sync
before insert or update of address, display_location, source_raw, lat, lon, state
on public.place
for each row
execute function public.place_state_sync();

update public.place
set state = public.resolve_place_state(address, display_location, source_raw, lat, lon)
where state is null;
