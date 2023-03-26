#!/bin/bash
#
# Copyright 2023 Jonathan Schultz
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
  "-e:--eventtable:::Semicolon-delimited name(s) of database table(s) containing event data":required
  ":--eventid:::Semicolon-delimited Id column(s) in event table(s). Default is 'id'"
  ":--eventorder:::Semicolon-separated list of sort order for event table(s); empty value means use 'eventid'"
  "-g:--geometry::geom:Semicolon-delimited name(s) of geometry column(s) in event tables"
  "-b:--basename:::Table name base for output dump, polygon, point-in-polygon and junction output tables. Default is first event table name"
  "-j:--junction:::Semicolon-delimited junction table names. Default is 'eventtable'_junction"
  "-S:--suffix:::Suffix to append to first event table name to generate dump, polygon, point-in-polygon and junction table names:deprecated"
  ":--polycolumns:::Semicolon-separated list of columns to retrieve from polygon table"
  ":--polyaliases:::Semicolon-separated list of aliases for columns retrieved from polygon table"
  "-c:--eventcolumns::id:Semicolon-separated list of fully specified columns (table and colume name) to retrieve from event table(s)"
  ":--eventaliases:::Semicolon-separated list of aliases for columns retrieved from event table(s); empty value means use column name as alias"
  "-w:--where:::WHERE clause for selecting from polygon table"
  "-a:--append:::Append output to existing view table:flag"
  "-v:--viewtable:::Table to generate, defaults to \$eventtable + \$suffix + '_view'"
  "-S:--viewfile:::Shapefile to generate:output"
  "-l:--logfile:::Log file to record processing, defaults to \$viewtable or \$viewfile with extension replaced by '.log', or \$eventtable + \$suffix' + '.log' if neither \$viewtable nor \$viewfile is defined:private"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--nocomments:::Don't add comments to table:private,flag"
  ":--nobackup:::Don't back up existing database table:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${debug}" == "true" ]]; then
    set -x
fi

IFS=';' read -r -a eventtable_array <<< "${eventtable}"
IFS=';' read -r -a eventid_array    <<< "${eventid}"
IFS=';' read -r -a eventorder_array <<< "${eventorder}"
IFS=';' read -r -a geometry_array   <<< "${geometry}"
IFS=';' read -r -a junction_array   <<< "${junction}"
IFS=';' read -r -a polycolumn_array <<< "${polycolumns}"
IFS=';' read -r -a polyalias_array  <<< "${polyaliases}"
IFS=';' read -r -a eventcolumn_array <<< "${eventcolumns}"
IFS=';' read -r -a eventalias_array <<< "${eventaliases}"

if [[ ! -n "${basename}" ]]; then
    basename=${eventtable_array[0]}
    if [[ ! -n "${suffix}" ]]; then
        basename=${basename}_${suffix}
    fi
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

