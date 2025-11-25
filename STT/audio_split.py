#!/usr/bin/env python
# -*- coding: utf-8 -*-
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

from argrecord import ArgumentHelper, ArgumentRecorder
import subprocess
import re
import os
import sys
from datetime import datetime, timedelta
from pymediainfo import MediaInfo

FFMPEG_BIN = "ffmpeg"

def audioSplit(arglist=None):
    parser = ArgumentRecorder(description='Split an audio file into non-silect sections',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity', type=int, default=1, private=True)
    
    parser.add_argument('--logfile',   type=str, help="Logfile", private=True)
    parser.add_argument('--nologfile', action='store_true', help='Do not output a logfile')

    parser.add_argument('--outdir',    type=str, help="Directory to output files (must exist)")

    parser.add_argument('infiles',     type=str, nargs='+', help="Name of audio file(s) to export", input=True)

    args = parser.parse_args(arglist)

    if not args.nologfile:
        if args.logfile:
            logfilename = args.logfile
        else:
            logfilename = 'audio_split.log'
                
        logfile = open(logfilename, 'w')
        parser.write_comments(args, logfile, incomments=ArgumentHelper.separator())
        logfile.close()

    INFILE_REGEX = re.compile(R"(?P<prefix>.*)(?P<year>(20)?[0-9]{2})(?P<month>[0-9]{2})(?P<day>[0-9]{2})\-(?P<hour>[0-9]{2})(?P<minute>[0-9]{2})(?P<second>[0-9]{2})(\-(?P<volume>[0-9]{2}))?.*")
    
    for infile in args.infiles:
        if args.verbosity >= 1:
            print("Processing file: ", infile, file=sys.stderr)
            
        infile_ext = os.path.splitext(infile)[1]
        infile_match = INFILE_REGEX.match(infile)
        if infile_match:
            prefix = infile_match.group('prefix')
            if args.outdir:
                prefix = os.path.join(args.outdir, os.path.basename(prefix))
            
            year = int(infile_match.group('year'))
            if year < 100:
                year += 2000
            basedatetime = datetime(year, int(infile_match.group('month')), int(infile_match.group('day')), int(infile_match.group('hour')), int(infile_match.group('minute')), int(infile_match.group('second')))
            if infile_match.group('volume'):
                volume = int(infile_match.group('volume'))
                basedatetime = basedatetime + (volume - 1) * timedelta(hours=18, minutes=38, seconds=28, milliseconds=860)

        else:
            print("ERROR: filename does not match date/time pattern", file=sys.stderr)
            return
             
        command = [ FFMPEG_BIN, '-nostats',
                    '-i', infile,
                    '-af', 'silencedetect=duration=30:noise=0.1', '-f', 'null', 
                    '/dev/null']

        pipe = subprocess.Popen(command, stderr=subprocess.PIPE)
        
        SILENCE_START_REGEX = re.compile(R".*silence_start: (?P<silence_start>[0-9]*(\.[0-9]*)?)")
        SILENCE_END_REGEX   = re.compile(R".*silence_end: (?P<silence_end>[0-9]*(\.[0-9]*)?).*silence_duration: (?P<silence_duration>[0-9]*(\.[0-9]*)?)")

        silence_end = 0
        while True:
            line = pipe.stderr.readline().decode()
            if not line:
                break
             
            silence_start_match = SILENCE_START_REGEX.match(line)
            if silence_start_match:
                silence_start = float(silence_start_match.group('silence_start'))

                if args.verbosity >= 2:
                    print("Found chunk: ", silence_end, silence_start, file=sys.stderr)

                if silence_end:
                    datetime_start = basedatetime + timedelta(seconds = silence_end)
                    datetime_end   = basedatetime + timedelta(seconds = silence_start)

                    subprocess.run( [ FFMPEG_BIN, '-nostats', '-loglevel', 'quiet',
                                    '-y',
                                    '-i', infile,
                                    '-ss', str(silence_end),
                                    '-to', str(silence_start),
                                    '-c', 'copy',
                                    prefix + datetime_start.strftime("%Y%m%d-%H%M%S") + infile_ext ] )
                    subprocess.run( [ 'touch',
                                    '--date='+str(datetime_end),
                                    prefix + datetime_start.strftime("%Y%m%d-%H%M%S") + infile_ext ] )

                    silence_end = None

            else:
                silence_end_match = SILENCE_END_REGEX.match(line)
                if silence_end_match:
                    silence_end      = float(silence_end_match.group('silence_end'))
                    silence_duration = float(silence_end_match.group('silence_duration'))

        if silence_end:
            datetime_start = basedatetime + timedelta(seconds = silence_end)

            subprocess.run( [ FFMPEG_BIN, '-nostats', '-loglevel', 'quiet',
                            '-y',
                            '-i', infile,
                            '-ss', str(silence_end),
                            '-c', 'copy',
                            prefix + datetime_start.strftime("%Y%m%d-%H%M%S") + infile_ext ] )

            datetime_end = datetime_start + timedelta(milliseconds = MediaInfo.parse(prefix + datetime_start.strftime("%Y%m%d-%H%M%S") + infile_ext).tracks[0].duration)
            subprocess.run( [ 'touch',
                            '--date='+str(datetime_end),
                            prefix + datetime_start.strftime("%Y%m%d-%H%M%S") + infile_ext ] )


        
if __name__ == '__main__':
    audioSplit(None)
