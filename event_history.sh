#!/bin/bash
#
# Copyright 2021 Jonathan Schultz
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

help='Produces a list of events that intersect a specified area'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-v:--viewtable:::Name of table containing event history view:required"
  "-a:--area:::Specification of area of which history will be extracted:required"
  "-c:--viewcolumns::objectid:Semicolon-separated list of columns to retrieve from view data"
  "-g:--viewgroups::objectid:Semicolon-separated list of columns to group view data"
  ":--viewaliases:::Semicolon-separated list of aliases for columns retrieved from view data; empty value for no alias"
  "-f:--filter:::Condition applied after query execution"
  "-C:--csvfile:::CSV file to generate:output"
  "-S:--shapefile:::Shapefile to generate:output"
  "-l:--logfile:::Log file to record processing, defaults to out file name with extension replaced by '.log':private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        if [[ -n "${shapefile}" ]]; then
            logfile=$(basename ${shapefile})
            logfile="${logfile%.*}.log"
        elif [[ -n "${csvfile}" ]]; then
            logfile=$(basename ${csvfile})
            logfile="${logfile%.*}.log"
        else
            logfile="event_history.log"
        fi
    fi
    if [[ -r "${logfile}" ]]; then
        INCOMMENTS="$(< "${logfile}")"
    else
        INCOMMENTS=""
    fi
    echo "${COMMENTS}${INCOMMENTS}" > ${logfile}
fi

if [[ "${debug}" == "true" ]]; then
    set -x
fi

IFS=';' read -r -a viewcolumnarray <<< "${viewcolumns}"
IFS=';' read -r -a viewaliasarray <<< "${viewaliases}"
IFS=';' read -r -a viewgrouparray <<< "${viewgroups}"

HISTORY_QUERY="WITH area AS ${area} SELECT * FROM (SELECT"
separator=""
for ((colidx=0; colidx<${#viewcolumnarray[@]}; colidx++)) do
    HISTORY_QUERY+="${separator} ${viewcolumnarray[colidx]}"
    if [[ -n "${viewaliasarray[colidx]}" ]]; then
        HISTORY_QUERY+=" AS ${viewaliasarray[colidx]}"
    fi
    separator=","
done
HISTORY_QUERY+="
    FROM ${viewtable} AS view
WHERE
    ST_Intersects(view.geom, (SELECT geom from area))"
if [[ ${#viewgrouparray[@]} -gt 0 ]]; then
    HISTORY_QUERY+="
        GROUP BY"
    separator=""
    for ((colidx=0; colidx<${#viewgrouparray[@]}; colidx++)) do
        HISTORY_QUERY+="${separator} ${viewgrouparray[colidx]}"
        separator=","
    done
fi
HISTORY_QUERY+=") AS actual_query"
if [[ -n "${filter}" ]]; then
    HISTORY_QUERY+=" WHERE (${filter})"
fi
# echo $HISTORY_QUERY

if [[ -n "${shapefile}" ]]; then
    echo "Creating shapefile ${shapefile}"
#     pgsql2shp -f ${shapefile} -u qgis fire "${HISTORY_QUERY}"
#   Note work-around for pgsql2shp bug: https://trac.osgeo.org/postgis/ticket/5018
    pgsql2shp -f "${shapefile}" -u ${user} ${database} "SELECT * FROM (${HISTORY_QUERY}) AS query"
elif [[ -n "${csvfile}" ]]; then
    echo "Creating CSV file ${csvfile}"
    psql ${database} ${user} \
        --quiet --csv \
        --command="${HISTORY_QUERY}" > "${csvfile}"
elif [[ -n "${table}" ]]; then
    echo "Creating table ${table}"
    psql ${database} ${user} \
        --quiet \
        --command="DROP TABLE IF EXISTS ${table}" \
        --command="CREATE TABLE ${table} AS ${VIEW_QUERY}"
else
    psql ${database} ${user} \
        --quiet \
        --command="$HISTORY_QUERY"
fi
