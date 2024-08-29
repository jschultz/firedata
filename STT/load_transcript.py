#!/usr/bin/env python
# -*- coding: utf-8 -*-
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

from argrecord import ArgumentHelper, ArgumentRecorder
import re
import datetime
import sys
import os
import csv
import shutil

def loadTranscript(arglist=None):
    parser = ArgumentRecorder(description='Read Daily Burns from DBCA WMS server, stopping when today''s burns have been retrieved',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)
    
    parser.add_argument('-c', '--csvfile',    type=str, 
                                              help='Output CSV file, default is ''infile''.csv.', output=True)
    
    parser.add_argument('--no-comments',      action='store_true', help='Do not output descriptive comments')

    parser.add_argument('infile',             type=str, help="Name of lrc transcript file to export", input=True)

    args = parser.parse_args(arglist)

    if args.csvfile is None:
        args.csvfile = os.path.splitext(args.infile)[0] + '.csv'

    if os.path.exists(args.csvfile):
        shutil.move(args.csvfile, args.csvfile + '.bak')

    csvfile = open(args.csvfile, 'w')

    if not args.no_comments:
        parser.write_comments(args, csvfile, incomments=ArgumentHelper.separator())

    filenameregexp = re.compile(R"(?P<frequency>[0-9]+)-.+-Chan(?P<channel>[0-9]+)-(?P<year>[0-9]{2})(?P<month>[0-9]{2})(?P<day>[0-9]{2})-(?P<hour>[0-9]{2})(?P<minute>[0-9]{2})(?P<second>[0-9]{2})-.+", re.UNICODE)

    filenamematch = filenameregexp.match(args.infile)
    if filenamematch:
        frequency = int(filenamematch.group('frequency'))
        channel   = int(filenamematch.group('channel'))
        year      = 2000 + int(filenamematch.group('year'))
        month     = int(filenamematch.group('month'))
        day       = int(filenamematch.group('day'))
        hour      = int(filenamematch.group('hour'))
        minute    = int(filenamematch.group('minute'))
        second    = int(filenamematch.group('second'))

        basetime=datetime.datetime(year, month, day, hour, minute, second)
    else:
        print("ERROR: Filename does not match pattern", file=sys.stderr)
    
    infile = open(args.infile, 'r')
    csvwriter=csv.DictWriter(csvfile, fieldnames=['frequency', 'channel', 'datetime', 'text'])
    csvwriter.writeheader()

    lineregexp = re.compile(r"^\[(?P<minute>[0-9]{2}):(?P<second>[0-9]{2}).(?P<csec>[0-9]{2})\]\s*(?P<text>.*)$", re.UNICODE)

    for line in infile:
        linematch = lineregexp.match(line)
        if linematch:
            minute = int(linematch.group('minute'))
            second = int(linematch.group('second'))
            csec   = int(linematch.group('csec'))
            text   =     linematch.group('text')
            
            finaltime = basetime + datetime.timedelta(minutes=minute, seconds=second, milliseconds = csec*10)
            csvwriter.writerow({'frequency':frequency, 'channel':channel, 'datetime':finaltime, 'text':text})

    csvfile.close()
        
if __name__ == '__main__':
    loadTranscript(None)
