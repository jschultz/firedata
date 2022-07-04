#!/bin/bash
#
# Copyright 2021 Jonathan Schultz
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

help="Run argreplay substituting 'lmu' with each LMU in turn"
args=(
# "-short:--long:variable:default:description:flags"
  "-p:--parallel:::Use GNU parallel:private,flag"
  "-s:--script:::argreplay script to run:required"
  "-l:--logfile:::Log file to record processing, defaults to 'script'.log:private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

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
      --command "select distinct description from land_management_unit order by description" |
    parallel -u -q argreplay --substitute lmu:{} -- ${script}
else
    psql \
      --quiet --tuples-only --no-align \
      --command "\timing off" \
      --command "select distinct description from land_management_unit order by description" |
    while read -r lmu; do argreplay --substitute lmu:"${lmu}" -- ${script}; done
fi