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

help='Load a GeoPackage file into a PostGIS table.'
args=(
# "-short:--long:variable:default:required:description:flags"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-t:--table:::Table name, defaults to file name without extension"
  ":filename:::GeoPackage file name:required,input"
)

source $(dirname "$0")/argparse.sh

if [[ ! -n "${table}" ]]; then
    table=$(basename ${filename})
    table="${table%.*}"
fi
echo "${COMMENTS}" > ${table}.log

ogr2ogr -overwrite -f PostgreSQL "PG:dbname=${database} user=${user}" -t_srs EPSG:4326  -lco geometry_name=geometry "${filename}" -nln "${table}"