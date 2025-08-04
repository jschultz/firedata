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
  ":--debug:::Debug execution:flag"
  "-t:--table:::Name of table to create, defaults to file name without extension"
  "-a:--append:::Append to existing table; otherwise overwrite:flag"
  "-g:--geometry::geom:Name of column to hold geometry data"
  "-s:--srid:::SRID to re-project geometry"
  "-L:--layer:::Layer to import"
  ":filename:::Name of file to read:input"
  "-l:--logfile:::Log file to record processing, defaults to table name with extension '.log':private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ ! -n "${table}" ]]; then
    if [[ -n "${filename}" ]]; then
        table=$(basename "${filename}")
        table="${table%.*}"
    else
        echo "At least one of 'table' and 'filename' must be specified" > /dev/stderr
        exit 1
    fi
fi
if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        logfile=${table}.log
    fi
    echo "${COMMENTS}" > "${logfile}"
fi

if [[ "${debug}" == "true" ]]; then
    set -x
fi

if [[ -n "${srid}" ]]; then
    srid="-t_srs EPSG:${srid}"
fi

if [[ ! -n "${filename}" ]]; then
    filename=$(mktemp)
    cat >${filename}
fi

if [[ "${append}" == "true" ]]; then
    overwrite=
else
    overwrite="-overwrite"
fi

if [[ -n "${geometry}" ]]; then
    ogr2ogr ${overwrite} -f PostgreSQL "PG:dbname=$PGDATABASE user=${PGUSER-$USER}" -lco geometry_name=${geometry} ${srid} -nln "${table}" -nlt PROMOTE_TO_MULTI "${filename}" ${layer}
#     psql \
#         --quiet --command="\timing off" \
#         --command="CREATE INDEX ON ${table} USING gist (${geometry})"
else
    ogr2ogr -overwrite -f PostgreSQL "PG:dbname=$PGDATABASE user=${PGUSER-$USER}" -nln "${table}" -nlt PROMOTE_TO_MULTI "${filename}" ${layer}
fi
