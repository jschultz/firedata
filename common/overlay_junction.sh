#!/bin/bash
#
# Copyright 2025 Jonathan Schultz
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
  "-g:--geometry::geom:Semicolon-delimited name(s) of geometry column(s) in event tables"
  "-b:--basename:::Table name base for output dump, polygon, point-in-polygon and junction output tables. Default is first event table name"
  "-j:--junction:::Semicolon-delimited junction table names. Default is 'eventtable'_junction"
  "-S:--suffix:::Suffix to append to first event table name to generate dump, polygon, point-in-polygon and junction table names"
  "-w:--where:::WHERE clause(s) for selecting from event table(s). Consider using 'area' or 'exclude' if simpler:"
  "-a:--area:::Area to constrain junction calculation"
  "-e:--exclude:::Area to exclude from junction calculation"
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

table_exists() {
    psql --variable=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
    --command "\timing off" \
    --command "SELECT table_exists('$1')::int"
}

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    canonical_array[tableidx]=$(psql --variable=ON_ERROR_STOP=1 \
        --quiet --tuples-only --no-align --command="\timing off" \
        --command="SELECT canonical_table('${eventtable_array[tableidx]}')")
    if [[ ! -n "${canonical_array[tableidx]}" ]]; then
        canonical_array[tableidx]="${eventtable_array[tableidx]}"
    fi
done

