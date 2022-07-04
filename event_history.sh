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
  "-e:--eventtable:::Name of table containing event history:required"
  "-a:--area:::Specification of area of which history will be extracted"
  "-c:--eventcolumns::objectid:Semicolon-separated list of columns to retrieve from event data"
  "-g:--eventgroups:::Semicolon-separated list of columns to group event data"
  ":--eventaliases:::Semicolon-separated list of aliases for columns retrieved from event data; empty value for no alias"
  "-o:--order:::Comma-separated expression(s) to sort retrieved data"
  "-f:--filter:::Condition applied after query execution"
  "-w:--with:::Common table expression (CTE) for database query"
  "-t:--table:::Database table to generate"
  "-C:--csvfile:::CSV file to generate:output"
  "-S:--shapefile:::Shapefile to generate:output"
  "-l:--logfile:::Log file to record processing, defaults to out file name with extension replaced by '.log' or stderr:private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        if [[ -n "${shapefile}" ]]; then
            logfile=$(basename ${shapefile})
            logfile="${logfile%.*}.log"
        elif [[ -n "${csvfile}" ]]; then
            logfile="${csvfile%.*}.log"
        else
            logfile="/dev/stderr"
        fi
    fi
    echo -n "${COMMENTS}" > "${logfile}"
fi

if [[ "${debug}" == "true" ]]; then
    set -x
fi

IFS=';' read -r -a eventcolumnarray <<< "${eventcolumns}"
IFS=';' read -r -a eventaliasarray <<< "${eventaliases}"
IFS=';' read -r -a eventgrouparray <<< "${eventgroups}"

HISTORY_QUERY=""

if [[ -n "${area}" || -n "${with}" ]]; then
    HISTORY_QUERY+="WITH "
    if [[ -n "${area}" ]]; then
        HISTORY_QUERY+="area AS (SELECT ${area} AS geom) "
        if [[ -n "${with}" ]]; then
            HISTORY_QUERY+=", "
        fi
    fi
    if [[ -n "${with}" ]]; then
        HISTORY_QUERY+="${with} "
    fi
fi
HISTORY_QUERY+="SELECT * FROM (SELECT"
separator=""
for ((colidx=0; colidx<${#eventcolumnarray[@]}; colidx++)) do
    HISTORY_QUERY+="${separator} ${eventcolumnarray[colidx]}"
    if [[ -n "${eventaliasarray[colidx]}" ]]; then
        HISTORY_QUERY+=" AS \"${eventaliasarray[colidx]}\""
    fi
    separator=","
done
HISTORY_QUERY+="
    FROM ${eventtable} AS event"
if [[ -n "${area}" ]]; then
    HISTORY_QUERY+=", area
    WHERE
        ST_Intersects(event.geom, area.geom)
    GROUP BY"
    separator=""
else
    HISTORY_QUERY+="
    GROUP BY"
    separator=""
fi
if [[ ${#eventgrouparray[@]} -gt 0 ]]; then
    for ((colidx=0; colidx<${#eventgrouparray[@]}; colidx++)) do
        HISTORY_QUERY+="${separator} ${eventgrouparray[colidx]}"
        separator=","
    done
fi
if [[ -n "${order}" ]]; then
    HISTORY_QUERY+="
    ORDER BY ${order}"
fi
HISTORY_QUERY+=") AS prefilter_query"
if [[ -n "${filter}" ]]; then
    HISTORY_QUERY+=" WHERE (${filter})"
fi

if [[ "${debug}" == "true" ]]; then
    echo "---------------------------------------------" > /dev/stderr
    echo "$HISTORY_QUERY"                                > /dev/stderr  
    echo "---------------------------------------------" > /dev/stderr
fi

if [[ -n "${shapefile}" ]]; then
    echo "Creating shapefile ${shapefile}"
     pgsql2shp -f ${shapefile}  -u $PGUSER $PGDATABASE "${HISTORY_QUERY}"
#    Work-around for pgsql2shp bug: https://trac.osgeo.org/postgis/ticket/5018
#    pgsql2shp -f "${shapefile}" -u $PGUSER $PGDATABASE "SELECT * FROM (${HISTORY_QUERY}) AS query"
    zip --move --junk-paths "${shapefile}".zip "${shapefile}".{cpg,dbf,prj,shp,shx}
elif [[ -n "${table}" ]]; then
    echo "Creating table ${table}"
    psql \
        --quiet \
        --command="DROP TABLE IF EXISTS \"${table}\"" \
        --command="CREATE TABLE \"${table}\" AS ${HISTORY_QUERY}"
else
    if [[ "${nologfile}" != "true" ]]; then
        echo "################################################################################" >> "${logfile}"
    fi
    if [[ -n "${csvfile}" ]]; then
        psql \
            --quiet --csv \
            --command="\timing off" \
            --command="${HISTORY_QUERY}" > "${csvfile}"
    else
        psql \
            --quiet --csv \
            --command="\timing off" \
            --command="${HISTORY_QUERY}"
    fi
fi
