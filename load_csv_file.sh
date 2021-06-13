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

# PSQL_USER=qgis
# PSQL_DATABASE=fire
# PSQL_TABLE=dpaw_fuel_age

set -e

help='Create a PostgreSQL table from GeoCSV files (.csv, .csvt, .prj).'
args=(
# "-short:--long:variable:default:help:flags"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-c:--csv:::GeoCSV file name with no extension:required"
  "-t:--table:::Table name to load, default is GeoCSV file name:"
)

source $(dirname "$0")/argparse.sh

if [[ ! -n "$table" ]]; then
    table=$(basename "$csv")
    table="${table%.*}"
fi
columns=$(head -1 "$csv")
psql --username=$user --dbname=$database --command="\copy $table ($columns) FROM '$csv' CSV HEADER;"
