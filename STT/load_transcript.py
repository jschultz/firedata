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
import glob
import re
import datetime
import sys
import os
import csv
import shutil
from sqlalchemy import *

def loadTranscript(arglist=None):
    parser = ArgumentRecorder(description='Read and process scanner transcript files',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)
    
    parser.add_argument('-c', '--csvfile',    type=str, 
                                              help='Output CSV file', output=True)
    parser.add_argument('-d', '--database',   type=str,
                                              help='SQLAlchemy database specification')
    
    parser.add_argument('--no-comments',      action='store_true', help='Do not output descriptive comments')
    parser.add_argument('--no-header',        action='store_true', help='Do not output CSV header with column names')

    parser.add_argument('--logfile',   type=str, help="Logfile", private=True)
    parser.add_argument('--no-logfile', action='store_true', help='Do not output a logfile')

    parser.add_argument('infile',             type=str, help="Filename pattern to match", input=True)

    args = parser.parse_args(arglist)


    if args.csvfile:
        if os.path.exists(args.csvfile):
            shutil.move(args.csvfile, args.csvfile + '.bak')
        csvfile = open(args.csvfile, 'w')

        if not args.no_comments:
            parser.write_comments(args, csvfile, incomments=ArgumentHelper.separator())

        csvwriter=csv.DictWriter(csvfile, fieldnames=['name', 'channel', 'datetime', 'text'])
        if not args.no_header:
            csvwriter.writeheader()
        
    if args.database:
        if not args.no_logfile:
            if args.logfile:
                logfilename = args.logfile
            else:
                logfilename = args.infile + '.log'

            logfile = open(logfilename, 'w')
            parser.write_comments(args, logfile, incomments=ArgumentHelper.separator())
            logfile.close()

        database = create_engine(args.database)
        connection  = database.connect()
        metadata = MetaData()

        # try:
        #     transcript = Table('Transcript', metadata, autoload_with=database)
        # except sqlalchemy.exc.NoSuchTableError:
        transcript = Table('Transcript', metadata,
            Column('Name',          String(256)),
            Column('Channel',       Integer),
            Column('DateTime',      DateTime,       unique=True),
            Column('Text',          String(256)))
        metadata.create_all(database)

        transaction = connection.begin()

    filenameregexp = re.compile(R"(?P<name>.+?)(-Chan(?P<channel>[0-9]+))?-(?P<year>[0-9]{2,4})(?P<month>[0-9]{2})(?P<day>[0-9]{2})-(?P<hour>[0-9]{2})(?P<minute>[0-9]{2})(?P<second>[0-9]{2}).+", re.UNICODE)
    lineregexp = re.compile(r"^\[(?P<minute>[0-9]{2}):(?P<second>[0-9]{2}).(?P<csec>[0-9]{2})\]\s*(?P<text>.*)$", re.UNICODE)
    
    for filename in glob.glob(args.infile):
        basename = os.path.basename(filename)
        filenamematch = filenameregexp.match(basename)
        if filenamematch:
            name      = filenamematch.group('name')
            channel   = int(filenamematch.group('channel') or 0)
            year      = int(filenamematch.group('year'))
            if year < 100:
                year += 2000
            month     = int(filenamematch.group('month'))
            day       = int(filenamematch.group('day'))
            hour      = int(filenamematch.group('hour'))
            minute    = int(filenamematch.group('minute'))
            second    = int(filenamematch.group('second'))

            basetime=datetime.datetime(year, month, day, hour, minute, second)
        else:
            print("ERROR: Filename " + basename + " does not match pattern", file=sys.stderr)
        
        infile = open(filename, 'r')

        for line in infile:
            linematch = lineregexp.match(line)
            if linematch:
                minute = int(linematch.group('minute'))
                second = int(linematch.group('second'))
                csec   = int(linematch.group('csec'))
                text   =     linematch.group('text')
                
                finaltime = basetime + datetime.timedelta(minutes=minute, seconds=second, milliseconds = csec*10)
                
                if args.csvfile:
                    csvwriter.writerow({'name':name, 'channel':channel, 'datetime':finaltime, 'text':text})
                if args.database:
                    connection.execute(transcript.delete().where(transcript.c.DateTime == finaltime))
                    connection.execute(transcript.insert().values({
                        'Name': name,
                        'Channel': channel,
                        'DateTime': finaltime,
                        'Text': text}))
                    
    
    if args.csvfile:
        csvfile.close()
    if args.database:
        transaction.commit()
        connection.close()
        database.dispose()
        
if __name__ == '__main__':
    loadTranscript(None)
