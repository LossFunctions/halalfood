-- Add HMS (Halal Monitoring Services) as certifier for known HMS-certified places
-- Source: HMS certified restaurant list (reports/Halal Monitoring Services.xlsx)

UPDATE public.place
SET cc_certifier_org = 'HMS'
WHERE (
  -- Chain restaurants (match all locations)
  name ILIKE 'Burgermania%' OR
  name ILIKE 'Holy Burger%' OR
  name ILIKE 'Holy Cow%' OR
  name ILIKE 'Mannan%' OR
  name ILIKE 'Moho Mexican Grill%' OR
  name ILIKE 'Pariwaar Delights%' OR
  name ILIKE 'Sheikhs N Burgers%' OR
  -- Individual restaurants and stores
  name ILIKE '804 Halal Platters%' OR
  name ILIKE 'Ace Shawarma%' OR
  name ILIKE 'Addys BBQ%' OR
  name ILIKE 'Addy''s BBQ%' OR
  name ILIKE 'Affan Indo-Chinese%' OR
  name ILIKE 'Aftab Meat%' OR
  name ILIKE 'Aftab Supermarket%' OR
  name ILIKE 'Al Falah Meats%' OR
  name ILIKE 'Al Mehran Restaurant%' OR
  name ILIKE 'Al Mezaan%' OR
  name ILIKE 'Al Noor Halal Poultry%' OR
  name ILIKE 'Aladin Halal Meat%' OR
  name ILIKE 'Amart and Halal Meat%' OR
  name ILIKE 'Aziz Halal%' OR
  name ILIKE 'Azka BBQ%' OR
  name ILIKE 'Azka Events%' OR
  name ILIKE 'BBQ Today%' OR
  name ILIKE 'Baitullaham%' OR
  name ILIKE 'Bismillah Halal Live Poultry%' OR
  name ILIKE 'Bismillah Live Poultry%' OR
  name ILIKE 'Burgery%' OR
  name ILIKE 'Burns Road Foods%' OR
  name ILIKE 'Chef''s Mahal%' OR
  name ILIKE 'Chick N Kick%' OR
  name ILIKE 'Datar Gyro%' OR
  name ILIKE 'Datar Halal%' OR
  name ILIKE 'Deshi Foods%' OR
  name ILIKE 'Deshi Halal%' OR
  name ILIKE 'Dhaka Restaurant%' OR
  name ILIKE 'Dosa and Biryani House%' OR
  name ILIKE 'EMIR HALAL%' OR
  name ILIKE 'Eatzy Chinese%' OR
  name ILIKE 'Eatzy Thai%' OR
  name ILIKE 'Fatima Grocery%' OR
  name ILIKE 'Fiesta Healthy Mexican%' OR
  name ILIKE 'Filli Cafe%' OR
  name ILIKE 'Fire Stone Grill%' OR
  name ILIKE 'Firestone Grill%' OR
  name ILIKE 'Foster Food Market%' OR
  name ILIKE 'Good Cuts Halal%' OR
  name ILIKE 'Grillwaale%' OR
  name ILIKE 'Grill Waale%' OR
  name ILIKE 'Gyro Hut%' OR
  name ILIKE 'HAL&AL Meats%' OR
  name ILIKE 'Halal Bros Kabab%' OR
  name ILIKE 'Halal Eatz%' OR
  name ILIKE 'Halal Mart%' OR
  name ILIKE 'Halal Pride Farms%' OR
  name ILIKE 'Hitit Burger%' OR
  name ILIKE 'Hyderabad House JC%' OR
  name ILIKE 'Hyderabad House Jersey City%' OR
  name ILIKE 'IndoPak Halal%' OR
  name ILIKE 'Indo Pak Halal%' OR
  name ILIKE 'Jazeera Restaurant%' OR
  name ILIKE 'Kababjees%' OR
  name ILIKE 'Kawran Bazar%' OR
  name ILIKE 'Khorasan Kabab%' OR
  name ILIKE 'Krunchy Krust%' OR
  name ILIKE 'La Estacion Mela%' OR
  name ILIKE 'Labbaik Karahi%' OR
  name ILIKE 'Lil Hala Baby Food%' OR
  name ILIKE 'Maa Supermarket%' OR
  name ILIKE 'Mars Halal Market%' OR
  name ILIKE 'Mecca Halal Meat%' OR
  name ILIKE 'Midnight Curry%' OR
  name ILIKE 'Mina Bazar%' OR
  name ILIKE 'Moon Restaurant%' OR
  name ILIKE 'Moon Supermarket%' OR
  name ILIKE 'New York City Halal Grill%' OR
  name ILIKE 'NYC Halal Grill%' OR
  name ILIKE 'Aria Kabab%' OR
  name ILIKE 'Nur Halal Meat%' OR
  name ILIKE 'Ozone Park Supermarket%' OR
  name ILIKE 'Pizza 101%' OR
  name ILIKE 'Punjab Halal Meat%' OR
  name ILIKE 'Qasim Zabiha%' OR
  name ILIKE 'Royal Kabab%' OR
  name ILIKE 'Saffron Restaurant%' OR
  name ILIKE 'Sagar Restaurant%' OR
  name ILIKE 'Samosa Paradise%' OR
  name ILIKE 'Sherins Halal%' OR
  name ILIKE 'Sherin''s Halal%' OR
  name ILIKE 'Slammin Pizza%' OR
  name ILIKE 'Slappin Chick%' OR
  name ILIKE 'Star Restaurant%' OR
  name ILIKE 'Sumaq Mediterranean%' OR
  name ILIKE 'Taj Grill%' OR
  name ILIKE 'Tandoor Restaurant%' OR
  name ILIKE 'Wok & Grill%' OR
  name ILIKE 'Wok and Grill%' OR
  name ILIKE 'Zacs Burger%' OR
  name ILIKE 'Zac''s Burger%'
)
AND cc_certifier_org IS NULL
AND status = 'published';

-- Also update the materialized view after this migration
-- Run: REFRESH MATERIALIZED VIEW public.community_top_rated_v1;
