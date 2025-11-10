#!/bin/bash
#
# Copyright 2025 Jonathan Schultz
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

help='Dissolves adjoining polygons in a view table according to specified matching criteria'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  ":--verbosity::1:Verbosity level"
  ":--outtable:::Table to generate, defaults to \$viewtable + '_dissolve'"
  ":--outfile:::Shapefile to generate:output"
  "-m:--match:::Semicolon-delimited list of columns to match"
  ":--viewtable:::View table to dissolve:required"
  ":--polytable:::Polygon table referenced from view table:required"
  ":--eventtable:::Event table referenced from view table:"
  "-E:--existing:::Use existing tables where they exist:flag"
  "-K:--keep:::Keep tables for re-use:flag"
  "-l:--logfile:::Log file to record processing, defaults to \$outtable or \$outfile with extension replaced by '.log':private"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--nocomments:::Don't add comments to table:private,flag"
  ":--nobackup:::Don't back up existing database table:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${debug}" == "true" ]]; then
    set -x
fi

IFS=';' read -r -a match_array <<< "${match}"

if [[ ! -n "${outtable}" ]]; then
    outtable="${viewtable}_dissolve"
fi

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        if [[ -n "${outfile}" ]]; then
            logfile=$(basename "${outfile}")
            logfile="${logfile%.*}.log"
        else
            logfile="${outtable}.log"
        fi
    fi
    if [[ -r "${logfile}" ]]; then
        INCOMMENTS="$(< "${logfile}")"
    else
        INCOMMENTS=""
    fi
    echo "${COMMENTS}${INCOMMENTS}" > "${logfile}"
fi

table_exists() {
    psql --variable=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
    --command="\timing off" \
    --command "SELECT table_exists('$1')::int"
}

TEMPSCHEMA=temp
CALCSCHEMA=calc

force=false
touchestable="${CALCSCHEMA}.${polytable}_touches"
jointable="${TEMPSCHEMA}.${viewtable}_join"
maptable="${TEMPSCHEMA}.${viewtable}_map"

if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${touchestable}") == 1 ]]; then
    echo "Touches table ${touchestable} exists - skipping" >> /dev/stderr
else
    force=true
    echo "Creating touches table ${touchestable}" >> /dev/stderr
    if [[ "${nobackup}" != "true" ]]; then
        backupcommand="CALL cycle_table('${touchestable}')"
    else
        backupcommand=
    fi

    psql --variable=ON_ERROR_STOP=1 \
        --command="${backupcommand}" \
        --command="CREATE TABLE ${touchestable} AS
                        SELECT poly_1.id AS poly_id_1, poly_2.id AS poly_id_2
                        FROM ${CALCSCHEMA}.${polytable} AS poly_1, ${CALCSCHEMA}.${polytable} AS poly_2
                        WHERE poly_1.id = poly_2.id OR (ST_Touches(poly_1.geom, poly_2.geom)
                        AND ST_RelateMatch(ST_Relate(poly_1.geom, poly_2.geom),'****1****'))"
fi
if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${jointable}") == 1 ]]; then
    echo "Join table ${jointable} exists - skipping" >> /dev/stderr
