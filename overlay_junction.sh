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

help='Creates an overlay of non-intersecting polygons from a collection of possibly overlapping shapes. Produces a polygon table and a junction table between the polygon and original shape tables.'
args=(
# "-short:--long:variable:default:required:description:flags"
  "-u:--user:::PostgreSQL username":"required"
  "-d:--database:::PostgreSQL database":"required"
  "-s:--shape:::Table name containing geometrical data"
  ":--shapeid::objectid:Id column in shape table"
  "-S:--suffix:::Suffix to append to shape table name to generate other table names":"required"
  "-g:--geometry:::Column name for geometry in 'shape' table"
  "-w:--where:::WHERE clause for selecting from 'shape' table"
  "-l:--logfile:::Log file to record processing, defaults to 'shape' + 'suffix' + .log"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--leavedump:::Don't drop intermediate dump table:flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${shape}_${suffix}.log"
    fi
    echo "${COMMENTS}" > ${logfile}
fi

dump=${shape}_${suffix}_dump
poly=${shape}_${suffix}_poly
point=${shape}_${suffix}_point
junction=${shape}_${suffix}_junction

echo "Creating dump table ${dump}"
if [[ ! -n "${where}" ]]; then
    where="TRUE"
fi
psql ${database} ${user} \
    --command="DROP TABLE IF EXISTS ${dump}" \
    --command="CREATE TABLE ${dump} AS
                  SELECT ${shapeid} AS id, (ST_Dump(${geometry})).geom AS geometry FROM ${shape} WHERE ${where}"

echo "Creating polygon table ${poly}"
psql ${database} ${user} \
    --quiet \
    --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${poly} CASCADE" \
    --command="CREATE TABLE ${poly} (id SERIAL PRIMARY KEY, ${geometry} geometry(Polygon, 4326));"
psql ${database} ${user} \
    --quiet --tuples-only --no-align \
    --command="\timing off" \
    --command="SELECT ST_ExteriorRing((ST_DumpRings(geometry)).geom) FROM ${dump}" | \
jtsop.sh -a stdin -b "POLYGON (EMPTY)" -f wkb -explode OverlayNG.union 100000000 | \
jtsop.sh -a stdin -f wkb -explode Polygonize.polygonize | \
psql ${database} ${user} \
    --quiet \
    --command="\timing off" \
    --command="\copy ${poly} (${geometry}) FROM stdin"

echo "Creating point in polygon table ${point}"
psql ${database} ${user} \
    --quiet \
    --command="DROP TABLE IF EXISTS ${point}" \
    --command="CREATE TABLE ${point} (id INTEGER, point geometry(Point, 4326))" \
    --command="INSERT INTO ${point}
                SELECT id, ST_PointOnSurface(${geometry}) AS point
                FROM ${poly}"

echo "Creating junction table ${junction}"
psql ${database} ${user} \
    --quiet \
    --command="DROP TABLE IF EXISTS ${junction}" CASCADE \
    --command="CREATE TABLE ${junction} (poly_id INTEGER, shape_id INTEGER)" \
    --command="INSERT INTO ${junction}  (poly_id, shape_id)
                SELECT poly.id, dump.id
                FROM ${point} poly
                  JOIN ${dump} dump
                  ON ST_Contains(dump.geometry, poly.point)
                GROUP BY poly.id, dump.id"

echo "Dropping point in polygon table ${point}"
psql ${database} ${user} \
    --quiet \
    --command="DROP TABLE IF EXISTS ${point}"

if [[ "${leavedump}" != "true" ]]; then
    echo "Dropping shape dump table ${dump}"
    psql ${database} ${user} \
        --quiet \
        --command="DROP TABLE IF EXISTS ${dump}"
fi