if [[ ! -n "${basename}" ]]; then
    basename=${canonical_array[0]##*.}
fi

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${basename}_${suffix}.log"
    fi
    echo "${COMMENTS}" > ${logfile}
fi

TEMPSCHEMA=temp
CALCSCHEMA=calc

polytable=${CALCSCHEMA}.${basename}_${suffix}_poly
pointtable=${TEMPSCHEMA}.${basename}_${suffix}_point

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    dumptable[tableidx]=${TEMPSCHEMA}.${canonical_array[tableidx]##*.}_${suffix}_dump
    if [[ ! -n "${eventid_array[tableidx]}" ]]; then
        eventid_array[tableidx]="id"
    fi
    if [[ ! -n "${geometry_array[tableidx]}" ]]; then
        geometry_array[tableidx]="geom"
    fi
    if [[ ! -n "${junction_array[tableidx]}" ]]; then
        junction_array[tableidx]="${basename}_${suffix}_${eventtable_array[tableidx]}_junction"
    fi

done

force=false

echo "Testing SRIDs" >> /dev/stderr

SRID=$(psql --variable=ON_ERROR_STOP=1 \
            --quiet --tuples-only --no-align --command="\timing off" \
            --command "SELECT ST_SRID(${geometry_array[0]}) AS srid FROM ${eventtable_array[0]} LIMIT 1" )

if [[ $SRID -eq 0 ]]; then
    echo "ERROR: Missing SRID in shape table geometries" >> /dev/stderr
    exit 1
fi

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    MULTIPLE_SRID=$(psql --variable=ON_ERROR_STOP=1 \
                --quiet --tuples-only --no-align --command="\timing off" \
                --command "SELECT EXISTS(
                            SELECT ST_SRID(${geometry_array[tableidx]}) AS srid FROM ${canonical_array[tableidx]} WHERE ST_SRID(${geometry_array[tableidx]}) != '${SRID}')" )
    if [[ "$MULTIPLE_SRID" == "t" ]]; then
        echo "ERROR: Multiple SRIDs in shape table geometries" >> /dev/stderr
        exit 1
    fi
done

if [[ "${merge}" == "true" ]]; then
    mergetable=${TEMPSCHEMA}.${basename}_${suffix}_merge
    outtable=${mergetable}
else
    outtable=${polytable}
fi

if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${outtable}") == 1 ]]; then
    echo "Table ${outtable} exists - skipping" >> /dev/stderr
else

    for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
        if [[ "${existing}" == "true" && $(table_exists "${dumptable[tableidx]}") == 1 ]]; then
            echo "Dump table ${dumptable[tableidx]} exists - skipping" >> /dev/stderr
            continue
        else
            force=true
            echo "Creating dump table ${dumptable[tableidx]}" >> /dev/stderr

            if [[ "${nobackup}" != "true" ]]; then
                backupcommand="CALL cycle_table('${dumptable[tableidx]}')"
            else
                backupcommand=
            fi
            DUMP_QUERY=""
            withintro="WITH"
            if [[ -n "${area}" ]]; then
                DUMP_QUERY+="${withintro} area as (${area})"
                withintro=","
            fi
            if [[ -n "${exclude}" ]]; then
                DUMP_QUERY+="${withintro} exclude as (${exclude})"
                withintro=","
            fi
            DUMP_QUERY+="
                SELECT ${eventid_array[tableidx]},
                    (ST_Dump("
            if [[ -n "${area}" ]]; then
                DUMP_QUERY+="ST_Intersection("
            fi
            if [[ -n "${exclude}" ]]; then
                DUMP_QUERY+="ST_Difference("
            fi
            DUMP_QUERY+="event.${geometry_array[tableidx]}"
            if [[ -n "${exclude}" ]]; then
                DUMP_QUERY+=", exclude.geom)"
            fi
            if [[ -n "${area}" ]]; then
                DUMP_QUERY+=", area.geom)"
            fi
            DUMP_QUERY+=")).geom FROM ${canonical_array[tableidx]} AS event"
            if [[ -n "${area}" ]]; then
                DUMP_QUERY+=", area"
            fi
            if [[ -n "${exclude}" ]]; then
                DUMP_QUERY+=", exclude"
            fi
            whereintro="WHERE"
            if [[ -n "${area}" ]]; then
                DUMP_QUERY+=" ${whereintro} ST_Intersects(event.${geometry_array[tableidx]}, area.geom)"
                whereintro="AND"
            fi
            if [[ -n "${exclude}" ]]; then
                DUMP_QUERY+=" ${whereintro} NOT ST_Within(event.${geometry_array[tableidx]}, exclude.geom)"
                whereintro="AND"
            fi
            if [[ -n "${where}" ]]; then
                DUMP_QUERY+=" ${whereintro} ${where}"
                whereintro="AND"
            fi

            if [[ "${debug}" == "true" ]]; then
                echo $DUMP_QUERY >> /dev/stderr
            fi
            psql --variable=ON_ERROR_STOP=1 \
                --command="${backupcommand}" \
                --command="CREATE TABLE ${dumptable[tableidx]} AS ${DUMP_QUERY}" \
                --command "CREATE INDEX ON ${dumptable[tableidx]} USING gist (geom)"
        fi
    done

    force=true
    echo "Creating table ${outtable}" >> /dev/stderr
    if [[ "${existing}" != "true" && "${nobackup}" != "true" ]]; then
        backupcommand="CALL cycle_table('${outtable}')"
    else
        backupcommand=
    fi

    psql --variable=ON_ERROR_STOP=1 \
        --command="${backupcommand}" \
        --command="CREATE TABLE ${outtable} (id SERIAL PRIMARY KEY, geom geometry(Polygon,${SRID}))" \
        --command "CREATE INDEX ON ${outtable} USING gist (geom)"

    dumpcommand="SELECT ST_ExteriorRing((ST_DumpRings(geom)).geom) FROM (
        SELECT geom FROM ${dumptable[0]}"
    for ((tableidx=1; tableidx<${#eventtable_array[@]}; tableidx++)) do
        dumpcommand+=" UNION SELECT geom FROM ${dumptable[tableidx]}"
    done
    dumpcommand+=") foo"

    psql --variable=ON_ERROR_STOP=1 \
        --quiet --tuples-only --no-align --command="\timing off" \
        --command="${dumpcommand}" \
    | \
    time --portability jtsop.sh -a stdin -b "POLYGON (EMPTY)" -f wkb -explode OverlayNG.union 100000000 | \
    time --portability jtsop.sh -a stdin -f wkb -srid ${SRID} -explode Polygonize.polygonize | \
    psql --variable=ON_ERROR_STOP=1 \
        --command="\copy ${outtable} (geom) FROM stdin"
fi

if [[ "${merge}" == "true" ]]; then
    mergepolyjunction=${CALCSCHEMA}.${basename}_${suffix}_merge_poly_junction
    if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${mergepolyjunction}") == 1 ]]; then
        echo "Junction table ${mergepolyjunction} exists - skipping" >> /dev/stderr
    else
        psql --variable=ON_ERROR_STOP=1 \
            --command="\echo Creating junction table ${mergepolyjunction}"
            --command="CREATE TABLE ${mergepolyjunction} AS SELECT merge.id AS merge_id, poly.id AS poly_id FROM ${polytable} AS poly, ${mergetable} AS merge WHERE ST_Intersects(merge.geom, poly.geom)" \
            --command="CREATE INDEX ON ${mergepolyjunction} (merge_id)" \
            --command="CREATE INDEX ON ${mergepolyjunction} (poly_id)"
    fi

    psql --variable=ON_ERROR_STOP=1 \
        --command="\echo Inserting difference between merged and old polygons" \
        --command="
INSERT INTO ${polytable} AS poly (geom)
(SELECT geom
    FROM (SELECT
            (ST_Dump(ST_Difference(merge.geom, ST_Union(poly.geom)))).geom
          FROM ${mergepolyjunction} AS junction, ${polytable} AS poly, ${mergetable} AS merge
          WHERE  poly.id = junction.poly_id
            AND merge.id = junction.merge_id
          GROUP BY merge.geom) AS foo
    WHERE ST_GeometryType(geom) = 'ST_Polygon'::text)" \
        --command="\echo Inserting difference between old and merged polygons" \
        --command="
INSERT INTO ${polytable} AS poly (geom)
(SELECT geom
    FROM (SELECT
            (ST_Dump(ST_Difference(poly.geom, ST_Union(merge.geom)))).geom
          FROM ${mergepolyjunction} AS junction, ${mergetable} AS merge, ${polytable} AS poly
          WHERE merge.id = junction.merge_id
            AND  poly.id = junction.poly_id
          GROUP BY poly.geom) AS foo
    WHERE ST_GeometryType(geom) = 'ST_Polygon'::text)" \
        --command="\echo Inserting intersection between merged and old polygons" \
        --command="
INSERT INTO ${polytable} AS poly (geom)
(SELECT geom
    FROM (SELECT
            (ST_Dump(ST_Intersection(poly.geom, merge.geom))).geom
          FROM ${mergepolyjunction} AS junction, ${polytable} AS poly, ${mergetable} AS merge
          WHERE  poly.id = junction.poly_id
            AND merge.id = junction.merge_id) AS foo
    WHERE ST_GeometryType(geom) = 'ST_Polygon'::text)" \
        --command="\echo Deleting old polygons" \
        --command="
DELETE FROM ${polytable} AS poly
USING (SELECT DISTINCT poly_id
         FROM ${mergepolyjunction} AS junction) foo
WHERE poly.id = poly_id"
fi

if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${pointtable}") == 1 ]]; then
    echo "Point in polygon table ${pointtable} exists - skipping" >> /dev/stderr
else
    echo "Creating point in polygon table ${pointtable}" >> /dev/stderr
    psql --variable=ON_ERROR_STOP=1 \
        --command="DROP TABLE IF EXISTS ${pointtable}" \
        --command="CREATE TABLE ${pointtable} AS
                    SELECT id, ST_PointOnSurface(geom) AS point
                    FROM ${polytable}" \
        --command "CREATE INDEX ON ${pointtable} USING gist (point)"
fi

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    junctiontable=${CALCSCHEMA}.${junction_array[tableidx]}
    if [[ "${force}" != "true" && "${existing}" == "true" && $(table_exists "${junctiontable}") == 1 ]]; then
        echo "Junction table ${junctiontable} exists - skipping" >> /dev/stderr
    else
        echo "Creating junction table ${junctiontable}" >> /dev/stderr
        if [[ "${nobackup}" != "true" ]]; then
            backupcommand="CALL cycle_table('${junctiontable}')"
        else
            backupcommand=
        fi
        if [[ -n "${area}" ]]; then
            junctioncommand="CREATE TABLE ${junctiontable} AS
                                WITH area as (${area})
                                SELECT DISTINCT point.id AS poly_id, event.${eventid_array[tableidx]}
                                FROM area,
                                    ${canonical_array[tableidx]} AS event,
                                    ${pointtable} AS point
                                WHERE ST_Intersects(area.geom, event.${geometry_array[tableidx]})
                                AND   ST_Contains(event.${geometry_array[tableidx]}, point.point)"
        else
            junctioncommand="CREATE TABLE ${junctiontable} AS
                                SELECT DISTINCT point.id AS poly_id, event.${eventid_array[tableidx]}
                                FROM ${canonical_array[tableidx]} AS event,
                                     ${pointtable} AS point
                                WHERE ST_Contains(event.${geometry_array[tableidx]}, point.point)"
        fi
        psql --variable=ON_ERROR_STOP=1 \
            --command="${backupcommand}" \
            --command="${junctioncommand}" \
            --command="CREATE INDEX ON ${junctiontable} (poly_id)" \
            --command="ALTER TABLE ${junctiontable} ADD CONSTRAINT fk_poly FOREIGN KEY (poly_id) REFERENCES ${polytable}(id)" \
            --command="CREATE INDEX ON ${junctiontable} (${eventid_array[tableidx]})" \
            --command="ALTER TABLE ${junctiontable} ADD CONSTRAINT fk_${eventtable_array[tableidx]} FOREIGN KEY (${eventid_array[tableidx]}) REFERENCES ${canonical_array[tableidx]}(${eventid_array[tableidx]})"
    fi
done

if [[ "${keep}" != "true" ]]; then
    echo "Dropping point in polygon table ${pointtable}" >> /dev/stderr
    psql --variable=ON_ERROR_STOP=1 \
        --command="DROP TABLE ${pointtable}"
    for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
        echo "Dropping dump table ${dumptable[tableidx]}" >> /dev/stderr
        psql --variable=ON_ERROR_STOP=1 \
            --command="DROP TABLE IF EXISTS ${dumptable[tableidx]}"
    done
fi
