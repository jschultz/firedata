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
from more_itertools import peekable
from dateutil import parser as dateparser
from datetime import datetime, timedelta
import math
import os
import sys
import shutil
import csv
from windrose import WindroseAxes
from matplotlib import pyplot, cm
import numpy

def bomPresentation(arglist=None):

    parser = ArgumentRecorder(description='Present BOM wind data as wind rose.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)

    parser.add_argument('-l', '--limit',      type=int, help='Limit number of rows to process')
    parser.add_argument(      '--since',      type=str, help='Lower bound date/time in any sensible format')
    parser.add_argument(      '--until',      type=str, help='Upper bound date/time in any sensible format')
    
    parser.add_argument('-b', '--bomfile',    type=str, help='CSV file containing BOM data; otherwise use stdin')

    parser.add_argument('-o', '--outfile',    type=str, help='Output SVG file, otherwise plot on screen.', output=True)
    parser.add_argument('--logfile',          type=str, help="Logfile", private=True)
    parser.add_argument('--no-logfile',       action='store_true', help='Do not output descriptive comments')

    args = parser.parse_args(arglist)

    if args.bomfile:
        bomfile = open(args.bomfile, 'r')
    else:
        bomfile = peekable(sys.stdin)

    until = dateparser.parse(args.until) if args.until else None
    since = dateparser.parse(args.since) if args.since else None

    # Read comments at start of bomfile.
    incomments = ArgumentHelper.read_comments(bomfile) or ArgumentHelper.separator()
    bomfieldnames = next(csv.reader([next(bomfile)]))
    bomcsv=csv.DictReader(bomfile, fieldnames=bomfieldnames)

    if not args.no_logfile:
        if not args.logfile and not args.outfile:
            logfile = sys.stdout
        else:
            if args.logfile:
                logfilename = args.logfile
            elif args.outfile:
                logfilename = args.outfile.split('/')[-1].rsplit('.',1)[0] + '.log'
                
            logfile = open(logfilename, 'w')

        parser.write_comments(args, logfile, incomments=incomments)
        
        if args.logfile or args.outfile:
            logfile.close()
    
    windspeed = []
    winddir  = []
    linecount = 0
    for bomline in bomcsv:
        timestamp = dateparser.parse(bomline['DateTime'])
        if since and timestamp < since:
            continue
        if until and timestamp > until:
            continue

        windspeed += [float(bomline['Wind speed measured in km/h'])]
        winddir += [float(bomline['Wind direction measured in degrees'])]
        linecount += 1
        if args.limit and linecount == args.limit:
            break

    windspeed = numpy.array(windspeed)
    winddir = numpy.array(winddir)

    ax = WindroseAxes.from_ax()
    ax.bar(winddir, windspeed, bins=numpy.arange(0,80,10), cmap=cm.Blues)
    ax.set_yticks(numpy.arange(0, 10, 2))
    ax.set_yticklabels([])
    #ax.axis('off')
    #ax.set_legend()

    if args.outfile:
        pyplot.savefig(args.outfile, transparent=True, format='svg')
    else:
        pyplot.show()
    
    if args.bomfile:
        bomfile.close()

    
if __name__ == '__main__':
    bomPresentation(None)
