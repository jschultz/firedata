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
from spacetrack import SpaceTrackClient
from pyorbital.orbital import Orbital
from pyorbital import tlefile
import spacetrack.operators as op
from dateutil import parser as dateparser
from datetime import datetime, timedelta
import math
import os
import sys
import shutil
import csv

def plotSatellite(arglist=None):

    parser = ArgumentRecorder(description='Plot satellite position.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)

    parser.add_argument('--no-comments',      action='store_true', help='Do not output descriptive comments')
    parser.add_argument('--no-header',        action='store_true', help='Do not output CSV header with column names')
    
    parser.add_argument('-t', '--tlefile',    type=str, required=True, help='File containing TLE data')
    
    parser.add_argument('-s', '--satfile',    type=str, required=True, help='File containing satellite observation data in CSV format')
    parser.add_argument('-o', '--outfile',    type=str, help='Output CSV file, otherwise use stdout.', output=True)

    args = parser.parse_args(arglist)
    hiddenargs = ['verbosity', 'no_comments']

    incomments = ''

    if args.outfile is None:
        outfile = sys.stdout
    else:
        if os.path.exists(args.outfile):
            shutil.move(args.outfile, args.outfile + '.bak')

        outfile = open(args.outfile, 'w')
    
    satcodes = { 'N':     37849,
                'Terra': 25994,
                'Aqua':  27424 }

    tledict = {}
    for norad_id in satcodes.values():
        tledict[norad_id] = ()

    tlefile = open(args.tlefile, 'r')
    line1 = tlefile.readline().rstrip()
    while len(line1) > 1:
        norad_id = int(line1[2:7])
        year2d = int(line1[18:20])
        daynum = float(line1[20:32])
        tledate = datetime(2000 + year2d if year2d <= 56 else 1900 + year2d, 1, 1) + timedelta(days=daynum)
        line2 = tlefile.readline().rstrip()
        tledict[norad_id] += ((tledate, line1, line2),)
        line1 = tlefile.readline().rstrip()

    satfile = open(args.satfile, 'r')
    satcsv = csv.DictReader(satfile)
    
    satout = csv.DictWriter(outfile, fieldnames = satcsv.fieldnames + ['azimuth', 'elevation', 'timeoffset'])
    satout.writeheader()
    minelevation = 90
    tleindexes = {}
    lastline1 = None
    lastline2 = None
    for satline in satcsv:
        passdatetime = dateparser.parse(satline['acq_date'] + ' ' + satline['acq_time'])
        satcode = satcodes[satline['satellite']]
        tletuples = tledict[satcode]
        tleidx = tleindexes.get(satcode, 0)
        while tletuples[tleidx+1][0] <= passdatetime:
            tleidx += 1
        tleindexes[satcode] = tleidx

        tletuple = tletuples[tleidx]
        line1 = tletuple[1]
        line2 = tletuple[2]

        if line1 != lastline1 or line2 != lastline2:
            orb = Orbital("", line1=line1, line2=line2)
            lastline1 = line1
            lastline2 = line2
        next_passes = orb.get_next_passes(passdatetime - timedelta(hours = 12), 24, float(satline['longitude']), float(satline['latitude']), 0, horizon=0)

        passidx = 0
        bestidx = None
        bestoffset = -9999999
        for passidx in range(len(next_passes)):
            next_pass = next_passes[passidx]
            offset = (next_pass[2] - passdatetime).total_seconds()
            if abs(offset) < abs(bestoffset):
                bestidx = passidx
                bestoffset = offset
            elif offset > 0:
                break

        if abs(bestoffset) > 600:
            print("WARNING: offset=", bestoffset)
            print("   ", satline)
        if bestidx is not None:
            (satline['azimuth'], elevation) = orb.get_observer_look(next_passes[bestidx][2], float(satline['longitude']), float(satline['latitude']), 0)
            satline['elevation']  = elevation
            satline['timeoffset'] = bestoffset

        satout.writerow(satline)
        if elevation < minelevation:
            minelevation = elevation
    
    if args.outfile is not None:
        outfile.close()
        
    print("Minimum elevation is ", minelevation)

if __name__ == '__main__':
    plotSatellite(None)
