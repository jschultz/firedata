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
  "-r:--reference:::Normalised reference table name. Default is 'basename'_reference"
  "-S:--suffix:::Suffix to append to first event table name to generate dump, polygon, point-in-polygon and junction table names:deprecated"
  "-g:--geometry::geom:Semicolon-delimited name(s) of geometry column(s) in event tables"
  "-w:--where:::WHERE clause(s) for selecting from event table(s); deprecated in favour of 'area':deprecated"
  "-a:--area:::Area to constrain junction calculation"
  "-m:--merge:::Merge new with existing polygon table:flag"
  "-E:--existing:::Use existing tables where they exist:flag"
  "-K:--keep:::Keep tables for re-use:flag"
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

table_exists() {
    psql --variable=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
    --command="\timing off" \
    --command "SELECT table_exists('$1')::int"
}

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

force=false

echo "Testing SRIDs" >> /dev/stderr

SRID=$(psql --variable=ON_ERROR_STOP=1 \
            --quiet --tuples-only --no-align --command="\timing off" \
            --command "SELECT ST_SRID(${geometry_array[0]}) AS srid FROM ${eventtable_array[0]} LIMIT 1" )
            
if [[ $SRID -eq 0 ]]; then
    echo "ERROR: Missing SRID in shape table geometries" >> /dev/stderr
    return 1
fi

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    MULTIPLE_SRID=$(psql --variable=ON_ERROR_STOP=1 \
                --quiet --tuples-only --no-align --command="\timing off" \
                --command "SELECT EXISTS(
                            SELECT ST_SRID(${geometry_array[tableidx]}) AS srid FROM ${eventtable_array[tableidx]} WHERE ST_SRID(${geometry_array[tableidx]}) != '${SRID}')" )
    if [[ "$MULTIPLE_SRID" == "t" ]]; then
        echo "ERROR: Multiple SRIDs in shape table geometries" >> /dev/stderr
        return 1
    fi
done

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    if [[ "${existing}" == "true" && $(table_exists "${eventtable_array[tableidx]}_dump") == 1 ]]; then
        echo "Dump table ${eventtable_array[tableidx]}_dump exists - skipping"
        continue
    else
        force=true
        echo "Creating dump table ${eventtable_array[tableidx]}_dump"

        if [[ "${nobackup}" != "true" ]]; then  
            backupcommand="CALL cycle_table('${eventtable_array[tableidx]}_dump')"
        else
            backupcommand=
        fi
        if [[ -n "${area}" ]]; then
            dumptable="WITH area as (${area})
                        SELECT ${eventid_array[tableidx]}, (ST_Dump(ST_Intersection(area.geom,event.${geometry_array[tableidx]}))).geom AS geom FROM ${eventtable_array[tableidx]} AS event, area WHERE ST_Intersects(area.geom,event.${geometry_array[tableidx]})"
        elif [[ -n "${where}" ]]; then
            dumptable="SELECT ${eventid_array[tableidx]}, (ST_Dump(${geometry_array[tableidx]})).geom AS geom FROM ${eventtable_array[tableidx]} WHERE ${where}"
        else
            dumptable="SELECT ${eventid_array[tableidx]}, (ST_Dump(geom,event)).geom AS geom FROM ${eventtable_array[tableidx]} AS event"
        fi
        psql --variable=ON_ERROR_STOP=1 \
            --command="${backupcommand}" \
            --command="CREATE TABLE ${eventtable_array[tableidx]}_dump AS ${dumptable}" \
            --command "CREATE INDEX ON ${eventtable_array[tableidx]}_dump USING gist (geom)"
    fi
done

if [[ "${merge}" == "true" ]]; then
    mergetable=${basename}_merge
    outtable=${mergetable}
else
    outtable=${poly}
fi

if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${outtable}") == 1 ]]; then
    echo "Table ${outtable} exists - skipping"
