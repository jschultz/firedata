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

help='Creates an overlay of non-intersecting polygons from a collection of shapes in an event table. Produces a polygon table and a junction table between the polygon and original event tables.'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  "-e:--eventtable:::Semicolon-delimited name(s) of database table(s) containing event data":required
  ":--eventid:::Semicolon-delimited Id column(s) in event table(s). Default is 'id'"
  "-b:--basename:::Table name base for output dump, polygon, point-in-polygon and junction output tables. Default is first event table name"
  "-j:--junction:::Semicolon-delimited junction table names. Default is 'eventtable'_junction"
  "-S:--suffix:::Suffix to append to first event table name to generate dump, polygon, point-in-polygon and junction table names:deprecated"
  "-g:--geometry::geom:Semicolon-delimited name(s) of geometry column(s) in event tables"
  "-w:--where:::WHERE clause(s) for selecting from event table(s)"
  "--E:--existing:::Use existing dump and polygon tables:flag"
  "-l:--logfile:::Log file to record processing, defaults to 'basename' + .log"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--nobackup:::Don't back up existing database tables:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${debug}" == "true" ]]; then
    set -x
fi

IFS=';' read -r -a eventtable_array <<< "${eventtable}"
IFS=';' read -r -a eventid_array    <<< "${eventid}"
IFS=';' read -r -a geometry_array   <<< "${geometry}"
IFS=';' read -r -a junction_array   <<< "${junction}"

if [[ ! -n "${basename}" ]]; then
    basename=${eventtable_array[0]}
    if [[ ! -n "${suffix}" ]]; then
        basename=${basename}_${suffix}
    fi
fi

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${basename}.log"
    fi
    echo "${COMMENTS}" > ${logfile}
fi

poly=${basename}_poly
point=${basename}_point

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    if [[ ! -n "${eventid_array[tableidx]}" ]]; then
        eventid_array[tableidx]="id"
    fi
    if [[ ! -n "${geometry_array[tableidx]}" ]]; then
        geometry_array[tableidx]="geom"
    fi
    if [[ ! -n "${junction_array[tableidx]}" ]]; then
        junction_array[tableidx]="${basename}_${eventtable_array[tableidx]}_junction"
    fi
done

