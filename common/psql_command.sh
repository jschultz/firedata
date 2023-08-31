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

help='Runs PSQL commands and generates logfile or comments to enable replaying.'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  "-D:--database:::Database to connect to; default is environment variabe PGDATABASE"
  "-c:--command:::Semicolon list of commands to run:required"
  "-c:--csvfile:::CSV file to output"
  "-l:--logfile:::Log file to record processing, defaults to 'basename' + .log"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--nocomments:::Don't write comments to CSV output:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${debug}" == "true" ]]; then
    set -x
fi

if [[ (! -n "${csvfile}" || -n "${logfile}" ) && "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${basename}.log"
    fi
    echo -n "${COMMENTS}" > ${logfile}
fi

IFS=';' read -d "\0" -r -a command_array <<< "${command}\0"
if [[ -n "${csvfile}" ]]; then
    echo -n > "${csvfile}"
    if [[ "${nocomments}" != "true" ]]; then
        echo -n "${COMMENTS}"           >> "${csvfile}"
        echo -n "${COMMENTS_SEPARATOR}" >> "${csvfile}"
    fi

#     printf -- "--command\0%s\0" "${command_array[@]}" | xargs -0 psql ${database} \
#         --quiet --csv --command "\timing off" \
#         >> "${csvfile}"
    command_array=("\timing off" "${command_array[@]/%/;}")
    printf "%s\n" "${command_array[@]}" | psql ${database} \
        --quiet --csv \
        >> "${csvfile}"
else
#     printf -- "--command\0%s\0" "${command_array[@]}" | xargs -0 psql ${database} \
#         --quiet --command "\timing off"
    command_array=("\timing off" "${command_array[@]/%/;}")
    printf "%s\n" "${command_array[@]}" | psql ${database} \
        --quiet --csv
fi
