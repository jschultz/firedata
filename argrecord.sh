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

# help='Generic description.'
# args=(
# "-short:--long:variable:default:required:description:input:output:private"
# )

######################## START OF ARGUMENT PARSING CODE ########################

argshort=()
arglong=()
argvar=()
argdefault=()
argrequired=()
argdesc=()
arginput=()
argoutput=()
argprivate=()

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
    arginput+=("${arg[6]}")
    argoutput+=("${arg[7]}")
    argprivate+=("${arg[8]}")
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

COMMENTS=$'################################################################################\n'
COMMENTS+="# $(basename $0)"
COMMENTS+=$'\n'
for ((argidx=0; argidx<argn; argidx++)) do
    if [[ "${argprivate[argidx]}" != "true" ]] && [[ -n "${!argvar[argidx]}" ]]; then
        PREFIX="#"
        if [[ "${arginput[argidx]}" == "true" ]]; then
            PREFIX+="<   "
        elif [[ "${argoutput[argidx]}" == "true" ]]; then
            PREFIX+=">   "
        else
            PREFIX+="    "
        fi
        ARGSPEC="${arglong[argidx]:-${argshort[argidx]}} "
        if [ ${ARGSPEC:0:1} != "-" ]; then
            ARGSPEC=""
        fi
        LINE="${PREFIX}${ARGSPEC}\"${!argvar[argidx]}\""
        COMMENTS+="${LINE}"
        COMMENTS+=$'\n'
    fi
done

######################### END OF ARGUMENT PARSING CODE #########################

# echo "${COMMENTS}" > ${filename%.*}.log

