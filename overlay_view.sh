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
  ":--shapeid::objectid:Id column in shape table"
  "-p:--polygon:::Polygon table"
  ":--polyid::id:ID column in polygon table"
  ":--polycolumns::poly_id,poly_geometry:Columns to retrieve from polygon table"
  "-S:--suffix:::Suffix to append to poly or shape table name to generate other table names:required"
  "-c:--columns::objectid:List separated by '|' of columns to retrieve from linked shape data"
  ":--columnaliases::objectid:List separated by '|' of aliases for retrieved shape data columns; empty value means no alias"
  "-n:--number:::Number of links to copy to view; default is minimum required to hold all links in the junction table"
  "-w:--where:::WHERE clause for selecting from 'poly' table"
  "-v:--view:::View to generate"
  "-S:--shapefile:::Shapefile to generate:output"
  "-l:--logfile:::Log file to record processing, defaults to 'shape' + 'suffix' + .log:private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ ! -n "${polygon}" ]]; then
    base=${shape}
    polygon=${base}_${suffix}_poly
else
    base=${polygon}
fi

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        logfile="${base}_${suffix}.log"
    fi
    INCOMMENTS=$([ -r "${logfile}" ] && cat "${logfile}")
    echo "${COMMENTS}${INCOMMENTS}" > ${logfile}
fi

junction=${base}_${suffix}_junction
if [[ ! -n "${view}" ]]; then
    view=${base}_${suffix}_view
fi
IFS='|' read -r -a columnarray <<< "${columns}"
IFS='|' read -r -a columnaliasarray <<< "${columnaliases}"
for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
    if [[ ! -n "${columnaliasarray[colidx]}" ]]; then
        columnaliasarray[colidx]="${columnarray[colidx]}"
    fi
done

if [[ ! -n "${number}" ]]; then
    if [[ ! -n "${where}" ]]; then
        NUMBER_SELECT="SELECT max(count)
                      FROM (SELECT poly_id, count(shape_id) AS count 
                            FROM ${junction}
                            GROUP BY poly_id) AS foo"
    else
        NUMBER_SELECT="SELECT max(count)
                      FROM (SELECT poly_id, count(shape_id) AS count 
                            FROM ${junction}
                            JOIN ${polygon} AS poly ON poly.${polyid} = poly_id
                            WHERE ${where}
                            GROUP BY poly_id) AS foo"
    fi
    number=$(psql ${database} ${user} \
                --quiet --tuples-only --no-align \
                --command="\timing off" \
                --command="${NUMBER_SELECT}")
fi
if [[ ! -n "${number}" ]]; then
    echo "ERROR: no links!"
    exit 1
fi
echo "Number of links to copy is ${number}"
VIEW_QUERY="SELECT ${polycolumns}, st_area(poly_geometry::geography)/10000 as area, 
                   array_length(agg.${columnaliasarray[0]}, 1) AS shape_count, 
                   (SELECT min(diff) as min_interval
                    FROM (SELECT season_year - lag(season_year) OVER (ORDER BY season_year) AS diff FROM unnest(season_year) AS season_year) foo),
                   (SELECT max(diff) as max_interval
                    FROM (SELECT season_year - lag(season_year) OVER (ORDER BY season_year) AS diff FROM unnest(season_year) AS season_year) foo)"
for ((linkidx=1; linkidx<=${number}; linkidx++)) do
    for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
        VIEW_QUERY+=", agg.${columnaliasarray[colidx]}[${linkidx}] AS ${columnaliasarray[colidx]}_${linkidx}"
    done
done
VIEW_QUERY+=" FROM (SELECT poly_id, poly.geometry AS poly_geometry"
VIEW_QUERY+=", array_agg(substring(shape.fih_fire_seaso, '/([0-9]{4})')::integer) AS season_year"
for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
    VIEW_QUERY+=", array_agg(${columnarray[colidx]} ORDER by fih_date1 DESC, ${shapeid} DESC) AS ${columnaliasarray[colidx]}"
done
VIEW_QUERY+=" FROM ${junction} AS junction
               JOIN ${polygon} AS poly ON poly.${polyid} = poly_id
               JOIN ${shape} AS shape ON shape.${shapeid} = shape_id"
if [[ -n "${where}" ]]; then
    VIEW_QUERY+=" WHERE ${where}"
fi
VIEW_QUERY+=" GROUP BY poly_id, poly_geometry) agg"
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