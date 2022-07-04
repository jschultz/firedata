#!/bin/bash
#
# Copyright 2022 Jonathan Schultz
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

help='Load a file into a PostGIS table. The file may be of any kind supported by ogr2ogr'
args=(
# "-short:--long:variable:default:description:flags"
  "-t:--table:::Name of table to create, defaults to file name without extension"
  "-g:--geometry::geom:Name of column to hold geometry data"
  "-s:--srid::geom:SRID to re-project geometry"
  "-L:--layer:::Layer to import"
  ":filename:::Name of file to read:required,input"
  "-l:--logfile:::Log file to record processing, defaults to table name with extension '.log':private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ ! -n "${table}" ]]; then
    table=$(basename ${filename})
    table="${table%.*}"
fi
if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        logfile=${table}.log
    fi
    echo "${COMMENTS}" > ${logfile}
fi

if [[ -n "${srid}" ]]; then
    srid="-t_srs EPSG:${srid}"
fi

ogr2ogr -overwrite -f PostgreSQL "PG:dbname=$PGDATABASE user=$PGUSER" -lco geometry_name=${geometry} ${srid} -nln "${table}" "${filename}" ${layer}
