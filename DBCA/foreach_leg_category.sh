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

help="Run argreplay substituting 'leg_category' with each legistated category in turn"
args=(
# "-short:--long:variable:default:description:flags"
  "-p:--parallel:::Use GNU parallel:private,flag"
  "-S:--substitute:::Substitutions to add to script invocation:"
  "-v:--verbosity::1:"
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
      --command "select distinct leg_category from legislated_lands_and_waters_dbca_011 order by leg_category" |
    parallel -u -q argreplay --verbosity ${verbosity} --substitute leg_category:{} ${substitute} -- ${script}
else
    psql \
      --quiet --tuples-only --no-align \
      --command "\timing off" \
      --command "select distinct leg_category from legislated_lands_and_waters_dbca_011 order by leg_category" |
    while read -r leg_category; do argreplay --verbosity ${verbosity} --substitute leg_category:"${leg_category}" ${substitute} -- ${script}; done
fi