if [[ "${existing}" != "true" ]]; then

    echo "Testing SRIDs" > /dev/stderr

    SRID=$(psql \
                --quiet --tuples-only --no-align --command="\timing off" \
                --command "SELECT ST_SRID(${geometry_array[0]}) AS srid FROM ${eventtable_array[0]} LIMIT 1" )
                
    if [[ $SRID -eq 0 ]]; then
        echo "ERROR: Missing SRID in shape table geometries" > /dev/stderr
        return 1
    fi

    for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
        MULTIPLE_SRID=$(psql \
                    --quiet --tuples-only --no-align --command="\timing off" \
                    --command "SELECT EXISTS(
                                SELECT ST_SRID(${geometry_array[tableidx]}) AS srid FROM ${eventtable_array[tableidx]} WHERE ST_SRID(${geometry_array[tableidx]}) != '${SRID}')" )
        if [[ "$MULTIPLE_SRID" == "t" ]]; then
            echo "ERROR: Multiple SRIDs in shape table geometries" > /dev/stderr
            return 1
        fi
    done
            
    for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
        echo "Creating dump table ${eventtable_array[tableidx]}_dump"
        if [[ ! -n "${where}" ]]; then
            where="True"
        fi
        if [[ "${nobackup}" != "true" ]]; then  
            backupcommand="CALL cycle_table('${eventtable_array[tableidx]}_dump')"
        else
            backupcommand=
        fi
        psql \
            --quiet --tuples-only --no-align --command="\timing off" \
            --command="${backupcommand}" \
            --command="CREATE TABLE ${eventtable_array[tableidx]}_dump AS
                        SELECT ${eventid_array[tableidx]}, (ST_Dump(${geometry_array[tableidx]})).geom AS geom FROM ${eventtable_array[tableidx]} WHERE ${where}" \
        --command "CREATE INDEX ON ${eventtable_array[tableidx]}_dump USING gist (geom)" \
        --command "ANALYZE ${eventtable_array[tableidx]}_dump"
    done

    echo "Creating polygon table ${poly}" > /dev/stderr
    if [[ "${nobackup}" != "true" ]]; then  
        backupcommand="CALL cycle_table('${poly}')"
    else
        backupcommand=
    fi

    psql \
        --quiet --tuples-only --no-align --command="\timing off" \
        --command="${backupcommand}" \
        --command="CREATE TABLE ${poly} (id SERIAL PRIMARY KEY, ${geometry} geometry(Polygon));"
        
    dumpcommand="SELECT ST_ExteriorRing((ST_DumpRings(geom)).geom) FROM (
        SELECT geom FROM ${eventtable_array[0]}_dump"
    for ((tableidx=1; tableidx<${#eventtable_array[@]}; tableidx++)) do
        dumpcommand+=" UNION SELECT geom FROM ${eventtable_array[0]}_dump"
    done
    dumpcommand+=") foo"

    psql \
        --quiet --tuples-only --no-align --command="\timing off" \
        --command="${dumpcommand}" \
    | \
    jtsop.sh -a stdin -b "POLYGON (EMPTY)" -f wkb -explode OverlayNG.union 100000000 | \
    jtsop.sh -a stdin -f wkb -srid ${SRID} -explode Polygonize.polygonize | \
    psql \
        --quiet --tuples-only --no-align --command="\timing off" \
        --command="\timing off" \
        --command="\copy ${poly} (${geometry}) FROM stdin" \
        --command "CREATE INDEX ON ${poly} USING gist (${geometry})" \
        --command "ANALYZE ${poly}"

fi

echo "Creating point in polygon table ${point}" > /dev/stderr
psql \
    --quiet --tuples-only --no-align --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${point}" \
    --command="CREATE TABLE ${point} AS 
                   SELECT id, ST_PointOnSurface(${geometry}) AS point
                   FROM ${poly}" \
    --command "CREATE INDEX ON ${point} USING gist (point)" \
    --command "ANALYZE ${point}"

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    echo "Creating junction table ${junction_array[tableidx]}" > /dev/stderr
    if [[ "${nobackup}" != "true" ]]; then  
        backupcommand="CALL cycle_table('${junction_array[tableidx]}')"
    else
        backupcommand=
    fi
    psql \
        --quiet --tuples-only --no-align --command="\timing off" \
        --command="${backupcommand}" \
        --command="CREATE TABLE ${junction_array[tableidx]} AS 
                    SELECT point.id AS poly_id, dump.${eventid_array[tableidx]}
                    FROM ${eventtable_array[tableidx]}_dump AS dump
                        JOIN ${point} AS point
                        ON ST_Contains(dump.geom, point.point)
                    GROUP BY point.id, dump.id" \
        --command="CREATE INDEX ON ${junction_array[tableidx]} (poly_id)" \
        --command="ALTER TABLE ${junction_array[tableidx]} ADD CONSTRAINT fk_poly FOREIGN KEY (poly_id) REFERENCES ${poly}(id)" \
        --command="CREATE INDEX ON ${junction_array[tableidx]} (${eventid_array[tableidx]})" \
        --command="ALTER TABLE ${junction_array[tableidx]} ADD CONSTRAINT fk_${eventtable_array[tableidx]} FOREIGN KEY (${eventid_array[tableidx]}) REFERENCES ${eventtable_array[tableidx]}(${eventid_array[tableidx]})" \
        --command "ANALYZE ${junction_array[tableidx]}"
done

echo "Dropping point in polygon table ${point}" > /dev/stderr
psql \
    --quiet --tuples-only --no-align --command="\timing off" \
    --command="DROP TABLE IF EXISTS ${point}"