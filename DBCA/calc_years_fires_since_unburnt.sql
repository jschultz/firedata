SELECT geom, fslu, :refyear - season[fslu] AS yslu
FROM (
    SELECT 
        poly_id,
        season,
        (SELECT ordinality from unnest(season[1:array_length(season,1)-1] @- season[2:]) WITH ORDINALITY WHERE unnest >= :mininterval limit 1) AS fslu
    FROM (
        SELECT poly_id, array_prepend(:refyear, array_agg(fireseason(fih_date1))) season 
        FROM (
            SELECT poly_id, history_id, fih_date1 
            FROM dbca_fire_history_dbca_060_southern_history history, unnest(history.id) AS history_id, dbca_fire_history_dbca_060
            WHERE dbca_fire_history_dbca_060.id = history_id
            LIMIT 100
          ) sub
    GROUP BY poly_id
    ) sub1
) sub2
LEFT JOIN dbca_fire_history_dbca_060_southern_poly poly on poly.id = poly_id
