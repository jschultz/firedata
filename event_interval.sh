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
  "-e:--eventtable:::Name of database table containing event data"
  "-a:--area:::Specification of area over which event rotation will be calculated"
  ":--eventid::id:Id column in event table"
  "-S:--suffix:::Suffix to append to event table name to generate poly table name":"required"
  "-s:--sequence:::Name of sequence; appended to event table name plus suffix to generate sequence table name"
  "-C:--csvfile:::CSV file to generate:output"
  "-l:--logfile:::Log file to record processing, defaults to out file name with extension replaced by '.log' or stderr:private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        if [[ -n "${csvfile}" ]]; then
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

polytable=${eventtable}_${suffix}_poly
sequencetable=${eventtable}_${suffix}_${sequence}

INTERVAL_QUERY=""

if [[ -n "${area}" ]]; then
    INTERVAL_QUERY+="WITH area AS (SELECT ${area} AS geom) "
fi

INTERVAL_QUERY+="
    SELECT SUM(ST_AREA(poly.geom) * EXTRACT(DAY FROM event.fih_date1 - prev.fih_date1))/SUM(ST_Area(poly.geom)) AS interval
    FROM ${sequencetable} JOIN ${eventtable} AS event ON event.id = event_id 
    JOIN ${eventtable} AS prev ON prev.id = prev_event_id 
    JOIN ${polytable} AS poly ON poly.id = poly_id"
    
if [[ -n "${area}" ]]; then
    INTERVAL_QUERY+=" WHERE ST_Intersects(poly.geom, (SELECT geom FROM area))"
fi

if [[ -n "${csvfile}" ]]; then
    psql ${database} ${user} \
        --quiet --csv \
        --command="\timing off" \
        --command="${INTERVAL_QUERY}" > "${csvfile}"
else
    psql ${database} ${user} \
        --quiet --csv \
        --command="\timing off" \
        --command="${INTERVAL_QUERY}"
fi
