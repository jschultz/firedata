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
import csv
import sys
from dateutil import parser as dateparser
from datetime import datetime
from matplotlib import pyplot, dates as mdates, axes

def bomPresentation(arglist=None):

    parser = ArgumentRecorder(description='Present BOM temperature and humidity as line graph.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)
    
    parser.add_argument('-b', '--bomfile',    type=str, help='CSV file containing BOM data; otherwise use stdin')
    parser.add_argument('-O', '--obsfile',    type=str, help='CSV file observation timestamps')

    parser.add_argument('-l', '--limit',      type=int, help='Limit number of rows to process')
    parser.add_argument(      '--since',      type=str, help='Lower bound date/time in any sensible format')
    parser.add_argument(      '--until',      type=str, help='Upper bound date/time in any sensible format')
    
    parser.add_argument('-W', '--width',      type=int, default=297, help='Plot width in millimetres')
    parser.add_argument('-H', '--height',     type=int, default=50,  help='Plot width in millimetres')
    
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

    observations = []
    if args.obsfile:
        obsfile = open(args.obsfile, 'r')
        obsfieldnames = next(csv.reader([next(obsfile)]))
        obscsv=csv.DictReader(obsfile, fieldnames=obsfieldnames)
        
        for obsline in obscsv:
            observations += [dateparser.parse(obsline['datetime'])]

    obsdatetime = []
    obstemp = []
    obshumidity = []
    start = None
    end = None
    linecount = 0
    for bomline in bomcsv:
        timestamp = dateparser.parse(bomline['DateTime'])
        if since and timestamp < since:
            continue
        if until and timestamp > until:
            continue
          
        if not start or timestamp < start:
            start = timestamp
        if not end or timestamp > start:
            end = timestamp
            
        obsdatetime += [timestamp]
        obstemp += [float(bomline['Air temperature in Degrees C'])]
        obshumidity += [float(bomline['Relative humidity in percentage %'])]

        linecount += 1
        if args.limit and linecount == args.limit:
            break

    fig,ax1 = pyplot.subplots()
    fig.set_size_inches(args.width / 25.4, args.height / 25.4)
    ax2 = ax1.twinx()
    ax3 = ax1.twiny()

    ax1.set_xlim(left=start, right=end)
    ax1.set_ylabel("Temperature", color="red")
    ax1.tick_params(axis="y", colors="red")
    ax1.plot(obsdatetime, obstemp, color="red")
    
    ax2.plot(obsdatetime, obshumidity, color="blue")
    ax2.set_ylabel("Relative humidity", color="blue")
    ax2.tick_params(axis="y", colors="blue")
    ax2.spines['left'].set_visible(False)

    ax1.xaxis.set_minor_locator(mdates.HourLocator(byhour=range(0,24,3)))
    ax1.xaxis.set_minor_formatter(mdates.DateFormatter('%H'))
    ax1.xaxis.set_major_locator(mdates.HourLocator(byhour=12))
    ax1.xaxis.set_major_formatter(mdates.DateFormatter('%d/%m'))
    ax1.xaxis.set_remove_overlapping_locs(False)
    ax1.tick_params(axis='x', which='major', length=0)
    ax1.xaxis.set_tick_params(which='major', pad=18, labelsize="large")
    
    ax3.xaxis.set_ticks_position('top')
    ax3.set_xticks(observations)
    ax3.set_xticklabels(observations)
    pyplot.setp(ax3.get_xticklabels(), visible=False)
    ax3.set_xlim(left=start, right=end)
    ax3.yaxis.set_visible(False)

    if args.outfile:
        pyplot.savefig(args.outfile, transparent=True, format='svg')
    else:
        pyplot.show()
    
    if args.bomfile:
        bomfile.close()

    
if __name__ == '__main__':
    bomPresentation(None)
