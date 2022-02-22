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

help='Calculate statistics on mean event intervals'
args=(
# "-short:--long:variable:default:description:flags"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-e:--eventtable:::Name of table containing events:required"
  "-d:--datefield:::Field name of event date in 'eventtable'"
  "-h:--historytable:::Name of table containing unique event history:required"
  "-s:--since:::Only consider events since this date"
  "-g:--seasongap::1:Minimum number of seasons between events"
  "-t:--table:::Database table to generate"
  "-l:--logfile:::Log file to record processing, defaults to table name with extension '.log':private"
  ":--nologfile:::Don't write a log file:private,flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        logfile=${table}.log
    fi
    echo "${COMMENTS}" > ${logfile}
fi

psql ${database} ${user} \
     --command="DROP TABLE IF EXISTS ${table}" \
     --command="CREATE TABLE ${table} AS
                  (SELECT geom, 
                          (SELECT AVG(interval_unnest) FROM unnest(interval_array(${historytable}, '${datefield}', '${eventtable}', '${since}'::timestamp, ${seasongap}::integer)) AS interval_unnest) AS mean_interval
                    FROM ${historytable})"
