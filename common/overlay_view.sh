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

help='Produces a table or shapefile containing polygon columns and a selection of event columns. Requires event, polygon and junction tables. The last two can be generated from an event table by overlay_junction.sh'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  ":--verbosity::1:Verbosity level"
  "-e:--eventtable:::Semicolon-delimited name(s) of database table(s) containing event data":required
  "-b:--basename:::Table name base for output dump, polygon, point-in-polygon and junction output tables. Default is first event table name"
  "-j:--junction:::Semicolon-delimited junction table names. Default is 'eventtable'_junction"
  "-S:--suffix:::Suffix to append to first event table name to generate dump, polygon, point-in-polygon and junction table names"
  ":--eventid:::Semicolon-delimited Id column(s) in event table(s). Default is 'id'"
  ":--eventorder:::Semicolon-delimited list of sort order for event table(s)"
  ":--eventfilter:::WHERE clause for selecting from event table(s)"
  ":--eventlimit:::Semicolon-delimited list of maximum number of events to retrieve from event table(s); empty means unlimited"
  "-c:--eventcolumns:::Semicolon-delimited list of fully specified columns (table and column name) to retrieve from event table(s)"
  ":--eventaliases:::Semicolon-delimited list of aliases for columns retrieved from event table(s); empty value means use column name as alias"
  ":--flatten:::Output event columns as separate columns instead of arrays:flag"
  ":--polyfilter:::WHERE clause for selecting from polygon table"
  ":--polycolumns:::Semicolon-delimited list of columns to retrieve from polygon table"
  ":--polyaliases:::Semicolon-delimited list of aliases for columns retrieved from polygon table"
  ":--calccolumns:::Semicolon-delimited list of columns to calculate"
  ":--calcaliases:::Semicolon-delimited list of aliases for calculated columns"
  ":--indexes:::Semicolon-delimited list of indexes to create on view table"
  ":--using:::Semicolon-delimited list of index methods"
  "-a:--append:::Append output to existing view table:flag"
  "-v:--viewtable:::Table to generate, defaults to \$eventtable + \$suffix + '_view'"
  "-S:--viewfile:::Shapefile to generate:output"
  "-l:--logfile:::Log file to record processing, defaults to \$viewtable or \$viewfile with extension replaced by '.log', or \$eventtable + \$suffix' + '.log' if neither \$viewtable nor \$viewfile is defined:private"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--nocomments:::Don't add comments to table:private,flag"
  ":--nobackup:::Don't back up existing database table:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${debug}" == "true" ]]; then
    set -x
fi

IFS=';' read -r -a eventtable_array  <<< "${eventtable}"
IFS=';' read -r -a eventid_array     <<< "${eventid}"
IFS=';' read -r -a eventorder_array  <<< "${eventorder}"
IFS=';' read -r -a eventfilter_array <<< "${eventfilter}"
IFS=';' read -r -a eventlimit_array  <<< "${eventlimit}"
IFS=';' read -r -a junction_array    <<< "${junction}"
IFS=';' read -r -a polycolumn_array  <<< "${polycolumns}"
IFS=';' read -r -a polyalias_array   <<< "${polyaliases}"
IFS=';' read -r -a calccolumn_array  <<< "${calccolumns}"
IFS=';' read -r -a calcalias_array   <<< "${calcaliases}"
IFS=';' read -r -a eventcolumn_array <<< "${eventcolumns}"
IFS=';' read -r -a eventalias_array  <<< "${eventaliases}"
IFS=';' read -r -a index_array       <<< "${indexes}"
IFS=';' read -r -a using_array       <<< "${using}"

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    canonical_array[tableidx]=$(psql --variable=ON_ERROR_STOP=1 \
        --quiet --tuples-only --no-align --command="\timing off" \
        --command="SELECT canonical_table('${eventtable_array[tableidx]}')")
    if [[ ! -n "${canonical_array[tableidx]}" ]]; then
        canonical_array[tableidx]="${eventtable_array[tableidx]}"
    fi
done

if [[ ! -n "${basename}" ]]; then
    basename=${canonical_array[0]}
fi

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        if [[ -n "${viewfile}" ]]; then
            logfile=$(basename "${viewfile}")
            logfile="${logfile%.*}.log"
        else
            logfile="${viewtable}.log"
        fi
    fi
    if [[ -r "${logfile}" ]]; then
        INCOMMENTS="$(< "${logfile}")"
    else
        INCOMMENTS=""
    fi
    echo "${COMMENTS}${INCOMMENTS}" > "${logfile}"
