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

while :; do 
  /home/jschultz/src/firedata/DBCA/get_daily_burns.py --no-comments --csvfile /home/jschultz/daily_burns/daily_burns.csv
  cp -p /home/jschultz/daily_burns/daily_burns.csv /home/jschultz/daily_burns/daily_burns.$(date "+%Y-%m-%d_%H:%M:%S").csv
  cat /home/jschultz/daily_burns/daily_burns.csv | /home/jschultz/src/firedata/common/sendmail.py
done