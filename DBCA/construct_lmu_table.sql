\timing off
SELECT "description" AS "LMU", area AS "Area (ha)", "3"/area*100 AS "< 3 years (%)", "6"/area*100 AS "< 6 years (%)", "12"/area*100 AS "< 12 years (%)", "25"/area*100 AS "< 25 years (%)", (area - "25")/area*100 AS ">= 25 years (%)"
FROM "land_management_unit",
LATERAL (SELECT yslb FROM yslb_by_lmu_native_veg WHERE yslb >= 3
AND "yslb_by_lmu_native_veg"."lmu name" = "land_management_unit"."description"
ORDER BY yslb
LIMIT 1) past3,
LATERAL (SELECT "lmu native veg area" AS area, "native veg area burned cumulative" AS "3"
FROM yslb_by_lmu_native_veg
WHERE yslb < past3.yslb
AND "yslb_by_lmu_native_veg"."lmu name" = "land_management_unit"."description"
ORDER BY -yslb
LIMIT 1) get3,
LATERAL (SELECT yslb FROM yslb_by_lmu_native_veg WHERE yslb >= 6
AND "yslb_by_lmu_native_veg"."lmu name" = "land_management_unit"."description"
ORDER BY yslb
LIMIT 1) past6,
LATERAL (SELECT "native veg area burned cumulative" AS "6"
FROM yslb_by_lmu_native_veg
WHERE yslb < past6.yslb
AND "yslb_by_lmu_native_veg"."lmu name" = "land_management_unit"."description"
ORDER BY -yslb
LIMIT 1) get6,
LATERAL (SELECT yslb FROM yslb_by_lmu_native_veg WHERE yslb >= 12
AND "yslb_by_lmu_native_veg"."lmu name" = "land_management_unit"."description"
ORDER BY yslb
LIMIT 1) past12,
LATERAL (SELECT "native veg area burned cumulative" AS "12"
FROM yslb_by_lmu_native_veg
WHERE yslb < past12.yslb
AND "yslb_by_lmu_native_veg"."lmu name" = "land_management_unit"."description"
ORDER BY -yslb
LIMIT 1) get12,
LATERAL (SELECT yslb FROM yslb_by_lmu_native_veg WHERE yslb >= 25
AND "yslb_by_lmu_native_veg"."lmu name" = "land_management_unit"."description"
ORDER BY yslb
LIMIT 1) past25,
LATERAL (SELECT "native veg area burned cumulative" AS "25"
FROM yslb_by_lmu_native_veg
WHERE yslb < past25.yslb
AND "yslb_by_lmu_native_veg"."lmu name" = "land_management_unit"."description"
ORDER BY -yslb
LIMIT 1) get25
