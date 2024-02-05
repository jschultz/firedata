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
import subprocess
import re
import os
import sys
from datetime import datetime, timedelta

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

    INFILE_REGEX = re.compile(R"(?P<prefix>.*)(?P<year>[0-9]{4})(?P<month>[0-9]{2})(?P<day>[0-9]{2})\-(?P<hour>[0-9]{2})(?P<minute>[0-9]{2})(?P<second>[0-9]{2})(\-(?P<volume>[0-9]{2}))?.*")
    
    for infile in args.infiles:
        if args.verbosity >= 1:
            print("Processing file: ", infile, file=sys.stderr)
            
        infile_match = INFILE_REGEX.match(infile)
        if infile_match:
            prefix = infile_match.group('prefix')
            if args.outdir:
                prefix = os.path.join(args.outdir, os.path.basename(prefix))
            
            basedatetime = datetime(int(infile_match.group('year')), int(infile_match.group('month')), int(infile_match.group('day')), int(infile_match.group('hour')), int(infile_match.group('minute')), int(infile_match.group('second')))
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
        
        SILENCE_END_REGEX = re.compile(R".*silence_end: (?P<silence_end>[0-9]*(\.[0-9]*)?).*silence_duration: (?P<silence_duration>[0-9]*(\.[0-9]*)?)")
        
        sound_start = None
        while True:
            line = pipe.stderr.readline().decode()
            if not line:
                break
             
            silence_end_match = SILENCE_END_REGEX.match(line)
            if silence_end_match:
                silence_end      = float(silence_end_match.group('silence_end'))
                silence_duration = float(silence_end_match.group('silence_duration'))
            
            if sound_start:
                datetime_start = basedatetime + timedelta(seconds = sound_start)
                print(sound_start, silence_start)
                
                silence_start = round(silence_end - silence_duration, 4)
                
                if sound_start:
                    datetime_start = basedatetime + timedelta(seconds = sound_start)
                    if args.verbosity >= 2:
                        print("Found chunk: ", sound_start, silence_start, file=sys.stderr)
                    
                    replay_command = [ FFMPEG_BIN, '-nostats', '-loglevel', 'quiet',
                                    '-y',
                                    '-i', infile,
                                    '-ss', str(sound_start),
                                    '-to', str(silence_start),
                                    '-c', 'copy',
                                    prefix + datetime_start.strftime("%Y%m%d-%H%M%S") + '.wav' ]
                 
                    subprocess.run(replay_command)
                    
                sound_start = silence_end
                
            sound_start = silence_end
                            
            
    
        
if __name__ == '__main__':
    audioSplit(None)
