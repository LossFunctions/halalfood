-- Add SBNY (Shar'i Board of New York) as certifier for known SBNY-certified places
-- Source: SBNY certified restaurant list (reports/SBNY Cert.xlsx)
-- Note: Only updates places that don't already have a certifier

UPDATE public.place
SET cc_certifier_org = 'SBNY'
WHERE (
  name ILIKE '804 Halal Platters%' OR
  name ILIKE 'Ace Shawarma%' OR
  name ILIKE 'Addy''s BBQ%' OR
  name ILIKE 'Addys BBQ%' OR
  name ILIKE 'Adnan Halal Meat%' OR
  name ILIKE 'Affan Indo-Chinese%' OR
  name ILIKE 'Affan%' OR
  name ILIKE 'Aftab Meat%' OR
  name ILIKE 'Aftab Supermarket%' OR
  name ILIKE 'Ahar Restaurant%' OR
  name ILIKE 'Al Baik Restaurant%' OR
  name ILIKE 'Al Falah Meats%' OR
  name ILIKE 'Al Maidah%' OR
  name ILIKE 'Al Meezan%' OR
  name ILIKE 'Al Mehran Restaurant%' OR
  name ILIKE 'Al Mezaan%' OR
  name ILIKE 'Al Noor Halal%' OR
  name ILIKE 'Al Souq%' OR
  name ILIKE 'Al-Maa''edah%' OR
  name ILIKE 'Al-Medinah Restaurant%' OR
  name ILIKE 'Alaadeen%' OR
  name ILIKE 'Aladin Halal%' OR
  name ILIKE 'Aladin Grill%' OR
  name ILIKE 'Amart and Halal%' OR
  name ILIKE 'Aziz Halal%' OR
  name ILIKE 'Azka BBQ%' OR
  name ILIKE 'Azka Events%' OR
  name ILIKE 'BBQ Today%' OR
  name ILIKE 'Baitullaham%' OR
  name ILIKE 'Baya Halal%' OR
  name ILIKE 'Bismillah Halal%' OR
  name ILIKE 'Bismillah Live Poultry%' OR
  name ILIKE 'Buffalo Fresh%' OR
  name ILIKE 'Burgermania%' OR
  name ILIKE 'Burgery%' OR
  name ILIKE 'Burns Road Foods%' OR
  name ILIKE 'Busn'' Halal%' OR
  name ILIKE 'Chawdhury Farm%' OR
  name ILIKE 'Chef''s Mahal%' OR
  name ILIKE 'Chick N Kick%' OR
  name ILIKE 'Chuucha%' OR
  name ILIKE 'DIYAANAAT%' OR
  name ILIKE 'Daily Foods and Halal%' OR
  name ILIKE 'Datar Gyro%' OR
  name ILIKE 'Datar Halal%' OR
  name ILIKE 'Deshi Foods%' OR
  name ILIKE 'Deshi Halal%' OR
  name ILIKE 'Dhaka Restaurant%' OR
  name ILIKE 'Dillsburg Halal%' OR
  name ILIKE 'Dosa and Biryani%' OR
  name ILIKE 'Eatzy Chinese%' OR
  name ILIKE 'Eatzy Thai%' OR
  name ILIKE 'Emir Halal%' OR
  name ILIKE 'EMIR HALAL%' OR
  name ILIKE 'Farmer''s India%' OR
  name ILIKE 'Fatima Grocery%' OR
  name ILIKE 'Fiesta Healthy Mexican%' OR
  name ILIKE 'Filli Cafe%' OR
  name ILIKE 'Fire Stone Grill%' OR
  name ILIKE 'Firestone Grill%' OR
  name ILIKE 'Foodland Supermarket%' OR
  name ILIKE 'Foster Food Market%' OR
  name ILIKE 'Good Cuts Halal%' OR
  name ILIKE 'Grillwaale%' OR
  name ILIKE 'Grill Waale%' OR
  name ILIKE 'Gyro Hut%' OR
  name ILIKE 'Hal & Al Meats%' OR
  name ILIKE 'HAL&AL Meats%' OR
  name ILIKE 'Halal Bros Kabab%' OR
  name ILIKE 'Halal Eatz%' OR
  name ILIKE 'Halal Mart%' OR
  name ILIKE 'Harb''s Farm%' OR
  name ILIKE 'Hitit Burger%' OR
  name ILIKE 'Holy Burger%' OR
  name ILIKE 'Holy Cow%' OR
  name ILIKE 'Hot Spot%' OR
  name ILIKE 'Hyderabad House%' OR
  name ILIKE 'Hyderabad Palace%' OR
  name ILIKE 'Hyndman Halal%' OR
  name ILIKE 'IHSAN FARMS%' OR
  name ILIKE 'Imperial Farms%' OR
  name ILIKE 'IndoPak Halal%' OR
  name ILIKE 'Indo Pak Halal%' OR
  name ILIKE 'Jazeera Restaurant%' OR
  name ILIKE 'Just Halal%' OR
  name ILIKE 'Kabab House%' OR
  name ILIKE 'Kababjees%' OR
  name ILIKE 'Kawran Bazar%' OR
  name ILIKE 'Khanum''s Kitchen%' OR
  name ILIKE 'Khorasan Kabab%' OR
  name ILIKE 'Krunchy Krust%' OR
  name ILIKE 'LABELLE FARMS%' OR
  name ILIKE 'La Estacion Mela%' OR
  name ILIKE 'Labbaik Karahi%' OR
  name ILIKE 'Locust Point Farms%' OR
  name ILIKE 'Maa Supermarket%' OR
  name ILIKE 'Mannan%' OR
  name ILIKE 'Mars Halal%' OR
  name ILIKE 'Mazadar Mediterranean%' OR
  name ILIKE 'Mecca Halal%' OR
  name ILIKE 'Midnight Curry%' OR
  name ILIKE 'Mina Bazar%' OR
  name ILIKE 'Moho Mexican%' OR
  name ILIKE 'Moon Restaurant%' OR
  name ILIKE 'Moon Supermarket%' OR
  name ILIKE 'Najaf Halal%' OR
  name ILIKE 'New England Meat%' OR
  name ILIKE 'New York City Halal%' OR
  name ILIKE 'NYC Halal Grill%' OR
  name ILIKE 'Noor N Spice%' OR
  name ILIKE 'Ozone Park Supermarket%' OR
  name ILIKE 'Palli Supermarket%' OR
  name ILIKE 'Pariwaar Delights%' OR
  name ILIKE 'Pizza 101%' OR
  name ILIKE 'Punjab Halal%' OR
  name ILIKE 'Qasim Zabiha%' OR
  name ILIKE 'Reem''s Grill%' OR
  name ILIKE 'Royal Kabab%' OR
  name ILIKE 'Royal Pizza%' OR
  name ILIKE 'Saffron Restaurant%' OR
  name ILIKE 'Sagar Restaurant%' OR
  name ILIKE 'Samosa Paradise%' OR
  name ILIKE 'Sheikhs N Burgers%' OR
  name ILIKE 'Sherins Halal%' OR
  name ILIKE 'Sherin''s Halal%' OR
  name ILIKE 'Slammin Pizza%' OR
  name ILIKE 'Slappin Chick%' OR
  name ILIKE 'Star Restaurant%' OR
  name ILIKE 'Sumaq Mediterranean%' OR
  name ILIKE 'Sycamore Halal%' OR
  name ILIKE 'Taj Grill%' OR
  name ILIKE 'Tandoor Restaurant%' OR
  name ILIKE 'Towne Market%' OR
  name ILIKE 'Two Brothers Chicken%' OR
  name ILIKE 'Valley Meat Packing%' OR
  name ILIKE 'Vineland Poultry%' OR
  name ILIKE 'Walden Groceries%' OR
  name ILIKE 'Watan Market%' OR
  name ILIKE 'Westminster Meat%' OR
  name ILIKE 'Wok & Grill%' OR
  name ILIKE 'Wok and Grill%' OR
  name ILIKE 'Zacs Burger%' OR
  name ILIKE 'Zac''s Burger%' OR
  name ILIKE 'Zbest Foods%' OR
  name ILIKE 'Zubaidah Halal%'
)
AND cc_certifier_org IS NULL
AND status = 'published';

-- Also update the materialized view after this migration
-- Run: REFRESH MATERIALIZED VIEW public.community_top_rated_v1;
