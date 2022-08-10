CREATE TABLE :table AS (
    WITH ids AS (
        SELECT
            poly_id,
            fireseason(fih_date1) AS thisfireseason,
            fireseason(LEAD(fih_date1) OVER (PARTITION BY poly_id ORDER BY fih_date1 DESC)) AS prevfireseason
        FROM
            dbca_fire_history_dbca_060_:suffix_history history, 
            unnest(history.id) AS history_id, 
            dbca_fire_history_dbca_060
        WHERE dbca_fire_history_dbca_060.id = history_id
        ORDER BY fih_date1 DESC)
    SELECT
        poly_id, geom, numfires
    FROM (
        SELECT 
            poly_id, 
            (SELECT count(DISTINCT thisfireseason) FILTER(WHERE thisfireseason >= :refseason AND thisfireseason - prevfireseason > 1) AS numfires)
        FROM 
            ids
        GROUP BY poly_id
    ) sub
    LEFT JOIN dbca_fire_history_dbca_060_:suffix_poly poly on poly.id = poly_id)