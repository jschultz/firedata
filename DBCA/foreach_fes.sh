#!/bin/bash
#
# Copyright 2022 Jonathan Schultz
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

help="Run argreplay substituting 'fes' with each Forest Ecosystem in turn"
args=(
# "-short:--long:variable:default:description:flags"
  ":--dry-run:::Print but do not execute command:flag"
  "-p:--parallel:::Use GNU parallel:private,flag"
  "-d:--depth::0:Depth of command history to replay, default is all."
  "-S:--substitute:::Substitutions to add to script invocation:"
  "-l:--logfile:::Log file to record processing, defaults to 'script'.log:private"
  ":--nologfile:::Don't write a log file:private,flag"
  ":script:::argreplay script to run:required"
)

source $(dirname "$0")/../common/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        logfile=$(basename ${script})
        logfile="${logfile%.*}.log"
    fi
    echo "${COMMENTS}" > ${logfile}
fi

if [[ "${parallel}" == "true" ]]; then
    psql \
      --quiet --tuples-only --no-align \
      --command "\timing off" \
      --command "select distinct descript from forest_ecosystem order by descript" |
    parallel "
        if [[ \"${dry_run}\" != "true" ]]; then
            argreplay --depth ${depth} --substitute fes:{} ${substitute} -- ${script}
        else
            echo argreplay --depth ${depth} --substitute fes:\"{}\" ${substitute} -- ${script} 
        fi"
else
    psql \
      --quiet --tuples-only --no-align \
      --command "\timing off" \
      --command "select distinct descript from forest_ecosystem order by descript" |
    while read -r fes; do 
        if [[ "${dry_run}" != "true" ]]; then
            argreplay --depth ${depth} --substitute fes:"${fes}" ${substitute} -- ${script}
        else
            echo argreplay --depth ${depth} --substitute fes:\"${fes}\" ${substitute} -- ${script}
        fi
    done
fi