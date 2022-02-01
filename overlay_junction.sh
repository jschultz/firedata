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

help='Creates an overlay of non-intersecting polygons from a collection of shapes in an event table. Produces a polygon table and a junction table between the polygon and original event tables.'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-e:--eventtable:::Name of database table containing event data"
  ":--eventid::id:Id column in event table"
  "-S:--suffix:::Suffix to append to event table name to generate dump, polygon, point-in-polygon and junction table names":"required"
  "-g:--geometry::geom:Name of geometry column in tables"
  "-w:--where:::WHERE clause for selecting from event table"
  "-l:--logfile:::Log file to record processing, defaults to 'event' + 'suffix' + .log"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--keepdump:::Keep intermediate dump table:flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${eventtable}_${suffix}_${sequence}.log"
    fi
    echo "${COMMENTS}" > ${logfile}
fi

if [[ "${debug}" == "true" ]]; then
    set -x
fi

dump=${eventtable}_${suffix}_dump
poly=${eventtable}_${suffix}_poly
point=${eventtable}_${suffix}_point
junction=${eventtable}_${suffix}_junction

SRID_COUNT=$(psql ${database} ${user} \
              --quiet --tuples-only --no-align \
              --command="\timing off" \
              --command "SELECT count(DISTINCT srid) FROM
                            (SELECT ST_SRID(${geometry}) AS srid FROM ${eventtable} ) AS foo" )
if [[ $SRID_COUNT -gt 1 ]]; then
    echo "ERROR: Multiple SRIDs in shape table geometries"
    return 1
else
    SRID=$(psql ${database} ${user} \
              --quiet --tuples-only --no-align \
              --command="\timing off" \
              --command "SELECT srid FROM
                            (SELECT ST_SRID(${geometry}) AS srid FROM ${eventtable} ) AS foo
                            LIMIT 1" )
    if [[ $SRID -eq 0 ]]; then
        echo "ERROR: No SRID in shape table geometries"
        return 1
    fi
fi
        
echo "Creating dump table ${dump}"
if [[ ! -n "${where}" ]]; then
    where="TRUE"
fi
psql ${database} ${user} \
    --command="DROP TABLE IF EXISTS ${dump}" \
    --command="CREATE TABLE ${dump} AS
                  SELECT ${eventid} AS id, (ST_Dump(${geometry})).geom AS ${geometry} FROM ${eventtable} WHERE ${where}"

echo "Creating polygon table ${poly}"
psql ${database} ${user} \
    --quiet \
    --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${poly} CASCADE" \
    --command="CREATE TABLE ${poly} (id SERIAL PRIMARY KEY, ${geometry} geometry(Polygon));"
psql ${database} ${user} \
    --quiet --tuples-only --no-align \
    --command="\timing off" \
    --command="SELECT ST_ExteriorRing((ST_DumpRings(${geometry})).geom) FROM ${dump}" | \
jtsop.sh -a stdin -b "POLYGON (EMPTY)" -f wkb -explode OverlayNG.union 100000000 | \
jtsop.sh -a stdin -f wkb -srid ${SRID} -explode Polygonize.polygonize | \
psql ${database} ${user} \
    --quiet \
    --command="\timing off" \
    --command="\copy ${poly} (${geometry}) FROM stdin"

echo "Creating point in polygon table ${point}"
psql ${database} ${user} \
    --quiet \
    --command="DROP TABLE IF EXISTS ${point}" \
    --command="CREATE TABLE ${point} (id INTEGER, point geometry(Point))" \
    --command="INSERT INTO ${point}
                SELECT id, ST_PointOnSurface(${geometry}) AS point
                FROM ${poly}"

echo "Creating junction table ${junction}"
psql ${database} ${user} \
    --quiet \
    --command="DROP TABLE IF EXISTS ${junction}" CASCADE \
    --command="CREATE TABLE ${junction} (poly_id INTEGER, event_id INTEGER)" \
    --command="INSERT INTO ${junction}  (poly_id, event_id)
                SELECT poly.id, dump.id
                FROM ${dump} dump
                  JOIN ${point} poly
                  ON ST_Contains(dump.${geometry}, poly.point)
                GROUP BY poly.id, dump.id"

echo "Dropping point in polygon table ${point}"
psql ${database} ${user} \
    --quiet \
    --command="DROP TABLE IF EXISTS ${point}"

if [[ "${keepdump}" != "true" ]]; then
    echo "Dropping shape dump table ${dump}"
    psql ${database} ${user} \
        --quiet \
        --command="DROP TABLE IF EXISTS ${dump}"
fi
