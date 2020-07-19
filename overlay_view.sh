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

help='Produces a denormalised view containing polygon ID and geometry and a selection of shape columns'
args=(
# "-short:--long:variable:default:required"
  "-u:--user:::true:PostgreSQL username"
  "-d:--database:::true:PostgreSQL database"
  "-s:--shape:::false:Table name containing geometrical data"
  "-S:--suffix:::true:Suffix to append to shape table name to generate other table names"
  "-c:--columns::id:false:Comma separated list of columns to retrieve from linked shape data"
  "-n:--number:::false:Number of links to copy to view; default is minimum required to hold all links in the junction table"
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

poly=${shape}_${suffix}_poly
junction=${shape}_${suffix}_junction
view=${shape}_${suffix}_view
IFS=',' read -r -a columnarray <<< "${columns}"

echo "Creating view ${view}"
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

CREATE_VIEW="CREATE VIEW ${view} AS SELECT poly_id, poly_geometry, array_length(agg.${columnarray[0]}, 1) AS shape_count"
for ((linkidx=1; linkidx<=${number}; linkidx++)) do
    for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
        CREATE_VIEW+=", agg.${columnarray[colidx]}[${linkidx}] AS ${columnarray[colidx]}_${linkidx}"
    done
done
CREATE_VIEW+=" FROM (SELECT poly_id, poly.geometry AS poly_geometry"
for ((colidx=0; colidx<${#columnarray[@]}; colidx++)) do
    CREATE_VIEW+=", array_agg(shape.${columnarray[colidx]}) AS ${columnarray[colidx]}"
done
CREATE_VIEW+="       FROM ${junction} AS junction
                     JOIN ${poly} AS poly on poly.id = poly_id
                     JOIN ${shape} AS shape ON shape.id = shape_id
                     GROUP BY poly_id, poly_geometry) agg"

psql ${database} ${user} \
    --quiet \
    --command="DROP VIEW IF EXISTS ${view}" \
    --command="$CREATE_VIEW"
