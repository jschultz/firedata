#!/usr/bin/env python
# -*- coding: utf-8 -*-
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

from argrecord import ArgumentHelper, ArgumentRecorder
from pyorbital import tlefile
from spacetrack import SpaceTrackClient
import spacetrack.operators as op
from dateutil import parser as dateparser
from datetime import date, timedelta
import os, shutil

def retrieveTLE(arglist=None):

    parser = ArgumentRecorder(description='Retrieve TLD data from space-track.org',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)

    parser.add_argument('--no-comments',      action='store_true', help='Do not output descriptive comments')
    parser.add_argument('--no-header',        action='store_true', help='Do not output CSV header with column names')
    
    parser.add_argument('-u', '--user',       type=str, required=True, help='SpaceTrack.org username')
    parser.add_argument('-p', '--password',   type=str, required=True, help='SpaceTrack.org password')

    parser.add_argument('-s', '--satellite',  type=str, required=True, help='NORAD name')
    parser.add_argument('--startdate',        type=str, required=True, help='Start date/time in any sensible format')
    parser.add_argument('--enddate',          type=str, help='End date/time in any sensible format')
    parser.add_argument('-l', '--limit',      type=int, help='Limit number of TLEs to retrieve')
    
    parser.add_argument('-o', '--outfile',    type=str, help='Output CSV file, otherwise use stdout.', output=True)

    args = parser.parse_args(arglist)
    hiddenargs = ['verbosity', 'no_comments']

    incomments = ''
    
    args.startdate = dateparser.parse(args.startdate) if args.startdate else None
    args.enddate   = dateparser.parse(args.enddate) if args.enddate else None

    if args.outfile is None:
        outfile = sys.stdout
    else:
        if os.path.exists(args.outfile):
            shutil.move(args.outfile, args.outfile + '.bak')

        outfile = open(args.outfile, 'w')

    st = SpaceTrackClient(identity=args.user, password=args.password)
    tledict = tlefile.read_platform_numbers()
    norad_cat_id = tledict[args.satellite]
    drange = op.inclusive_range(args.startdate, args.enddate or date.today())
    lines = st.tle(norad_cat_id=norad_cat_id, epoch=drange, format='tle', limit=args.limit).split("\n")
    for line in lines:
        outfile.write(line + "\n")
        
    if args.outfile is not None:
        outfile.close()

    exit(0)

if __name__ == '__main__':
    retrieveTLE(None)
