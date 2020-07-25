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
# "-short:--long:variable:default:required:description:input:output:private"
  "-u:--user:::true:PostgreSQL username"
  "-d:--database:::true:PostgreSQL database"
  "-s:--shape:::false:Table name containing geometrical data"
  "-S:--suffix:::true:Suffix to append to shape table name to generate other table names"
  "-c:--columns::id:false:Comma separated list of columns to retrieve from linked shape data"
  "-n:--number:::false:Number of links to copy to view; default is minimum required to hold all links in the junction table"
  "-S:--shapefile:::false:Shapefile to generate"::true
  "-l:--logfile:::false:Log file to record processing, defaults to \$shape + \$suffix + .log"::true
)

source $(dirname "$0")/argrecord.sh

if [[ ! -n ${logfile} ]]; then
    logfile="${shape}_${suffix}.log"
fi
INCOMMENTS=$([ -r "${logfile}" ] && cat "${logfile}")
echo "${COMMENTS}${INCOMMENTS}" > ${logfile}

poly=${shape}_${suffix}_poly
junction=${shape}_${suffix}_junction
view=${shape}_${suffix}_view
IFS=',' read -r -a columnarray <<< "${columns}"

if [[ ! -n "${number}" ]]; then
    number=$(psql ${database} ${user} \
                --quiet --tuples-only --no-align \
                --command="\timing off" \
                --command="SELECT max(count)
                           FROM (SELECT poly_id, count(shape_id) AS count 
                                 FROM ${junction}
                                 GROUP BY poly_id) AS foo")
fi
echo "Number of links to copy is ${number}"

VIEW_QUERY="SELECT poly_id, poly_geometry, array_length(agg.${columnarray[0]}, 1) AS shape_count"
for ((linkidx=1; linkidx<=${number}; linkidx++)) do
    for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
        VIEW_QUERY+=", agg.${columnarray[colidx]}[${linkidx}] AS ${columnarray[colidx]}_${linkidx}"
    done
done
VIEW_QUERY+=" FROM (SELECT poly_id, poly.geometry AS poly_geometry"
for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
    VIEW_QUERY+=", array_agg(shape.${columnarray[colidx]} ORDER by fih_date1 DESC, objectid DESC) AS ${columnarray[colidx]}"
done
VIEW_QUERY+=" FROM ${junction} AS junction
               JOIN ${poly} AS poly on poly.id = poly_id
               JOIN ${shape} AS shape ON shape.objectid = shape_id
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