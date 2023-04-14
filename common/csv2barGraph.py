#!/usr/bin/env python
# -*- coding: utf-8 -*-
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

from argrecord import ArgumentHelper, ArgumentRecorder
import more_itertools
import csv
import sys
from dateutil import parser as dateparser
#from datetime import datetime
from matplotlib import pyplot, dates as mdates, ticker
import numpy

def csv2barGraph(arglist=None):

    parser = ArgumentRecorder(description='Make a bar graph with X axis from first column and Y axis from subsequent columns on a CSV file',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)
    
    parser.add_argument('-b', '--blocks',     type=int, default=1, help='Number of blocks in each bar column')
    parser.add_argument('-C', '--columns',    type=int, default=1, help='Number of coumns')
    parser.add_argument('-w', '--whitespace', type=int, default=10, help='Percentage of width to leave as white space between columns')

    parser.add_argument('-l', '--limit',      type=int, help='Limit number of rows to process')
    parser.add_argument(      '--since',      type=str, help='X axis lower bound')
    parser.add_argument(      '--until',      type=str, help='X axis upper bound')
    parser.add_argument(      '--cumulative',  action='store_true', help='Cumulate Y data')
    
    parser.add_argument('-W', '--width',      type=int, default=400, help='Plot width in millimetres')
    parser.add_argument('-H', '--height',     type=int, default=200,  help='Plot height in millimetres')
    parser.add_argument('-t', '--title',      type=str,              help='Title of plot')
    parser.add_argument('-y', '--ylabel',     type=str,              help='Label for Y axis')
    parser.add_argument('-x', '--xlabel',     type=str,              help='Label for Y axis')
    parser.add_argument('-s', '--subtitle',   type=str,              help='Subtitle of plot')
    parser.add_argument('-c', '--colors',     type=str, nargs='+', help='Bar colors')
    parser.add_argument('-e', '--exec',       type=str, help='Arbitrary Python code to execute before rendering the graph')
    
    parser.add_argument('-o', '--outfile',    type=str, help='Output file, otherwise plot on screen.', output=True)
    parser.add_argument('--logfile',          type=str, help="Logfile", private=True)
    parser.add_argument('--nologfile',        action='store_true', help='Do not output descriptive comments')

    parser.add_argument(      'csvfile',      type=str, nargs='?', help='Name of CSV file containing data; otherwise use stdin', input=True)

    args = parser.parse_args(arglist)

    if args.csvfile:
        csvfile = open(args.csvfile, 'r')
    else:
        csvfile = more_itertools.peekable(sys.stdin)

    #until = datetime(int(args.until), 1, 1) if args.until else None
    #since = datetime(int(args.since), 1, 1) if args.since else None
    until = int(args.until) if args.until else None
    since = int(args.since) if args.since else None

    # Read comments at start of csvfile.
    incomments = ArgumentHelper.read_comments(csvfile) or ArgumentHelper.separator()
    csvfieldnames = next(csv.reader([next(csvfile)]))
    csvreader=csv.DictReader(csvfile, fieldnames=csvfieldnames)
    
    if not args.nologfile:
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

    start = None
    end = None
    Xdata = []
    Ydata = [[] for i in range(len(csvfieldnames) - 1)]
    linecount = 0    

    if args.cumulative:
        Y = [0] * (len(csvfieldnames) - 1)

    for csvline in csvreader:
        X = int(csvline[csvfieldnames[0]])
        if since and X < since:
            continue
        if until and X > until:
            break

        if args.cumulative:
            Y = [Y[idx-1] + float(csvline[csvfieldnames[idx]] or 0) for idx in range(1, len(csvfieldnames))]
        else:
            Y = [float(csvline[csvfieldnames[idx]] or 0) for idx in range(1, len(csvfieldnames))]
          
        if not start or X < start:
            start = X
        if not end or X > end:
            end = X
            
        Xdata += [X]
        for idx in range(len(Ydata)):
            Ydata[idx] = Ydata[idx] + [Y[idx]]
        linecount += 1
        if args.limit and linecount == args.limit:
            break

    pyplot.style.use('tableau-colorblind10')
    
    titlefont = {'fontname':'Linux Biolinum G', 'weight':'bold', 'size':24}
    subtitlefont = {'fontname':'Linux Biolinum G', 'weight':'normal'}
    labelfont = {'fontname':'Linux Biolinum G', 'weight':'normal'}
    legendfont = {'family':'Linux Biolinum G', 'weight':'normal'}

    fig = pyplot.figure()
    fig.set_size_inches(args.width / 25.4, args.height / 25.4)
    if args.title:
        fig.suptitle(args.title, **titlefont)

    ax = fig.add_subplot(111)
       
    # Ybars = (len(csvfieldnames) - 1 + args.blocks - 1) // args.blocks
    Ybars = args.columns
    Ybarwidth = (1 - args.whitespace / 100) / Ybars
    Ybaridx = 0
    Ybarnum = 0
    while Ybaridx < len(csvfieldnames):
        for Yblockidx in range(args.blocks):
            if Ybaridx >= len(csvfieldnames) - 1:
                break
            ax.bar(numpy.array(Xdata) - (Ybars - 1) / 2 * Ybarwidth + Ybarnum * Ybarwidth, 
                   Ydata[Ybaridx+Yblockidx], width=Ybarwidth, 
                   bottom=([sum(Ydata[Ybaridx+Yblockidx-1-Yidx][idx] for Yidx in range(Yblockidx)) for idx in range(len(Xdata))] if Yblockidx > 0 else None),
                   color = args.colors[Ybaridx+Yblockidx] if args.colors else None,
                   align='center',
                   label=csvfieldnames[Ybaridx+Yblockidx+1]
                   )
        Ybaridx += args.blocks
        Ybarnum += 1
        
    ax.set_xlabel(csvfieldnames[0], **labelfont)
    if args.subtitle:
        ax.set_title(args.subtitle, **subtitlefont)
    if args.ylabel:
        ax.set_ylabel(args.ylabel, **labelfont)
    if args.xlabel:
        ax.set_xlabel(args.xlabel, **labelfont)
    elif args.blocks == 1:
        ax.set_ylabel(csvfieldnames[1], **labelfont)
    ax.xaxis.set_major_locator(ticker.AutoLocator())
    # I just want a tick at each interval value. 9999 is just a big number.
    ax.xaxis.set_minor_locator(ticker.MaxNLocator(9999,integer=True))
    ax.set_xlim([int(args.since)-0.5 if args.since else None,
                 int(args.until)+0.5 if args.until else None])
    #pyplot.gca().invert_xaxis()
    pyplot.grid(axis='y', color='black')
    if args.blocks > 1 or Ybars > 1:
        ax.legend(prop=legendfont, framealpha=1)
    
    if args.exec:
        exec(args.exec)

    if args.outfile:
        pyplot.savefig(args.outfile, transparent=True)
    else:
        pyplot.show()
    
    if args.csvfile:
        csvfile.close()

    
if __name__ == '__main__':
    csv2barGraph(None)
