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

help='Produces a list of fires that intersect a given geometry'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-b:--burn-id:::Burn ID to specify geometry:required"
  "-t:--threshhold::10:Minimum percentage of geometry"
  "-S:--shapefile:::Shapefile to generate:output"
  "-l:--logfile:::Log file to record processing, defaults to \$shapefile with extension replaced by '.log':private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        if [[ -n "${shapefile}" ]]; then
            logfile=$(basename ${shapefile})
            logfile="${logfile%.*}.log"
        else
            logfile="burn_history.log"
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

psql ${database} ${user} \
    --quiet \
    --command="CREATE TEMP TABLE history AS
SELECT objectid,
       st_area(st_intersection(dbcafirehistorydbca_060.geometry, burn.geometry)) / st_area(burn.geometry) * 100 AS percent
FROM dbcafirehistorydbca_060, 
     (SELECT st_union(geometry) AS geometry FROM daily_burns WHERE burn_id = '${burn_id}' GROUP BY burn_target_date_raw ORDER BY burn_target_date_raw DESC LIMIT 1) AS burn
WHERE  st_area(st_intersection(dbcafirehistorydbca_060.geometry, burn.geometry)) / st_area(burn.geometry) > 0.1 ORDER BY fih_date1" \
    --command="SELECT history.*, fih_date1, fih_fire_type FROM history, dbcafirehistorydbca_060 WHERE dbcafirehistorydbca_060.objectid = history.objectid"

