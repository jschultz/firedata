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

help='Creates sequence table for a junction table based on some criterion in the underlying event table.'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  "-u:--user:::PostgreSQL username:required"
  "-d:--database:::PostgreSQL database:required"
  "-e:--eventtable:::Name of database table containing event data"
  ":--eventid::id:Id column in event table"
  "-S:--suffix:::Suffix to append to event table name to generate junction table name":"required"
  "-s:--sequence:::Name of sequence; appended to event table name plus suffix to generate sequence table name"
  "-E:--expression:::Expression for sorting events to create sequence"
  "-l:--logfile:::Log file to record processing, defaults to 'event' + 'suffix' + .log"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--keepdump:::Keep intermediate dump table:flag"
)

source $(dirname "$0")/argparse.sh

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n ${logfile} ]]; then
        logfile="${eventtable}_${suffix}_${sequence}.log"
    fi
    echo "${COMMENTS}" > ${logfile}
fi

if [[ "${debug}" == "true" ]]; then
    set -x
fi

junction=${eventtable}_${suffix}_junction
sequencetable=${eventtable}_${suffix}_${sequence}

echo "Creating sequence table ${sequencetable}"
psql ${database} ${user} \
    --quiet \
    --command="DROP TABLE IF EXISTS ${sequencetable}" CASCADE \
    --command="CREATE TABLE ${sequencetable} AS
      (SELECT poly_id, event_id,
              LAG(event_id)  OVER (PARTITION BY poly_id ORDER BY ${expression}) AS prev_event_id,
              LEAD(event_id) OVER (PARTITION BY poly_id ORDER BY ${expression}) AS next_event_id 
      FROM ${junction} JOIN ${eventtable} AS event ON event.${eventid} = event_id)"