else
    echo "Creating join table ${jointable}" >> /dev/stderr
    if [[ "${nobackup}" != "true" ]]; then
        backupcommand="CALL cycle_table('${jointable}')"
    else
        backupcommand=
    fi

    JOIN_QUERY="CREATE TABLE ${jointable} AS
                    SELECT poly_id_1, poly_id_2 FROM ${touchestable} AS touches, "
    JOIN_QUERY+="(SELECT poly_id"
    for ((matchidx=0; matchidx<${#match_array[@]}; matchidx++)) do
        JOIN_QUERY+=", ${match_array[matchidx]} AS match_${matchidx}"
    done
    JOIN_QUERY+=" FROM ${viewtable} AS view"
    if [[ -n "${eventtable}" ]]; then
        JOIN_QUERY+=", ${eventtable} AS event WHERE event.object_id = view.object_id[1]"
    fi
    JOIN_QUERY+=") AS event_1, "
    JOIN_QUERY+="(SELECT poly_id"
    for ((matchidx=0; matchidx<${#match_array[@]}; matchidx++)) do
        JOIN_QUERY+=", ${match_array[matchidx]} AS match_${matchidx}"
    done
    JOIN_QUERY+=" FROM ${viewtable} AS view"
    if [[ -n "${eventtable}" ]]; then
        JOIN_QUERY+=", ${eventtable} AS event WHERE event.object_id = view.object_id[1]"
    fi
    JOIN_QUERY+=") AS event_2 "
    JOIN_QUERY+="WHERE event_1.poly_id = poly_id_1 AND event_2.poly_id = poly_id_2"
    for ((matchidx=0; matchidx<${#match_array[@]}; matchidx++)) do
        JOIN_QUERY+=" AND event_1.match_${matchidx} IS NOT DISTINCT FROM event_1.match_${matchidx}"
    done

    if [[ ${verbosity} -ge 2 ]]; then
        echo "$JOIN_QUERY" > /dev/stderr
    fi
    psql --variable=ON_ERROR_STOP=1 \
        --command="${backupcommand}" \
        --command="${JOIN_QUERY}" \
        --command="CREATE INDEX ON ${jointable}(poly_id_1)" \
        --command="CREATE INDEX ON ${jointable}(poly_id_1,poly_id_2)"
fi

if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${maptable}") == 1 ]]; then
    echo "Map table ${maptable} exists - skipping" >> /dev/stderr
else
    force=true
    echo "Creating map table ${maptable}" >> /dev/stderr
    if [[ "${nobackup}" != "true" ]]; then
        backupcommand="CALL cycle_table('${maptable}')"
    else
        backupcommand=
    fi

    psql --variable=ON_ERROR_STOP=1 \
        --command="${backupcommand}" \
        --command="CREATE TABLE ${maptable} AS
                       SELECT poly_id, poly_id as map_id
                       FROM ${viewtable}" \
        --command="CREATE INDEX ON ${maptable}(poly_id)" \
        --command="CREATE INDEX ON ${maptable}(map_id)"

    echo "Updating map table ${maptable}" >> /dev/stderr
    newmaptable=${maptable##*.} # Temporary table has no schema
    while true; do
        result=$(psql --variable=ON_ERROR_STOP=1 --tuples-only --no-align \
                      --command "CREATE TEMPORARY TABLE ${newmaptable} AS
                                    SELECT map.poly_id, MIN(map_inner.map_id) AS map_id
                                    FROM ${maptable} AS map, ${jointable}, ${maptable} AS map_inner
                                    WHERE map_inner.poly_id = poly_id_2 AND map.poly_id = poly_id_1
                                    GROUP BY map.poly_id" \
                      --command="CREATE INDEX ON ${newmaptable}(poly_id)" \
                      --command="CREATE INDEX ON ${newmaptable}(map_id)" \
                      --command="UPDATE ${maptable} SET map_id = ${newmaptable}.map_id FROM ${newmaptable} WHERE ${newmaptable}.poly_id = ${maptable}.poly_id AND ${maptable}.map_id != ${newmaptable}.map_id" \
                | tee /dev/tty \
                | grep UPDATE)
        if [[ ${verbosity} -ge 2 ]]; then
            echo ${result}
        fi
        if [[ "${result}" == "UPDATE 0" ]]; then
            break
        fi
    done
fi

if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${outtable}") == 1 ]]; then
    echo "Table ${outtable} exists - skipping" >> /dev/stderr
else
    force=true
    if [[ "${nobackup}" != "true" ]]; then
        backupcommand="CALL cycle_table('${outtable}')"
    else
        backupcommand=
    fi

    DISSOLVE_QUERY="SELECT map_id, unionq.geom"
    for ((matchidx=0; matchidx<${#match_array[@]}; matchidx++)) do
        DISSOLVE_QUERY+=", ${match_array[matchidx]}"
    done
    DISSOLVE_QUERY+=" FROM (SELECT map_id, ST_Union(geom) AS geom
                            FROM ${maptable} AS map, ${CALCSCHEMA}.${polytable} AS poly
                            WHERE poly.id = map.poly_id
                            GROUP BY map_id) AS unionq,
                            ${viewtable} AS view"
    if [[ -n "${eventtable}" ]]; then
        DISSOLVE_QUERY+=", ${eventtable} AS event"
    fi
    DISSOLVE_QUERY+=" WHERE poly_id = map_id"
    if [[ -n "${eventtable}" ]]; then
        DISSOLVE_QUERY+=" AND event.object_id = view.object_id[1]"
    fi
    if [[ ${verbosity} -ge 2 ]]; then
        echo "$DISSOLVE_QUERY" > /dev/stderr
    fi

    if [[ -n "${outfile}" ]]; then
        if [[ ${verbosity} -ge 1 ]]; then
            echo "Creating dissolve shapefile ${outfile}"
        fi
        pgsql2shp -q -f "${outfile}" -u $PGUSER $PGDATABASE "${DISSOLVE_QUERY}"
        zip --move --junk-paths "${outfile}".zip "${outfile}".{cpg,dbf,prj,shp,shx}
    else
        if [[ ${verbosity} -ge 1 ]]; then
            echo "Creating dissolve table ${outtable}"
        fi
        if [[ "${nobackup}" != "true" ]]; then
            backupcommand="CALL cycle_table('${outtable}')"
        else
            backupcommand=
        fi
        if [[ "${nocomments}" != "true" ]]; then
            commentcommand="COMMENT ON TABLE ${outtable} IS '${COMMENTS//\'/\'\'}'"
        else
            commentcommand=
        fi
        psql --quiet \
                --command="${backupcommand}" \
                --command="CREATE TABLE ${outtable} AS ${DISSOLVE_QUERY}" \
                --command="${commentcommand}"
    fi
fi

if [[ "${keep}" != "true" ]]; then
    echo "Dropping join table ${jointable}" >> /dev/stderr
    psql --variable=ON_ERROR_STOP=1 \
         --command="DROP TABLE ${jointable}"

    echo "Dropping map table ${maptable}" >> /dev/stderr
    psql --variable=ON_ERROR_STOP=1 \
         --command="DROP TABLE ${maptable}"
fi
