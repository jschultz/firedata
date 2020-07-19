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

help='Create an overlay of non-intersecting polygons from a collection of possibly overlapping shapes, represented as a view linking those polygons back to the original shapes.'
args=(
# "-short:--long:variable:default:required"
  "-u:--user:::true:PostgreSQL username"
  "-d:--database:::true:PostgreSQL database"
  "-s:--shape:::false:Table name containing geometrical data"
  "-S:--suffix:::true:Suffix to append to shape table name to generate other table names"
  "-g:--geometry::geometry:false:Column name for geometry in 'shape' table"
  "-w:--where::TRUE:false:WHERE clause for selecting from 'shape' table"
  "-c:--columns::id:false:Comma separated list of columns to retrieve from linked shape data"
  "-n:--number:::false:Number of links to copy to view; default is minimum required"
)

######################## START OF ARGUMENT PARSING CODE ########################

argshort=()
arglong=()
argvar=()
argdefault=()
argrequired=()
argdesc=()

argn=${#args[@]}
for ((argidx=0; argidx<argn; argidx++)) do
    argstring=${args[argidx]}
    IFS=':' read -r -a arg <<< "${argstring}"
    argshort+=("${arg[0]}")
    arglong+=("${arg[1]}")
    if [[ -n "${arg[2]}" ]]; then 
        argvar+=("${arg[2]}")
    else
        var=${arg[1]}
        if [[ "${var:0:2}" == "--" ]]; then
            argvar+=("${var:2}")
        else
            argvar+=("${var}")
        fi
    fi
    argdefault+=("${arg[3]}")
    argrequired+=("${arg[4]}")
    argdesc+=("${arg[5]}")
done
while (( "$#" )); do
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo ${help} | fold --width=$(tput cols) --spaces
        echo "    -h, --help - Display this usage information" | fold --width=$(tput cols) --spaces
        for ((argidx=0; argidx<argn; argidx++)) do
            LINE="    "
            if [[ -n "${argshort[argidx]}" ]]; then
                LINE+="${argshort[argidx]}"
            fi
            if [[ -n "${arglong[argidx]}" ]]; then
                if [[ -n "${argshort[argidx]}" ]]; then
                    LINE+=", "
                fi
                LINE+="${arglong[argidx]}"
            fi
            if [[ -n "${argdefault[argidx]}" ]]; then
                LINE+=" (default: ${argdefault[argidx]})"
            fi
            if [[ "${argrequired[argidx]}" == "true" ]]; then
                LINE+=" (required)"
            fi
            if [[ -n "${argdesc[argidx]}" ]]; then
                LINE+=" - ${argdesc[argidx]}"
            fi
            echo "$LINE" | fold --width=$(tput cols) --spaces
        done
        exit 0
    fi
    
    for ((argidx=0; argidx<argn; argidx++)) do
        if [[ -n ${argshort[argidx]} ]]; then
            if [[ "$1" == "${argshort[argidx]}" || "$1" == "${arglong[argidx]}" ]]; then
                if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                    eval "${argvar[argidx]}=\"$2\""
                    shift 2
                else
                    echo "Error: Value for '${arglong[argidx]}' is missing" >&2
                    exit 1
                fi
                break
            fi
        # Positional argument
        elif [[ "${1:0:1}" != "-" && ! -n "${!argvar[argidx]}" ]]; then
            eval "${argvar[argidx]}=\"$1\""
            shift
            break
        fi
    done
    if [[ ${argidx} == ${argn} ]]; then
        echo "Error: Unrecognised argument: $1" >&2
        exit 1
    fi
done

for ((argidx=0; argidx<argn; argidx++)) do
    if [[ ! -n "${!argvar[argidx]}" ]]; then
        if [[ -n "${argdefault[argidx]}" ]]; then
            eval "${argvar[argidx]}=\"${argdefault[argidx]}\""
        elif [[ "${argrequired[argidx]}" == "true" ]]; then
            echo "Missing argument '${arglong[argidx]}'" >&2
            exit 1
        fi
    fi
done

######################### END OF ARGUMENT PARSING CODE #########################

dump=${shape}_${suffix}_dump
poly=${shape}_${suffix}_poly
point=${shape}_${suffix}_point
junction=${shape}_${suffix}_junction
denorm=${shape}_${suffix}_denorm
view=${shape}_${suffix}_view

echo "Creating dump table ${dump}"
psql ${database} ${user} \
    --quiet --tuples-only --no-align \
    --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${dump}" \
    --command="CREATE TABLE ${dump} AS
                  SELECT id, (ST_Dump(${geometry})).geom AS geometry FROM ${shape} WHERE ${where}"

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
    --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${point}" \
    --command="CREATE TABLE ${point} (id INTEGER, point geometry(Point, 4326))" \
    --command="INSERT INTO ${point}
                SELECT id, ST_PointOnSurface(${geometry}) AS point
                FROM ${poly}"

echo "Creating junction table ${junction}"
psql ${database} ${user} \
    --quiet \
    --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${junction}" \
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
    --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${point}"

echo "Dropping shape dump table ${dump}"
psql ${database} ${user} \
    --quiet --tuples-only --no-align \
    --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${dump}"

echo "Creating denormalised table ${denorm}"
if [[ ! -n "${number}" ]]; then
    number=$(psql ${database} ${user} \
                --quiet --tuples-only --no-align \
                --command="\timing off" \
                --command="SELECT max(count)
                          FROM (SELECT poly_id, count(shape_id) AS count 
                                FROM ${junction}
                                GROUP BY poly_id) AS foo")
fi
echo "Number of links to copy is ${number}"

# CREATE TABLE <denorm> (poly_id INTEGER REFERENCES <poly>(id), shape_count INTEGER shape_id_1 INTEGER REFERENCES <shape>(id) ...)
CREATE_TABLE_SQL="CREATE TABLE ${denorm} (poly_id INTEGER REFERENCES ${poly}(id), shape_count INTEGER"
for ((linkidx=1; linkidx<=${number}; linkidx++)) do
    CREATE_TABLE_SQL+=", shape_id_${linkidx} INTEGER REFERENCES ${shape}(id)"
done
CREATE_TABLE_SQL+=")"

# UPDATE <denorm> AS denorm SET shape_count = array_length(agg.shape_ids, 1), shape_id_1 = agg.shape_idx[1] ...
UPDATE_TABLE_SQL="UPDATE ${denorm} AS denorm SET shape_count = array_length(agg.shape_ids, 1)"
for ((linkidx=1; linkidx<=${number}; linkidx++)) do
    UPDATE_TABLE_SQL+=", shape_id_${linkidx} = agg.shape_ids[${linkidx}]"
done
UPDATE_TABLE_SQL+="FROM (SELECT poly_id, array_agg(shape_id) as shape_ids
                     FROM ${junction} AS junction
                     JOIN ${shape} AS shape ON shape.id = shape_id
                     GROUP BY poly_id) agg
                   WHERE agg.poly_id = denorm.poly_id"

psql ${database} ${user} \
    --quiet \
    --command="$CREATE_TABLE_SQL" \
    --command="INSERT INTO ${denorm} (poly_id) 
               SELECT DISTINCT poly_id FROM ${junction}" \
    --command="$UPDATE_TABLE_SQL"

echo "Dropping junction table ${junction}"
psql ${database} ${user} \
    --quiet --tuples-only --no-align \
    --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${junction}"

echo "Creating view ${view}"
# CREATE VIEW <view> AS SELECT poly_id AS id, poly.geometry AS poly_geometry, shape_count AS fire_count, shape1.col1 AS <column>_1, ...
CREATE_VIEW_SQL="CREATE VIEW ${view} AS SELECT poly_id AS id, poly.geometry AS poly_geometry, shape_count AS fire_count"
IFS=',' read -r -a columnarray <<< "${columns}"
for ((linkidx=1; linkidx<=${number}; linkidx++)) do
    for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
        CREATE_VIEW_SQL+=", shape${linkidx}.${columnarray[colidx]} AS ${columnarray[colidx]}_${linkidx}"
    done
done
CREATE_VIEW_SQL+=" FROM ${denorm}
    JOIN ${poly} AS poly ON poly.id = poly_id"
for ((linkidx=1; linkidx<=${number}; linkidx++)) do
    CREATE_VIEW_SQL+=" LEFT JOIN ${shape} as shape${linkidx} ON shape${linkidx}.id = shape_id_${linkidx}"
done

psql ${database} ${user} \
    --quiet \
    --command="DROP VIEW IF EXISTS ${view}" \
    --command="$CREATE_VIEW_SQL"
