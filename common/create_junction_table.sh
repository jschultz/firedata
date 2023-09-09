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

help='Creates a junction table containing selected columns from two different tables for each pair of records where geometry fields from the tables intersect'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  "-t1:--table1:::First table:required"
  "-c1:--column1:::Semicolon-delimited list of column(s) from table 1 to include in junction table"
  "-a1:--alias1:::Semicolon-delimited list of alias(es) for column(s) from table 1"
  "-g1:--geometry1::geom:Geometry column from table 1"
  
  "-t2:--table2:::Second table:required"
  "-c2:--column2:::Semicolon-delimited list of column(s) from table2 to include in junction table"
  "-a2:--alias2:::Semicolon-delimited list of alias(es) for column(s) from table2"
  "-g2:--geometry2::geom:Geometry column from table 2"
  
  "-C:--computed:::Semicolon-delimited list of computed columns to include in junction table"
  "-A:--computedalias:::Semicolon-delimited list of aliases for computed columns"
  
  "-j:--junction:::Name of junction table:required"

  "-l:--logfile:::Log file to record processing, defaults to 'junctio' + .log"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--nobackup:::Don't back up existing junction table:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${junction}.log"
    fi
    echo "${COMMENTS}" > ${logfile}
fi

if [[ "${debug}" == "true" ]]; then
    set -x
fi

IFS=';' read -r -a column1_array        <<< "${column1}"
IFS=';' read -r -a alias1_array         <<< "${alias1}"
IFS=';' read -r -a column2_array        <<< "${column2}"
IFS=';' read -r -a alias2_array         <<< "${alias2}"
IFS=';' read -r -a computed_array       <<< "${computed}"
IFS=';' read -r -a computedalias_array  <<< "${computedalias}"

for ((colidx=0; colidx<${#column1_array[@]}; colidx++)) do
    if [[ ! -n "${alias1_array[colidx]}" ]]; then
        alias1_array[colidx]="${column1_array[colidx]}"
    fi
done
for ((colidx=0; colidx<${#column2_array[@]}; colidx++)) do
    if [[ ! -n "${alias2_array[colidx]}" ]]; then
        alias2_array[colidx]="${column2_array[colidx]}"
    fi
done

if [[ "${nobackup}" != "true" ]]; then  
    backupcommand="CALL cycle_table('${junction}')"
else
    backupcommand=
fi

createcommand="CREATE TABLE \"${junction}\" AS SELECT"
separator=" "
for ((colidx=0; colidx<${#column1_array[@]}; colidx++)) do
    createcommand+="${separator}table1.\"${column1_array[colidx]}\" AS \"${alias1_array[colidx]}\""
    separator=","
done
for ((colidx=0; colidx<${#column2_array[@]}; colidx++)) do
    createcommand+="${separator}table2.\"${column2_array[colidx]}\" AS \"${alias2_array[colidx]}\""
    separator=","
done
for ((colidx=0; colidx<${#computed_array[@]}; colidx++)) do
    createcommand+="${separator}${computed_array[colidx]} AS \"${computedalias_array[colidx]}\""
    separator=","
done
createcommand+=" FROM \"${table1}\" AS table1, \"${table2}\" AS table2 WHERE ST_Intersects(table1.\"${geometry1}\", table2.\"${geometry2}\") GROUP BY"
separator=" "
for ((colidx=0; colidx<${#column1_array[@]}; colidx++)) do
    createcommand+="${separator}table1.\"${column1_array[colidx]}\""
    separator=","
done
for ((colidx=0; colidx<${#column2_array[@]}; colidx++)) do
    createcommand+="${separator}table2.\"${column2_array[colidx]}\""
    separator=","
done

psql --variable=ON_ERROR_STOP=1 \
    --command="${backupcommand}" \
    --command="${createcommand}"
