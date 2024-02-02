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

help='Load hotspot data from FIRMS into PostGIS table.'
args=(
# "-short:--long:variable:default:description:flags"
  "-k:--key:::FIRMS map key (See firms.modaps.eosdis.nasa.gov/api/map_key/):required"
  "-t:--table::hotspots:Hotspot table name:"
  "-g:--geometry::geom:Name of column to hold geometry data"
  "-s:--srid:::SRID to re-project geometry:required"
  "-a:--area:::Comma-separated West, South, East, North latitude/longitude"
  "-s:--start:::Start date"
  "-e:--end:::End date"
  "-l:--logfile:::Log file to record processing, defaults to 'table' + .log:private"
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

psql --command "CREATE TABLE IF NOT EXISTS ${table} ( ${geometry} geometry(Point,${srid}) GENERATED ALWAYS AS (ST_MakePoint(longitude, latitude)) STORED, latitude float, longitude float, brightness float, scan float, track float, satellite text, instrument text, confidence text, version text, bright_ti4 float, bright_ti5 float, bright_t31 float, frp float, daynight char, type integer, acq_date text, acq_time text, acq_datetime timestamp without time zone GENERATED ALWAYS AS (make_timestamp(substring(acq_date,1,4)::integer, substring(acq_date,6,2)::integer, substring(acq_date,9,2)::integer, acq_time::integer/100, acq_time::integer%100, 0)) STORED )"

if [[ -n "${srid}" ]]; then
    sridoption="-t_srs EPSG:${srid}"
fi

startdays=$(( $(date -d "${start}" "+%s") ))
enddays=$(( $(date -d "${end}" "+%s") ))
daysremaining=$(( $enddays / 86400 - $startdays / 86400 + 1 ))
while [[ $daysremaining -gt 0 ]]; do
    start=$(date -d @$(( $startdays )) +%Y-%m-%d)
    if [[ $daysremaining -gt 10 ]]; then
        days=10
        daysremaining=$(( $daysremaining - 10 ))
    else
        days=$daysremaining
        daysremaining=0
    fi
    startdays=$(( $startdays + $days * 86400 ))
    
    curl --silent -X GET --header 'Accept: text/csv' "https://firms.modaps.eosdis.nasa.gov/api/area/csv/${key}/VIIRS_SNPP_SP/${area}/${days}/${start}" > viirs.csv
    ogr2ogr -f PostgreSQL "PG:dbname=$PGDATABASE user=$PGUSER" -lco geometry_name=${geometry} ${sridoption} -nln "${table}" -nlt POINT viirs.csv
    curl --silent -X GET --header 'Accept: text/csv' "https://firms.modaps.eosdis.nasa.gov/api/area/csv/${key}/MODIS_SP/${area}/${days}/${start}" > modis.csv
    ogr2ogr -f PostgreSQL "PG:dbname=$PGDATABASE user=$PGUSER" -lco geometry_name=${geometry} ${sridoption} -nln "${table}" -nlt POINT modis.csv
done