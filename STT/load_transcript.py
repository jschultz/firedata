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
    parser.add_argument('-l', '--lrcfile',    type=str,
                                              help='Output LRC file', output=True)
    parser.add_argument('-d', '--database',   type=str,
                                              help='SQLAlchemy database specification')

    parser.add_argument('--nocomments',       action='store_true', help='Do not output descriptive comments')

    parser.add_argument('--logfile',   type=str, help="Logfile", private=True)
    parser.add_argument('--nologfile', action='store_true', help='Do not output a logfile')
    parser.add_argument('--noheader',  action='store_true', help='Do not output header to CSV file')

    parser.add_argument('inpattern', type=str, help="Filename pattern to match")

    args = parser.parse_args(arglist)


    if args.csvfile:
        if os.path.exists(args.csvfile):
            shutil.move(args.csvfile, args.csvfile + '.bak')
        csvfile = open(args.csvfile, 'w')

        if not args.nocomments:
            parser.write_comments(args, csvfile, incomments=ArgumentHelper.separator())

        csvwriter=csv.DictWriter(csvfile, fieldnames=['name', 'frequency', 'mode', 'channel', 'datetime', 'text'])
        if not args.noheader:
            csvwriter.writeheader()

    if args.lrcfile:
        if os.path.exists(args.lrcfile):
            shutil.move(args.lrcfile, args.lrcfile + '.bak')
        lrcfile = open(args.lrcfile, 'w')

    if args.database:
        if not args.nologfile:
            if args.logfile:
                logfilename = args.logfile
            else:
                logfilename = 'load_transcript.log'

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
            Column('Frequency',     Integer),
            Column('Mode',          String(32)),
            Column('Channel',       String(32)),
            Column('BaseTime',      DateTime),
            Column('DateTime',      DateTime),
            Column('Text',          String(256)),
            Column('Filename',      String(256)))
        metadata.create_all(database)

        transaction = connection.begin()

    filenameregexp = re.compile(R"(?P<name>[^-]*?[A-Za-z][^-]*?)?(?:-?(?P<frequency>[0-9]{8}))?(?:-(?P<mode>.+?))?(-Chan(?P<channel>[0-9]+))?(-(?P<year>(?:20)?[0-9]{2})(?P<month>[0-9]{2})(?P<day>[0-9]{2}))(-(?P<hour>[0-9]{2})(?P<minute>[0-9]{2})(?P<second>[0-9]{2}))?-.+", re.UNICODE)
    lineregexp = re.compile(r"^\[(?P<minute>[0-9]{1,3}):(?P<second>[0-9]{2}).(?P<csec>[0-9]{2})\]\s*(?P<text>.*)$", re.UNICODE)

    files = []
    for filename in glob.glob(args.inpattern):
        if args.verbosity >= 2:
            print("Matching file:", filename, file=sys.stderr)

        filenamematch = filenameregexp.match(os.path.basename(filename))
        if filenamematch:
            if args.verbosity >= 2:
                print("   Filename match:", filenamematch.groupdict(), file=sys.stderr)

            name      = filenamematch.group('name')
            frequency = int(filenamematch.group('frequency') or 0)
            channel   = int(filenamematch.group('channel') or 0)
            mode      = filenamematch.group('mode')
            year      = int(filenamematch.group('year') or 0)
            if year and year < 100:
                year += 2000
            month     = int(filenamematch.group('month') or 0)
            day       = int(filenamematch.group('day') or 0)
            hour      = int(filenamematch.group('hour') or 0)
            minute    = int(filenamematch.group('minute') or 0)
            second    = int(filenamematch.group('second') or 0)

            if year and month:
                basetime = datetime.datetime(year, month, day, hour, minute, second)
            else:
                if args.verbosity >= 2:
                    print ("NO BASETIME", file=sys.stderr)

                basetime = None

            files.append( {'fullname': filename, 'name': name, 'frequency': frequency, 'mode': mode, 'channel': channel, 'basetime': basetime} )
        else:
            print("ERROR: Filename " + filename + " does not match pattern", file=sys.stderr)


    for fileinfo in sorted(files, key=lambda fileinfo: fileinfo['basetime']):
        if args.verbosity >= 2:
            print("Processing file:", fileinfo['fullname'], file=sys.stderr)

        name = fileinfo['name']
        frequency = fileinfo['frequency']
        mode = fileinfo['mode']
        channel = fileinfo['channel']
        basetime = fileinfo['basetime'] or 0

        inpattern = open(fileinfo['fullname'], 'r', errors='ignore')    # Might be a better way

        lasttext = ''
        for line in inpattern:
            linematch = lineregexp.match(line)
            if linematch:
                minute = int(linematch.group('minute'))
                hour = minute // 60
                minute = minute % 60
                second = int(linematch.group('second'))
                csec   = int(linematch.group('csec'))
                text   =     linematch.group('text')

                if text != lasttext:
                    lasttext = text

                    if basetime:
                        finaltime = basetime + datetime.timedelta(hours=hour, minutes=minute, seconds=second, milliseconds = csec*10)
                    else:
                        finaltime = datetime.time(hour=hour, minute=minute, second=second, microsecond = csec*10000)

                    if args.csvfile:
                        csvwriter.writerow({'name':name, 'frequency':frequency, 'mode':mode, 'channel':channel, 'datetime':finaltime, 'text':text})
                    if args.lrcfile:
                        print(f"[{finaltime.hour*60+finaltime.minute}:{finaltime.second:02}:{finaltime.microsecond//10000:02}] {text}", file=lrcfile)
                    if args.database:
                        # connection.execute(transcript.delete().where(transcript.c.DateTime == finaltime))
                        connection.execute(transcript.insert().values({
                            'Name': name,
                            'Frequency': frequency,
                            'Mode': mode,
                            'Channel': channel,
                            'BaseTime': basetime,
                            'DateTime': finaltime,
                            'Text': text,
                            'Filename': fileinfo['fullname']}))

    if args.csvfile:
        csvfile.close()
    if args.lrcfile:
        lrcfile.close()
    if args.database:
        transaction.commit()
        connection.close()
        database.dispose()

if __name__ == '__main__':
    loadTranscript(None)
