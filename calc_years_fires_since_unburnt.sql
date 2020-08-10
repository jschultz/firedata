ALTER TABLE :table ADD COLUMN years_since_unburnt int, ADD COLUMN fires_since_unburnt int;

CREATE OR REPLACE FUNCTION calc_years_fires_since_unburnt(arg :table)
  RETURNS :table
  AS $$
    fires=[]
    idx = 1
    while True:
      if arg.get('fih_season1_'+str(idx)) is not None:
        fires += [{'fih_season1': arg['fih_season1_'+str(idx)], 'season': int(arg['fih_fire_seaso_'+str(idx)][5:]), 'fih_fire_type': arg['fih_fire_type_'+str(idx)]}]
      else:
        break;
      idx += 1
      
    threshold = 10
    cur_year = 2021
    idx = 0
    arg['years_since_unburnt'] = None
    arg['fires_since_unburnt'] = None
    while idx < len(fires):
      if cur_year - fires[idx]['season'] >= threshold:
        arg['years_since_unburnt'] = 2021 - cur_year
        arg['fires_since_unburnt'] = idx
        break
      else:
        cur_year = fires[idx]['season']
        idx += 1

    return arg
  $$ LANGUAGE plpython3u;

UPDATE :table AS update_table
  SET years_since_unburnt = calc.years_since_unburnt, fires_since_unburnt = calc.fires_since_unburnt 
  FROM (SELECT poly_id, (row).years_since_unburnt, (row).fires_since_unburnt 
        FROM (SELECT poly_id, calc_years_fires_since_unburnt(:table) AS row 
              FROM :table) AS foo) AS calc where calc.poly_id = update_table.poly_id;