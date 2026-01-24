delete from public.place_photo
where src ilike 'yelp'
   or image_url ilike '%yelpcdn.com%';

update public.place
set rating = null,
    rating_count = null
where (source is not null and lower(source) like '%yelp%')
   or (source_id is not null and lower(source_id) like '%yelp%')
   or (external_id is not null and lower(external_id) like 'yelp:%');
