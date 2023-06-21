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

help='Merges tables of non-intersecting polygons into a new table of non-intersecting polygons.'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  "-e:--eventtable:::Semicolon-delimited name(s) of database table(s) containing event data":required
  ":--eventid:::Semicolon-delimited Id column(s) in event table(s). Default is 'id'"
  "-b:--basename:::Table name base for output dump, polygon, point-in-polygon and junction output tables. Default is first event table name"
  "-g:--geometry::geom:Semicolon-delimited name(s) of geometry column(s) in event tables"
  "-w:--where:::WHERE clause(s) for selecting from event table(s); deprecated in favour of 'area':deprecated"
  "-a:--area:::Area to constrain junction calculation"
  "--E:--existing:::Use existing tables where they exist:flag"
  "--K:--keep:::Keep tables for re-use:flag"
  "-l:--logfile:::Log file to record processing, defaults to 'basename' + .log"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--nobackup:::Don't back up existing database tables:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${debug}" == "true" ]]; then
    set -x
fi

IFS=';' read -r -a eventtable_array <<< "${eventtable}"
IFS=';' read -r -a eventid_array    <<< "${eventid}"
IFS=';' read -r -a geometry_array   <<< "${geometry}"

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${basename}.log"
    fi
    echo "${COMMENTS}" > ${logfile}
fi

poly=${basename}_poly
point=${basename}_point

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    if [[ ! -n "${eventid_array[tableidx]}" ]]; then
        eventid_array[tableidx]="id"
    fi
    if [[ ! -n "${geometry_array[tableidx]}" ]]; then
        geometry_array[tableidx]="geom"
    fi
done

force=false

echo "Testing SRIDs" >> /dev/stderr

SRID=$(psql \
            --quiet --tuples-only --no-align --command="\timing off" \
            --command "SELECT ST_SRID(${geometry_array[0]}) AS srid FROM ${eventtable_array[0]} LIMIT 1" )
            
if [[ $SRID -eq 0 ]]; then
    echo "ERROR: Missing SRID in shape table geometries" >> /dev/stderr
    return 1
fi

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    MULTIPLE_SRID=$(psql \
                --quiet --tuples-only --no-align --command="\timing off" \
                --command "SELECT EXISTS(
                            SELECT ST_SRID(${geometry_array[tableidx]}) AS srid FROM ${eventtable_array[tableidx]} WHERE ST_SRID(${geometry_array[tableidx]}) != '${SRID}')" )
    if [[ "$MULTIPLE_SRID" == "t" ]]; then
        echo "ERROR: Multiple SRIDs in shape table geometries" >> /dev/stderr
        return 1
    fi
done

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
done

