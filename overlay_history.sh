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

help='Create history of all fires that intersected areas in a table.'
args=(
# "-short:--long:variable:default:required:description:flags"
  "-u:--user:::PostgreSQL username":"required"
  "-d:--database:::PostgreSQL database":"required"
  "-s:--shape:::Table name containing fire shape data"
  ":--shapeid::objectid:Id column in shape table"
  "-S:--suffix:::Suffix to append to polygon table name to generate other table names":"required"
  "-p:--polygon:::Polygon table":"required"
  ":--polyid::id:ID column in polygon table"
  "-l:--logfile:::Log file to record processing, defaults to 'polygon' + 'suffix' + .log"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${polygon}_${suffix}.log"
    fi
    echo "${COMMENTS}" > ${logfile}
fi

junction=${polygon}_${suffix}_junction

echo "Creating junction table ${junction}"
psql ${database} ${user} \
    --quiet \
    --command="DROP TABLE IF EXISTS ${junction} CASCADE" \
    --command="CREATE TABLE ${junction} (poly_id INTEGER, shape_id INTEGER)" \
    --command="INSERT INTO ${junction}  (poly_id, shape_id)
                SELECT poly.${polyid}, shape.${shapeid}
                FROM ${polygon} poly
                  JOIN ${shape} shape
                  ON ST_Intersects(shape.geometry, poly.geometry)
                GROUP BY poly.${polyid}, shape.${shapeid}"