fi

for ((colidx=0; colidx<${#polycolumn_array[@]}; colidx++)) do
    if [[ ! -n "${polyalias_array[colidx]}" ]]; then
        polyalias_array[colidx]="${polycolumn_array[colidx]}"
    fi
done

for ((colidx=0; colidx<${#calccolumn_array[@]}; colidx++)) do
    if [[ ! -n "${calcalias_array[colidx]}" ]]; then
        calcalias_array[colidx]="${calccolumn_array[colidx]}"
    fi
done

if [[ "${append}" == "true" && -n "${viewfile}" ]]; then
    echo "'append' option cannot be used when producing a shapefile" > /dev/stderr
    exit 1
fi

TEMPSCHEMA=temp
polytable=${TEMPSCHEMA}.${basename}_${suffix}_poly

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    if [[ ! -n "${eventid_array[tableidx]}" ]]; then
        eventid_array[tableidx]="id"
    fi
    if [[ ! -n "${junction_array[tableidx]}" ]]; then
        junction_array[tableidx]="${basename}_${suffix}_${eventtable_array[tableidx]}_junction"
    fi
done

if [[ ! -n "${viewtable}" ]]; then
    viewtable=${basename}_${suffix}_view
fi

for ((colidx=0; colidx<${#eventcolumn_array[@]}; colidx++)) do
    if [[ "${eventcolumn_array[colidx]%.*}" == "${eventcolumn_array[colidx]}" ]]; then
        eventcolumncorrelation_array[colidx]=""
    else
        eventcolumncorrelation_array[colidx]="${eventcolumn_array[colidx]%.*}"
    fi
    eventcolumnname_array[colidx]="${eventcolumn_array[colidx]#*.}"
    if [[ ! -n "${eventalias_array[colidx]}" ]]; then
        eventalias_array[colidx]="${eventcolumn_array[colidx]#*.}"
    fi
    TYPEOF_QUERY="SELECT pg_typeof(${eventcolumn_array[colidx]}) FROM"
    separator=""
    for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
        TYPEOF_QUERY+="${separator} ${canonical_array[tableidx]} AS ${eventtable_array[tableidx]}"
        separator=","
    done
    TYPEOF_QUERY+=" LIMIT 1"
    if [[ ${verbosity} -ge 2 ]]; then
        echo $TYPEOF_QUERY
    fi
    eventtype_array[colidx]=$(                                        \
        psql --quiet --tuples-only --no-align --command="\timing off" \
             --command="${TYPEOF_QUERY}"                              \
    )
done

for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    junctiontable=${TEMPSCHEMA}.${junction_array[tableidx]}
    if [[ "${flatten}" == "true" && ! -n "${eventlimit_array[tableidx]}" ]]; then
        LIMIT_QUERY="SELECT coalesce(max(count),0)"
        LIMIT_QUERY+=" FROM (SELECT count(*) AS count"
        LIMIT_QUERY+=" FROM ${junctiontable}"
        LIMIT_QUERY+=" JOIN ${canonical_array[tableidx]} AS ${eventtable_array[tableidx]} ON ${eventtable_array[tableidx]}.${eventid_array[tableidx]}=${junctiontable}.${eventid_array[tableidx]}"
        if [[ -n "${polyfilter}" ]]; then
            LIMIT_QUERY+=" JOIN ${polytable} ON ${polytable}.id = poly_id"
            LIMIT_QUERY+=" WHERE (${polyfilter})"
        fi
        if [[ -n "${eventfilter[tableidx]}" ]]; then
            if [[ -n "${polyfilter}" ]]; then
                LIMIT_QUERY+=" AND (${eventfilter[tableidx]})"
            else
                LIMIT_QUERY+=" WHERE (${eventfilter[tableidx]})"
            fi
        fi
        LIMIT_QUERY+=" GROUP BY ${junctiontable}.poly_id) AS foo"
        if [[ ${verbosity} -ge 2 ]]; then
            echo $LIMIT_QUERY
        fi
        eventlimit_array[tableidx]=$(psql \
                --quiet --tuples-only --no-align \
                --command="\timing off" \
                --command="${LIMIT_QUERY}")
        if [[ ${verbosity} -ge 1 ]]; then
            echo Limit for event table ${eventtable_array[tableidx]} is ${eventlimit_array[tableidx]}
        fi
    fi
done

VIEW_QUERY="SELECT"
separator=""
foreignkeycommand=""
for ((colidx=0; colidx<${#polyalias_array[@]}; colidx++)) do
    VIEW_QUERY+="${separator} ${polytable}.${polycolumn_array[colidx]} AS \"${polyalias_array[colidx]}\""
    separator=","
    if [[ "${polycolumn_array[colidx]}" == "id" ]]; then
        foreignkeycommand=" ADD CONSTRAINT fk_poly_id FOREIGN KEY (${polyalias_array[colidx]}) REFERENCES ${polytable}(id)"
    fi
done
for ((colidx=0; colidx<${#calcalias_array[@]}; colidx++)) do
    VIEW_QUERY+="${separator} ${calccolumn_array[colidx]} AS \"${calcalias_array[colidx]}\""
    separator=","
done
for ((colidx=0; colidx<${#eventalias_array[@]}; colidx++)) do
    if [[ "${flatten}" != "true" ]]; then
        VIEW_QUERY+="${separator} coalesce(${eventcolumn_array[colidx]}, '{}'::${eventtype_array[colidx]}[]) AS \"${eventalias_array[colidx]}\""
        separator=","
    else
        for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
            for ((linkidx=1; linkidx<=${eventlimit_array[tableidx]}; linkidx++)) do
                VIEW_QUERY+="${separator} ${eventcolumn_array[colidx]}_${linkidx} AS \"${eventalias_array[colidx]}_${linkidx}\""
                separator=","
            done
        done
    fi
    separator=","
done
VIEW_QUERY+=" FROM ${polytable}"
separator=""
for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
    junctiontable=${TEMPSCHEMA}.${junction_array[tableidx]}
    VIEW_QUERY+=" LEFT OUTER JOIN"
    if [[ -n "${eventlimit_array[tableidx]}" ]]; then
        VIEW_QUERY+=" LATERAL"
    fi
    VIEW_QUERY+=" (SELECT"
    VIEW_QUERY+=" ${eventtable_array[tableidx]}.poly_id"
    separator=","
    for ((colidx=0; colidx<${#eventcolumn_array[@]}; colidx++)) do
        if [[ "${eventcolumncorrelation_array[colidx]}" == ""
           || "${eventcolumncorrelation_array[colidx]}" == "${eventtable_array[tableidx]}" ]]; then
            if [[ "${flatten}" == "true" ]]; then
                for ((linkidx=1; linkidx<=${eventlimit_array[tableidx]}; linkidx++)) do
                    VIEW_QUERY+="${separator} (array_agg(${eventcolumn_array[colidx]}))[${linkidx}] AS \"${eventcolumn_array[colidx]#*.}_${linkidx}\""
                    separator=","
                done
            else
                VIEW_QUERY+="${separator} array_agg(${eventcolumn_array[colidx]}"
                VIEW_QUERY+=") AS \"${eventcolumn_array[colidx]#*.}\""
                separator=","
            fi
        fi
    done
    VIEW_QUERY+=" FROM (SELECT ${junctiontable}.poly_id"
    for ((colidx=0; colidx<${#eventcolumn_array[@]}; colidx++)) do
        if [[ "${eventcolumncorrelation_array[colidx]}" == ""
           || "${eventcolumncorrelation_array[colidx]}" == "${eventtable_array[tableidx]}" ]]; then
            VIEW_QUERY+=", ${eventcolumn_array[colidx]}"
        fi
    done
    VIEW_QUERY+=" FROM ${junctiontable}"
    VIEW_QUERY+=" JOIN ${canonical_array[tableidx]} AS ${eventtable_array[tableidx]}"
    VIEW_QUERY+=" ON ${eventtable_array[tableidx]}.${eventid_array[tableidx]}=${junctiontable}.${eventid_array[tableidx]}"
    separator="WHERE"
    if [[ -n "${eventlimit_array[tableidx]}" ]]; then
        VIEW_QUERY+=" ${separator} ${junctiontable}.poly_id = ${polytable}.id"
        separator="AND"
    fi
    if [[ -n "${eventfilter_array[tableidx]}" ]]; then
        VIEW_QUERY+=" ${separator} (${eventfilter_array[tableidx]})"
        separator="AND"
    fi
    if [[ -n "${eventorder_array[tableidx]}" ]]; then
        VIEW_QUERY+=" ORDER BY ${eventorder_array[tableidx]}"
    fi
    if [[ -n "${eventlimit_array[tableidx]}" ]]; then
        VIEW_QUERY+=" LIMIT ${eventlimit_array[tableidx]}"
    fi
    VIEW_QUERY+=") AS ${eventtable_array[tableidx]}"
    VIEW_QUERY+=" GROUP BY ${eventtable_array[tableidx]}.poly_id"
    VIEW_QUERY+=") AS ${eventtable_array[tableidx]}"
    if [[ -n "${eventlimit_array[tableidx]}" ]]; then
        VIEW_QUERY+=" ON true"
    else
        VIEW_QUERY+=" ON ${eventtable_array[tableidx]}.poly_id = ${polytable}.id"
    fi
done
if [[ -n "${polyfilter}" ]]; then
    VIEW_QUERY+=" WHERE (${polyfilter})"
fi
if [[ ${#polycolumn_array[@]} -gt 0 ]]; then
    VIEW_QUERY+=" GROUP BY"
    separator=""
    for ((colidx=0; colidx<${#polycolumn_array[@]}; colidx++)) do
        VIEW_QUERY+="${separator} ${polytable}.${polycolumn_array[colidx]}"
        separator=","
    done
    for ((colidx=0; colidx<${#eventcolumn_array[@]}; colidx++)) do
        if [[ "${flatten}" != "true" ]]; then
            VIEW_QUERY+="${separator} ${eventcolumn_array[colidx]}"
            separator=","
        else
            for ((tableidx=0; tableidx<${#eventtable_array[@]}; tableidx++)) do
                for ((linkidx=1; linkidx<=${eventlimit_array[tableidx]}; linkidx++)) do
                    VIEW_QUERY+="${separator} ${eventcolumn_array[colidx]}_${linkidx}"
                    separator=","
                done
            done
        fi
    done
fi

if [[ ${verbosity} -ge 2 ]]; then
    echo "$VIEW_QUERY" > /dev/stderr  
fi

if [[ -n "${viewfile}" ]]; then
    if [[ ${verbosity} -ge 1 ]]; then
        echo "Creating shapefile ${viewfile}"
    fi
    pgsql2shp -q -f "${viewfile}" -u $PGUSER $PGDATABASE "${VIEW_QUERY}"
    zip --move --junk-paths "${viewfile}".zip "${viewfile}".{cpg,dbf,prj,shp,shx}
else
    if [[ "${append}" != "true" ]]; then
        if [[ ${verbosity} -ge 1 ]]; then
            echo "Creating table ${viewtable}"
        fi
        if [[ "${nobackup}" != "true" ]]; then  
            backupcommand="CALL cycle_table('${viewtable}')"
        else
            backupcommand=
        fi
        if [[ "${nocomments}" != "true" ]]; then
            commentcommand="COMMENT ON TABLE ${viewtable} IS '${COMMENTS//\'/\'\'}'"
        else
            commentcommand=
        fi
        if [[ "${foreignkeycommand}" != "" ]]; then
            foreignkeycommand="ALTER TABLE ${viewtable} ${foreignkeycommand}"
        fi
        psql --quiet \
             --command="${backupcommand}" \
             --command="CREATE TABLE ${viewtable} AS ${VIEW_QUERY}" \
             --command="${commentcommand}" \
             --command="${foreignkeycommand}"

        for ((indexidx=0; indexidx<${#index_array[@]}; indexidx++)) do
            if [[ -n "${using_array[indexidx]}" ]]; then
                using="USING ${using_array[indexidx]}"
            else
                using=""
            fi
            psql --quiet \
                 --command="CREATE INDEX ON ${viewtable} ${using} (${index_array[indexidx]})"
        done
    else
        if [[ ${verbosity} -ge 1 ]]; then
            echo "Appending to table ${viewtable}"
        fi
        if [[ "${nocomments}" != "true" ]]; then
            INCOMMENTS=$(psql --csv --tuples-only --no-align --quiet --command="\timing off" --command "SELECT obj_description('${viewtable}'::regclass, 'pg_class')")
            NEWCOMMENTS="${COMMENTS}${INCOMMENTS}"
            commentcommand="COMMENT ON TABLE ${viewtable} IS '${NEWCOMMENTS//\'/\'\'}'"
        else
            commentcommand=
        fi
        
        psql --quiet \
             --command="CREATE TEMP TABLE ${viewtable}_append AS ${VIEW_QUERY}" \
             --command="INSERT INTO ${viewtable} SELECT * FROM ${viewtable}_append" \
             --command="${commentcommand}"
    fi
fi
