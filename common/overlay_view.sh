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

help='Produces a table or shapefile containing polygon ID and geometry and a selection of event columns. Requires event, polygon and junction tables. The last two can be generated from an event table by overlay_junction.sh'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  "-e:--eventtable:::Name of database table containing event data"
  ":--eventid::id:Id column in event table"
  "-s:--suffix:::Suffix to append to event table name to generate other table names:required"
  "-p:--polygon:::Polygon table"
  "-j:--junction:::Junction table"
  ":--polycolumns:::Comma-separated list of columns to retrieve from polygon table"
  ":--polyaliases:::Comma-separated list of aliases for columns retrieved from polygon table"
  "-c:--eventcolumns::objectid:Comma-separated list of columns to retrieve from event data"
  ":--eventaliases:::Comma-separated list of aliases for columns retrieved from burn data; empty value means use column name as alias"
#   "-n:--number:::Number of links to copy; default is minimum required to hold all links in the junction table"
  "-g:--geometry::geom:Column name for geometry in tables"
  "-w:--where:::WHERE clause for selecting from polygon table"
  "-v:--viewtable:::Table to generate, defaults to \$eventtable + \$suffix + '_view'"
  "-S:--viewfile:::Shapefile to generate:output"
  "-l:--logfile:::Log file to record processing, defaults to \$shapefile with extension replaced by '.log', or \$table.log, or \$eventtable + \$suffix' + '.log' if neither shapefile nor table is defined:private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ ! -n "${polygon}" ]]; then
    base=${eventtable}
    polygon=${base}_${suffix}_poly
else
    base=${polygon}
fi

if [[ ! -n "${junction}" ]]; then
    junction=${base}_${suffix}_junction
fi

if [[ ! -n "${viewtable}" ]]; then
    table=${base}_${suffix}_view
fi

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        if [[ -n "${viewfile}" ]]; then
            logfile=$(basename ${viewfile})
            logfile="${logfile%.*}.log"
        else
            logfile="${viewtable}.log"
        fi
    fi
    if [[ -r "${logfile}" ]]; then
        INCOMMENTS="$(< "${logfile}")"
    else
        INCOMMENTS=""
    fi
    echo "${COMMENTS}${INCOMMENTS}" > "${logfile}"
fi

if [[ "${debug}" == "true" ]]; then
    set -x
fi

IFS=',' read -r -a polycolumnarray <<< "${polycolumns}"
IFS=',' read -r -a polyaliasarray <<< "${polyaliases}"
for ((colidx=0; colidx<${#polycolumnarray[@]}; colidx++)) do
    if [[ ! -n "${polyaliasarray[colidx]}" ]]; then
        polyaliasarray[colidx]="${polycolumnarray[colidx]}"
    fi
done

IFS=',' read -r -a eventcolumnarray <<< "${eventcolumns}"
IFS=',' read -r -a eventaliasarray <<< "${eventaliases}"
for ((colidx=0; colidx<${#eventcolumnarray[@]}; colidx++)) do
    if [[ ! -n "${eventaliasarray[colidx]}" ]]; then
        eventaliasarray[colidx]="${eventcolumnarray[colidx]}"
    fi
done

VIEW_QUERY="SELECT"
separator=""
for ((colidx=0; colidx<${#polyaliasarray[@]}; colidx++)) do
    VIEW_QUERY+="${separator} agg.${polyaliasarray[colidx]}"
    separator=","
done
for ((colidx=0; colidx<${#eventaliasarray[@]}; colidx++)) do
    VIEW_QUERY+="${separator} agg.${eventaliasarray[colidx]} AS ${eventaliasarray[colidx]}"
    separator=","
done
VIEW_QUERY+=" FROM (SELECT"
separator=""
for ((colidx=0; colidx<${#polycolumnarray[@]}; colidx++)) do
    VIEW_QUERY+="${separator} poly.${polycolumnarray[colidx]} AS ${polyaliasarray[colidx]}"
    separator=","
done
for ((colidx=0; colidx<${#eventcolumnarray[@]}; colidx++)) do
    VIEW_QUERY+="${separator} array_agg(event.${eventcolumnarray[colidx]} ORDER BY fih_date1 DESC, event.${eventid} DESC) AS ${eventaliasarray[colidx]}"
    separator=","
done
VIEW_QUERY+=" FROM ${junction} AS junction
               JOIN ${polygon} AS poly ON poly.id = junction.poly_id
               JOIN ${eventtable} AS event ON event.${eventid} = event_id"
if [[ -n "${where}" ]]; then
    VIEW_QUERY+=" WHERE ${where}"
fi
if [[ ${#polycolumnarray[@]} -gt 0 ]]; then
    VIEW_QUERY+=" GROUP BY"
    separator=""
    for ((colidx=0; colidx<${#polycolumnarray[@]}; colidx++)) do
        VIEW_QUERY+="${separator} poly.${polycolumnarray[colidx]}"
        separator=","
    done
fi
VIEW_QUERY+=") agg"
# echo $VIEW_QUERY
if [[ -n "${viewfile}" ]]; then
    echo "Creating shapefile ${viewfile}"
    pgsql2shp -f ${viewfile} -u $PGUSER $PGDATABASE "${VIEW_QUERY}"
else
    echo "Creating table ${viewtable}"
    psql \
        --quiet \
        --command="DROP TABLE IF EXISTS ${viewtable}" \
        --command="CREATE TABLE ${viewtable} AS ${VIEW_QUERY}"
fi