for ((colidx=0; colidx<${#polycolumn_array[@]}; colidx++)) do
    if [[ ! -n "${polyalias_array[colidx]}" ]]; then
        polyalias_array[colidx]="${polycolumn_array[colidx]}"
    fi
done

if [[ "${append}" == "true" && -n "${viewfile}" ]]; then
    echo "'append' option cannot be used when producing a shapefile" > /dev/stderr
    return 1
fi

polytable=${basename}_poly

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    if [[ ! -n "${eventid_array[tableidx]}" ]]; then
        eventid_array[tableidx]="id"
    fi
    if [[ ! -n "${eventorder_array[tableidx]}" ]]; then
        eventorder_array[tableidx]="${eventtable_array[tableidx]}.${eventid_array[tableidx]}"
    fi
    if [[ ! -n "${geometry_array[tableidx]}" ]]; then
        geometry_array[tableidx]="geom"
    fi
    if [[ ! -n "${junction_array[tableidx]}" ]]; then
        junction_array[tableidx]="${basename}_${eventtable_array[tableidx]}_junction"
    fi
done

if [[ ! -n "${viewtable}" ]]; then
    viewtable=${basename}_view
fi

for ((colidx=0; colidx<${#eventcolumn_array[@]}; colidx++)) do
    if [[ ! -n "${eventalias_array[colidx]}" ]]; then
        eventalias_array[colidx]="${eventcolumn_array[colidx]#*.}"
    fi
done

VIEW_QUERY="SELECT"
separator=""
for ((colidx=0; colidx<${#polyalias_array[@]}; colidx++)) do
    VIEW_QUERY+="${separator} ${polytable}.${polycolumn_array[colidx]} AS ${polyalias_array[colidx]}"
    separator=","
done
for ((colidx=0; colidx<${#eventalias_array[@]}; colidx++)) do
    VIEW_QUERY+="${separator} ${eventcolumn_array[colidx]} AS ${eventalias_array[colidx]}"
    separator=","
done
VIEW_QUERY+=" FROM ${polytable}"
for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    VIEW_QUERY+=" LEFT OUTER JOIN (SELECT ${junction_array[tableidx]}.poly_id"
    for ((colidx=0; colidx<${#eventcolumn_array[@]}; colidx++)) do
        if [[ "${eventcolumn_array[colidx]%.*}" == "${eventtable_array[tableidx]}" ]]; then
            VIEW_QUERY+=", array_agg(${eventcolumn_array[colidx]} ORDER BY ${eventorder_array[tableidx]}) AS ${eventcolumn_array[colidx]#*.}"
        fi
    done
    VIEW_QUERY+=" FROM ${junction_array[tableidx]}, ${eventtable_array[tableidx]} WHERE ${eventtable_array[tableidx]}.${eventid_array[tableidx]}=${junction_array[tableidx]}.${eventid_array[tableidx]}"
    VIEW_QUERY+=" GROUP BY ${junction_array[tableidx]}.poly_id"
    VIEW_QUERY+=") AS ${eventtable_array[tableidx]} ON ${eventtable_array[tableidx]}.poly_id = ${polytable}.id"
done
if [[ -n "${where}" ]]; then
    VIEW_QUERY+=" WHERE ${where}"
fi
if [[ ${#polycolumn_array[@]} -gt 0 ]]; then
    VIEW_QUERY+=" GROUP BY"
    separator=""
    for ((colidx=0; colidx<${#polycolumn_array[@]}; colidx++)) do
        VIEW_QUERY+="${separator} ${polytable}.${polycolumn_array[colidx]}"
        separator=","
    done
    for ((colidx=0; colidx<${#eventcolumn_array[@]}; colidx++)) do
        VIEW_QUERY+="${separator} ${eventcolumn_array[colidx]}"
        separator=","
    done
fi

if [[ "${debug}" == "true" ]]; then
    echo "---------------------------------------------" > /dev/stderr
    echo "$VIEW_QUERY"                                   > /dev/stderr  
    echo "---------------------------------------------" > /dev/stderr
fi

if [[ -n "${viewfile}" ]]; then
    echo "Creating shapefile ${viewfile}"
    pgsql2shp -f ${viewfile} -u $PGUSER $PGDATABASE "${VIEW_QUERY}"
else
    if [[ "${append}" != "true" ]]; then
        echo "Creating table ${viewtable}"
        if [[ "${nobackup}" != "true" ]]; then  
            backupcommand="CALL cycle_table('${viewtable}')"
        else
            backupcommand=
        fi
        if [[ "${nocomments}" != "true" ]]; then
            commentcommand="COMMENT ON TABLE \"${viewtable}\" IS '${COMMENTS//\'/\'\'}'"
        else
            commentcommand=
        fi
        psql --quiet \
             --command="${backupcommand}" \
             --command="CREATE TABLE ${viewtable} AS ${VIEW_QUERY}" \
             --command="CREATE INDEX ON ${viewtable} (id)"
             --command="${commentcommand}"
    else
        echo "Appending to table ${viewtable}"
        if [[ "${nocomments}" != "true" ]]; then
            INCOMMENTS=$(psql --csv --tuples-only --no-align --quiet --command="\timing off" --command "SELECT obj_description('${viewtable}'::regclass, 'pg_class')")
            NEWCOMMENTS="${COMMENTS}${INCOMMENTS}"
            commentcommand="COMMENT ON TABLE \"${viewtable}\" IS '${NEWCOMMENTS//\'/\'\'}'"
        else
            commentcommand=
        fi
        
        psql --quiet \
             --command="CREATE TEMP TABLE ${viewtable}_append AS ${VIEW_QUERY}" \
             --command="INSERT INTO ${viewtable} SELECT * FROM ${viewtable}_append" \
             --command="${commentcommand}"
    fi
fi
