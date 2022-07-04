WITH 
  area AS (
    SELECT fmp_geom AS geom FROM land_management_unit WHERE description = :lmu),
  byyear AS (
    SELECT 
      fireseason(fih_date1) AS year, 
      ST_Area(ST_Intersection(ST_Union(geom), (SELECT geom FROM area)))/ST_Area((SELECT geom FROM area))*100 AS percent 
    FROM dbca_fire_history_dbca_060 
    WHERE ST_Intersects(geom, (SELECT geom FROM area)) 
    GROUP BY fireseason(fih_date1)
    ORDER BY year DESC)
  SELECT baseyear, baseyear - year + 1 AS rotation
  FROM generate_series(2020, 1970, -1) baseyear,
  LATERAL (SELECT
    year,
    cumulative
  FROM (
    SELECT
      year, SUM(percent) FILTER (WHERE year <= baseyear) OVER (ORDER BY year DESC) AS cumulative
    FROM
      byyear
    )
  AS byyearcumulative
  WHERE cumulative >= 80
  LIMIT 1) rotation
