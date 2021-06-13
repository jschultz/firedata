ALTER TABLE :table ADD COLUMN years_since_unburnt int, ADD COLUMN fires_since_unburnt int;
SET ROLE dba;
CREATE OR REPLACE FUNCTION calc_years_fires_since_unburnt(arg :table)
  RETURNS :table
  AS $$
    fires=[]
    idx = 1
    while True:
      fih_date1 = arg.get('fih_date1_'+str(idx))
      if fih_date1:
        if int(fih_date1[5:7]) >= 7:
          season = int(fih_date1[0:4]) + 1
        else:
          season = int(fih_date1[0:4])

        fires += [{'season': season, 'fih_fire_type': arg['fih_fire_type_'+str(idx)]}]
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
RESET ROLE;
UPDATE :table AS update_table
  SET years_since_unburnt = calc.years_since_unburnt, fires_since_unburnt = calc.fires_since_unburnt 
  FROM (SELECT poly_id, (row).years_since_unburnt, (row).fires_since_unburnt 
        FROM (SELECT poly_id, calc_years_fires_since_unburnt(:table) AS row 
              FROM :table) AS foo) AS calc where calc.poly_id = update_table.poly_id;