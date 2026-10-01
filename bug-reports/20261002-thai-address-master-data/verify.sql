-- Post-apply checks (Plan.md) — each query returns expected vs actual
-- Bangkok subdistrict count → 180
SELECT 'bangkok_subdistrict_count' AS check_name, 180 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict s
JOIN public.address_th_district d ON s.district_id = d.id::bigint
WHERE d.province_id = 10;

-- Chatuchak (1030) subdistrict count → 5
SELECT 'chatuchak_subdistrict_count' AS check_name, 5 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict WHERE district_id = 1030;

-- No doubled ต.ต. prefix
SELECT 'no_doubled_t_prefix' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict
WHERE subdistrict_name_th LIKE 'ต.ต.%';

-- No replacement char in names
SELECT 'no_replacement_char' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict
WHERE subdistrict_name_th LIKE '%�%';

-- zip_code 0 or NULL except Phase 2 held codes
SELECT 'bad_zip_except_held' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict
WHERE (zip_code IS NULL OR zip_code = 0)
  AND id NOT IN ('200409', '920221', '920222', '920414');

-- No subdistrict_name_en = '0'
SELECT 'no_en_zero_except_held' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.address_th_subdistrict
WHERE subdistrict_name_en = '0'
  AND id NOT IN ('200409', '920221', '920222', '920414', '380103', '410111', '500109', '830105');

-- Phayao (province 56) districts: 9 distinct English names
SELECT 'phayao_distinct_district_en' AS check_name, 9 AS expected,
       COUNT(DISTINCT district_name_en)::int AS actual
FROM public.address_th_district
WHERE province_id = 56;

-- user_address must not reference deleted codes
SELECT 'user_address_deleted_codes' AS check_name, 0 AS expected, COUNT(*)::int AS actual
FROM public.user_address
WHERE subdistrict_code IN ('104701', '105001', '110105', '402602', '402608', '402615', '440828', '490501', '530306')
   OR district_code = '4026';

-- Province 11 English name
SELECT 'province_11_en' AS check_name, 'Samut Prakan' AS expected, province_name_en AS actual
FROM public.address_th_province WHERE id = '11';
