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

help='Load a file into a PostGIS table. The file may be of any kind supported by ogr2ogr'
args=(
# "-short:--long:variable:default:description:flags"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-t:--table:::Name of table to create, defaults to file name without extension"
  "-g:--geometry::geom:Name of column to hold geometry data"
  ":filename:::Name of file to read:required,input"
)

source $(dirname "$0")/argparse.sh

if [[ ! -n "${table}" ]]; then
    table=$(basename ${filename})
    table="${table%.*}"
fi
echo "${COMMENTS}" > ${table}.log

ogr2ogr -overwrite -f PostgreSQL "PG:dbname=${database} user=${user}" -lco geometry_name=${geometry} "${filename}" -nln "${table}"