else
    force=true
    echo "Creating table ${outtable}" >> /dev/stderr
    if [[ "${existing}" != "true" && "${nobackup}" != "true" ]]; then  
        backupcommand="CALL cycle_table('${outtable}')"
    else
        backupcommand=
    fi

    psql --variable=ON_ERROR_STOP=1 \
        --command="${backupcommand}" \
        --command="CREATE TABLE ${outtable} (id SERIAL PRIMARY KEY, geom geometry(Polygon))" \
        --command "CREATE INDEX ON ${outtable} USING gist (geom)"
        
    dumpcommand="SELECT ST_ExteriorRing((ST_DumpRings(geom)).geom) FROM (
        SELECT geom FROM ${eventtable_array[0]}_dump"
    for ((tableidx=1; tableidx<${#eventtable_array[@]}; tableidx++)) do
        dumpcommand+=" UNION SELECT geom FROM ${eventtable_array[tableidx]}_dump"
    done
    dumpcommand+=") foo"

    psql --variable=ON_ERROR_STOP=1 \
        --quiet --tuples-only --no-align --command="\timing off" \
        --command="${dumpcommand}" \
    | \
    jtsop.sh -a stdin -b "POLYGON (EMPTY)" -f wkb -explode OverlayNG.union 100000000 | \
    jtsop.sh -a stdin -f wkb -srid ${SRID} -explode Polygonize.polygonize | \
    psql --variable=ON_ERROR_STOP=1 \
        --command="\copy ${outtable} (geom) FROM stdin"
fi

if [[ "${merge}" == "true" ]]; then
    mergepolyjunction=${basename}_merge_poly_junction
    if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${mergepolyjunction}") == 1 ]]; then
        echo "Junction table ${mergepolyjunction} exists - skipping"
    else
        psql --variable=ON_ERROR_STOP=1 \
            --command="\echo Creating junction table ${mergepolyjunction}"
            --command="CREATE TABLE ${mergepolyjunction} AS SELECT merge.id AS merge_id, poly.id AS poly_id FROM ${poly} AS poly, ${mergetable} AS merge WHERE ST_Intersects(merge.geom, poly.geom)" \
            --command="CREATE INDEX ON ${mergepolyjunction} (merge_id)" \
            --command="CREATE INDEX ON ${mergepolyjunction} (poly_id)"
    fi

    psql --variable=ON_ERROR_STOP=1 \
        --command="\echo Inserting difference between merged and old polygons" \
        --command="
INSERT INTO ${poly} AS poly (geom) 
(SELECT geom 
    FROM (SELECT 
            (ST_Dump(ST_Difference(merge.geom, ST_Union(poly.geom)))).geom
          FROM ${mergepolyjunction} AS junction, ${poly} AS poly, ${mergetable} AS merge
          WHERE  poly.id = junction.poly_id
            AND merge.id = junction.merge_id
          GROUP BY merge.geom) AS foo
    WHERE ST_GeometryType(geom) = 'ST_Polygon'::text)" \
        --command="\echo Inserting difference between old and merged polygons" \
        --command="
INSERT INTO ${poly} AS poly (geom) 
(SELECT geom 
    FROM (SELECT 
            (ST_Dump(ST_Difference(poly.geom, ST_Union(merge.geom)))).geom
          FROM ${mergepolyjunction} AS junction, ${mergetable} AS merge, ${poly} AS poly
          WHERE merge.id = junction.merge_id
            AND  poly.id = junction.poly_id
          GROUP BY poly.geom) AS foo
    WHERE ST_GeometryType(geom) = 'ST_Polygon'::text)" \
        --command="\echo Inserting intersection between merged and old polygons" \
        --command="
INSERT INTO ${poly} AS poly (geom) 
(SELECT geom 
    FROM (SELECT 
            (ST_Dump(ST_Intersection(poly.geom, merge.geom))).geom 
          FROM ${mergepolyjunction} AS junction, ${poly} AS poly, ${mergetable} AS merge 
          WHERE  poly.id = junction.poly_id
            AND merge.id = junction.merge_id) AS foo 
    WHERE ST_GeometryType(geom) = 'ST_Polygon'::text)" \
        --command="\echo Deleting old polygons" \
        --command="
DELETE FROM ${poly} AS poly 
USING (SELECT DISTINCT poly_id 
         FROM ${mergepolyjunction} AS junction) foo 
WHERE poly.id = poly_id"
fi

if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${point}") == 1 ]]; then
    echo "Point in polygon table ${point} exists - skipping"
else
    echo "Creating point in polygon table ${point}" >> /dev/stderr
    psql --variable=ON_ERROR_STOP=1 \
        --command="DROP TABLE IF EXISTS ${point}" \
        --command="CREATE TABLE ${point} AS 
                    SELECT id, ST_PointOnSurface(geom) AS point
                    FROM ${poly}" \
        --command "CREATE INDEX ON ${point} USING gist (point)"
fi

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${junction_array[tableidx]}") == 1 ]]; then
        echo "Junction table ${junction_array[tableidx]} exists - skipping"
        continue
    else
        echo "Creating junction table ${junction_array[tableidx]}" >> /dev/stderr
        if [[ "${nobackup}" != "true" ]]; then  
            backupcommand="CALL cycle_table('${junction_array[tableidx]}')"
        else
            backupcommand=
        fi
        psql --variable=ON_ERROR_STOP=1 \
            --command="${backupcommand}" \
            --command="CREATE TABLE ${junction_array[tableidx]} AS 
                        SELECT point.id AS poly_id, dump.${eventid_array[tableidx]}
                        FROM ${eventtable_array[tableidx]}_dump AS dump
                            JOIN ${point} AS point
                            ON ST_Contains(dump.geom, point.point)
                        GROUP BY point.id, dump.${eventid_array[tableidx]}" \
            --command="CREATE INDEX ON ${junction_array[tableidx]} (poly_id)" \
            --command="ALTER TABLE ${junction_array[tableidx]} ADD CONSTRAINT fk_poly FOREIGN KEY (poly_id) REFERENCES ${poly}(id)" \
            --command="CREATE INDEX ON ${junction_array[tableidx]} (${eventid_array[tableidx]})" \
            --command="ALTER TABLE ${junction_array[tableidx]} ADD CONSTRAINT fk_${eventtable_array[tableidx]} FOREIGN KEY (${eventid_array[tableidx]}) REFERENCES ${eventtable_array[tableidx]}(${eventid_array[tableidx]})"
    fi
done

# if [[ ! -n "${reference}" ]]; then
#     reference="${basename}_reference"
# fi
# if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${reference}") == 1 ]]; then
#     echo "Table ${reference} exists - skipping"
# else
#     force=true
#     echo "Creating reference table ${reference}" >> /dev/stderr
#     if [[ "${existing}" != "true" && "${nobackup}" != "true" ]]; then  
#         backupcommand="CALL cycle_table('${reference}')"
#     else
#         backupcommand=
#     fi
# 
#     createreference="CREATE TABLE ${reference} AS SELECT poly.id"
#     for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
#         createreference+=", ${junction_array[tableidx]}.${eventid_array[tableidx]} AS ${eventtable_array[tableidx]}_${eventid_array[tableidx]}"
#     done
#     createreference+=" FROM ${poly} AS poly"
#     for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
#         createreference+=" LEFT JOIN ${junction_array[tableidx]} ON ${junction_array[tableidx]}.poly_id = poly.id"
#     done
# 
#     psql --variable=ON_ERROR_STOP=1 \
#         --command="${backupcommand}" \
#         --command="${createreference}"
# fi

if [[ "${keep}" != "true" ]]; then  
    echo "Dropping point in polygon table ${point}" >> /dev/stderr
    psql --variable=ON_ERROR_STOP=1 \
        --command="DROP TABLE ${point}"
    for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
        echo "Dropping dump table ${eventtable_array[tableidx]}_dump" >> /dev/stderr
        psql --variable=ON_ERROR_STOP=1 \
            --command="DROP TABLE ${eventtable_array[tableidx]}_dump"
    done
fi
