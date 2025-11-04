#!/bin/bash
#
# Copyright 2024 Jonathan Schultz
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

DAILY_BURNS_DIR="$HOME/daily_burns"
while :; do 
  argreplay get_daily_burns.log
  if [ $? -eq 0 ] && [ $(wc -c <"$DAILY_BURNS_DIR/daily_burns.csv") -gt 2 ]; then
    DAILY_BURNS_FILE="daily_burns.$(date "+%Y-%m-%d_%H:%M:%S").csv"
    cp -p "$DAILY_BURNS_DIR/daily_burns.csv" "$DAILY_BURNS_DIR"/"$DAILY_BURNS_FILE"
    argreplay sendmail.log
  fi
  echo $DAILY_BURNS_FILE
done
