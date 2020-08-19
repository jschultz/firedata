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

help='Produce a view or shapefile containing the optionally cumulative union of hotspots at times taken froma hotspot table.'
args=(
# "-short:--long:variable:default:required:description:flags"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-H:--hotspots:::Hotspot table name:required"
  "-v:--view:::View to generate"
  "-S:--shapefile:::Shapefile to generate:output"
  "-c:--cumulative:::Generate cumulative shapes:flag"
  "-l:--logfile:::Log file to record processing, defaults to 'view'/'shapefile' + .log:private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        if [[ -n "${shapefile}" ]]; then
            logfile=$(basename ${shapefile})
            logfile="${logfile%.*}.log"
        else
            logfile="${view}.log"
        fi
    fi
    INCOMMENTS=$([ -r "${logfile}" ] && cat "${logfile}")
    echo "${COMMENTS}${INCOMMENTS}" > ${logfile}
fi

if [[ "${cumulative}" == "true" ]]; then op="<="; else op="="; fi

QUERY="SELECT datetime, 
              (SELECT ST_Union(geometry) 
               FROM ${hotspots} 
               WHERE (acq_date+acq_time)::TIMESTAMP $op datetime)
       FROM (SELECT DISTINCT (acq_date + acq_time)::TIMESTAMP AS datetime 
             FROM ${hotspots}) AS foo 
       GROUP BY datetime"

if [[ -n "${shapefile}" ]]; then
    echo "Creating shapefile ${shapefile}"
    pgsql2shp -f ${shapefile} -u qgis fire "${QUERY}"
else
    echo "Creating view ${view}"
    psql ${database} ${user} \
        --quiet \
        --command="DROP VIEW IF EXISTS ${view}" \
        --command="CREATE VIEW ${view} AS ${QUERY}"
fi