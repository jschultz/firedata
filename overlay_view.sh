#!/bin/bash
#
# Copyright 2020 Jonathan Schultz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
set -e

help='Produces a view containing polygon ID and geometry and a selection of shape columns. The view is generated as a PostGIS view, or as a shapefile. Requires a shape, polygon and junction tables. The last two can be generated from a shape table by overlay_junction.sh'
args=(
# "-short:--long:variable:default:required:description:flags"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-s:--shape:::Table name containing geometrical data"
  "-S:--suffix:::Suffix to append to shape table name to generate other table names:required"
  "-c:--columns::objectid:Comma separated list of columns to retrieve from linked shape data"
  "-n:--number:::Number of links to copy to view; default is minimum required to hold all links in the junction table"
  "-w:--where:::WHERE clause for selecting from 'poly' table"
  "-v:--view:::View to generate"
  "-S:--shapefile:::Shapefile to generate:output"
  "-l:--logfile:::Log file to record processing, defaults to 'shape' + 'suffix' + .log:private"
  ":--nologfile:::Don't write a lot file:private"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${shape}_${suffix}.log"
    fi
    INCOMMENTS=$([ -r "${logfile}" ] && cat "${logfile}")
    echo "${COMMENTS}${INCOMMENTS}" > ${logfile}
fi
poly=${shape}_${suffix}_poly
junction=${shape}_${suffix}_junction
if [[ ! -n "${view}" ]]; then
    view=${shape}_${suffix}_view
fi
IFS=',' read -r -a columnarray <<< "${columns}"

if [[ ! -n "${where}" ]]; then
    where="TRUE"
fi
if [[ ! -n "${number}" ]]; then
    if [[ "${where}" == "TRUE" ]]; then
        NUMBER_SELECT="SELECT max(count)
                      FROM (SELECT poly_id, count(shape_id) AS count 
                            FROM ${junction}
                            GROUP BY poly_id) AS foo"
    else
        NUMBER_SELECT="SELECT max(count)
                      FROM (SELECT poly_id, count(shape_id) AS count 
                            FROM ${junction}
                            JOIN ${poly} AS poly ON poly.id = poly_id
                            WHERE ${where}
                            GROUP BY poly_id) AS foo"
    fi
    number=$(psql ${database} ${user} \
                --quiet --tuples-only --no-align \
                --command="\timing off" \
                --command="${NUMBER_SELECT}")
fi
echo "Number of links to copy is ${number}"
VIEW_QUERY="SELECT poly_id, poly_geometry, st_area(poly_geometry::geography)/10000 as area, 
                   array_length(agg.${columnarray[0]}, 1) AS shape_count, 
                   (SELECT min(diff) as min_interval
                    FROM (SELECT season_year - lag(season_year) OVER (ORDER BY season_year) AS diff FROM unnest(season_year) AS season_year) foo),
                   (SELECT max(diff) as max_interval
                    FROM (SELECT season_year - lag(season_year) OVER (ORDER BY season_year) AS diff FROM unnest(season_year) AS season_year) foo)"
for ((linkidx=1; linkidx<=${number}; linkidx++)) do
    for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
        VIEW_QUERY+=", agg.${columnarray[colidx]}[${linkidx}] AS ${columnarray[colidx]}_${linkidx}"
    done
done
VIEW_QUERY+=" FROM (SELECT poly_id, poly.geometry AS poly_geometry"
VIEW_QUERY+=", array_agg(substring(shape.fih_fire_seaso, '/([0-9]{4})')::integer) AS season_year"
for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
    VIEW_QUERY+=", array_agg(shape.${columnarray[colidx]} ORDER by fih_date1 DESC, objectid DESC) AS ${columnarray[colidx]}"
done
VIEW_QUERY+=" FROM ${junction} AS junction
               JOIN ${poly} AS poly on poly.id = poly_id
               JOIN ${shape} AS shape ON shape.objectid = shape_id
               WHERE ${where}
               GROUP BY poly_id, poly_geometry) agg"

if [[ -n "${shapefile}" ]]; then
    echo "Creating shapefile ${shapefile}"
    pgsql2shp -f ${shapefile} -u qgis fire "${VIEW_QUERY}"
else
    echo "Creating view ${view}"
    psql ${database} ${user} \
        --quiet \
        --command="DROP VIEW IF EXISTS ${view}" \
        --command="CREATE VIEW ${view} AS ${VIEW_QUERY}"
fi