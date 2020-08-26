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

help='Produce a table or file containing the optionally cumulative union of hotspots at times taken froma hotspot table.'
args=(
# "-short:--long:variable:default:description:flags"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-H:--hotspots:::Hotspot table name:required"
  "-t:--table:::Table to generate"
  "-o:--outfile:::Output file to generate; extension specifies format:output"
  "-c:--cumulative:::Generate cumulative shapes:flag"
  "-d:--distance::50:Distance in metres to blur the shape merge"
  ":--target-percent::0.8:Target percent (between 0 and 1) to pass to ST_ConcaveHull. Smaller takes longer and makes a tighter fit"
  "-l:--logfile:::Log file to record processing, defaults to 'table'/'outfile' + .log:private"
  ":--no-logfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${no_logfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        if [[ -n "${outfile}" ]]; then
            logfile=$(basename ${outfile})
            logfile="${logfile%.*}.log"
        else
            logfile="${table}.log"
        fi
    fi
    echo "${COMMENTS}" > ${logfile}
fi

if [[ "${cumulative}" == "true" ]]; then op="<="; else op="="; fi

QUERY="SELECT datetime,
              satellite,
              (SELECT ST_Union(ST_ConcaveHull((SELECT ST_Union(hotspots2.geometry)
                                               FROM ${hotspots} AS hotspots2
                                               WHERE hotspots1.acq_date  = hotspots2.acq_date 
                                               AND   hotspots1.acq_time  = hotspots2.acq_time 
                                               AND   hotspots1.satellite = hotspots2.satellite 
                                               AND   ST_DWithin(hotspots1.geometry, hotspots2.geometry, ${distance})), 
                                               ${target_percent}))
               FROM ${hotspots} AS hotspots1
               WHERE (acq_date+acq_time)::TIMESTAMP $op datetime)
               AS geometry
      FROM (SELECT DISTINCT (acq_date + acq_time)::TIMESTAMP AS datetime, satellite 
            FROM ${hotspots}) AS foo
      GROUP BY datetime, satellite"

if [[ -n "${outfile}" ]]; then
    echo "Creating file ${outfile}"
    ogr2ogr "${outfile}" "PG:dbname=${database} user=${user}" -sql "${QUERY}"
else
    echo "Creating table ${table}"
    psql ${database} ${user} \
        --quiet \
        --command="DROP TABLE IF EXISTS ${table}" \
        --command="CREATE TABLE ${table} AS ${QUERY}"
fi