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
from datetime import datetime, timedelta, MINYEAR
import math
import os
import sys
import shutil
import csv
from geo import sphere
import subprocess

def trackHotspotSatellite(arglist=None):

    parser = ArgumentRecorder(description='Track satellite position, bearing, previous and next passdatetimes from hotspot data.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)

    parser.add_argument('-u', '--user',       type=str, required=True, help="PostgreSQL username")
    parser.add_argument('-d', '--database',   type=str, required=True, help="PostgreSQL database")

    parser.add_argument('-l', '--limit',      type=int, help='Limit number of rows to process')
    
    parser.add_argument('-t', '--tlefile',    type=str, required=True, help='File containing TLE data')
    parser.add_argument('-w', '--where',      type=str, required=True, help="'Where' clause to select hotspots")
    parser.add_argument('-H', '--hotspots',   type=str, default='hotspots', help="Hotspot table name")
    parser.add_argument('-s', '--suffix',     type=str, required=True, help="Suffix to append to 'hotspots' to get output table name")
    parser.add_argument('-D', '--drop-table', action='store_true', help='Drop output table if it exists')
    
    parser.add_argument('--logfile',          type=str, help="Logfile, default is 'hotspots'_'suffix'.log", private=True)
    parser.add_argument('--no-logfile',       action='store_true', help='Do not output descriptive comments')

    args = parser.parse_args(arglist)

    if not args.no_logfile:
        if not args.logfile:
            args.logfile = args.hotspots + '_' + args.suffix + '.log'

        if os.path.exists(args.logfile):
            shutil.move(args.logfile, args.logfile.split('/')[-1].rsplit('.',1)[0] + '.bak')
            
        logfile = open(args.logfile, 'w')
        parser.write_comments(args, logfile, incomments=ArgumentHelper.separator())
        logfile.close()

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
        
    psqlin = subprocess.Popen(['psql', args.database, args.user,
                               '--quiet',
                               '--command', r'\timing off',
                               '--command', r'\copy (SELECT * FROM ' + args.hotspots + ' WHERE ' + args.where + ' ORDER BY acq_date + acq_time) TO STDOUT CSV HEADER'],
                               stdout=subprocess.PIPE, encoding='UTF-8')

    satcsv = csv.DictReader(psqlin.stdout)
    
    psqlout = subprocess.Popen(['psql', args.database, args.user,
                                '--quiet',
                                '--command', r'\timing off'] +
                              (['--command', 'DROP TABLE IF EXISTS ' + args.hotspots + '_' + args.suffix] if args.drop_table else []) +
                               ['--command', 'CREATE TABLE ' + args.hotspots + '_' + args.suffix + ' AS TABLE ' + args.hotspots + ' WITH NO DATA',
                                '--command', 'ALTER TABLE ' + args.hotspots + '_' + args.suffix + '     \
                                                  ADD COLUMN pass_azimuth NUMERIC(8,5),                 \
                                                  ADD COLUMN pass_elevation NUMERIC(8,5),               \
                                                  ADD COLUMN pass_bearing NUMERIC(8,5),                 \
                                                  ADD COLUMN pass_datetime TIMESTAMP WITHOUT TIME ZONE, \
                                                  ADD COLUMN prev_azimuth NUMERIC(8,5),                 \
                                                  ADD COLUMN prev_elevation NUMERIC(8,5),               \
                                                  ADD COLUMN prev_datetime TIMESTAMP WITHOUT TIME ZONE, \
                                                  ADD COLUMN next_azimuth NUMERIC(8,5),                 \
                                                  ADD COLUMN next_elevation NUMERIC(8,5),               \
                                                  ADD COLUMN next_datetime TIMESTAMP WITHOUT TIME ZONE, \
                                                  DROP COLUMN IF EXISTS geometry,                       \
                                                  ADD COLUMN geometry geometry GENERATED ALWAYS AS (ST_Rotate(ST_MakeEnvelope((ST_X(ST_Transform(ST_SetSRID(ST_MakePoint((longitude)::DOUBLE PRECISION, (latitude)::DOUBLE PRECISION), 4326), 28350)) - ((scan * (500)::NUMERIC))::DOUBLE PRECISION), (ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint((longitude)::DOUBLE PRECISION, (latitude)::DOUBLE PRECISION), 4326), 28350)) - ((track * (500)::NUMERIC))::DOUBLE PRECISION), (ST_X(ST_Transform(ST_SetSRID(ST_MakePoint((longitude)::DOUBLE PRECISION, (latitude)::DOUBLE PRECISION), 4326), 28350)) + ((scan * (500)::NUMERIC))::DOUBLE PRECISION), (ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint((longitude)::DOUBLE PRECISION, (latitude)::DOUBLE PRECISION), 4326), 28350)) + ((track * (500)::NUMERIC))::DOUBLE PRECISION), 28350), ((((- pass_bearing) * 3.1415926) / (180)::NUMERIC))::DOUBLE PRECISION, ST_Transform(ST_SetSRID(ST_MakePoint((longitude)::DOUBLE PRECISION, (latitude)::DOUBLE PRECISION), 4326), 28350))) STORED',
                                '--command', r'\copy ' + args.hotspots + '_' + args.suffix + ' FROM STDIN CSV HEADER'],
                                stdin=subprocess.PIPE, encoding='UTF-8')
    
    satout = csv.DictWriter(psqlout.stdin, fieldnames = satcsv.fieldnames + ['pass_azimuth', 'pass_elevation', 'pass_bearing', 'pass_datetime', 'prev_azimuth', 'prev_elevation', 'prev_datetime', 'next_azimuth', 'next_elevation', 'next_datetime'])
    
    minelevation = 90
    tleindexes = {}
    lastdatetime = datetime(MINYEAR,1,1)
    lastline1 = None
    lastline2 = None
    inrowcount = 0
    for satline in satcsv:
        thisdatetime = dateparser.parse(satline['acq_date'] + ' ' + satline['acq_time'])
        satcode = satcodes[satline['satellite']]
        tletuples = tledict[satcode]
        tleidx = tleindexes.get(satcode, 0)
        assert(thisdatetime >= lastdatetime)
        lastdatetime = thisdatetime
        while tletuples[tleidx+1][0] <= thisdatetime - timedelta(hours = 12):
            tleidx += 1
        tleindexes[satcode] = tleidx

        tletuple = tletuples[tleidx]
        line1 = tletuple[1]
        line2 = tletuple[2]

        if line1 != lastline1 or line2 != lastline2:
            orb = Orbital("", line1=line1, line2=line2)
            lastline1 = line1
            lastline2 = line2

        passdatetimes = [next_pass[2] for next_pass in orb.get_next_passes(thisdatetime - timedelta(hours=24), 48, float(satline['longitude']), float(satline['latitude']), 0, horizon=0)]
                     
        nearpasses = []
        leastoffset = 999999
        leastoffsetidx = None
        for passidx in range(len(passdatetimes)):
            max_elevation_time = passdatetimes[passidx]
            (azimuth, elevation) = orb.get_observer_look(max_elevation_time, float(satline['longitude']), float(satline['latitude']), 0)
            if elevation > 20:
                thisoffset = (max_elevation_time - thisdatetime).total_seconds()
                if abs(thisoffset) < abs(leastoffset):
                    leastoffsetidx = len(nearpasses)
                    leastoffset = thisoffset

                nearpasses += [(max_elevation_time, azimuth, elevation)]

        if abs(leastoffset) > 600:
            print("WARNING: offset=", leastoffset)
            #print("   ", satline)
            
        if len(nearpasses):
            nearestpass = nearpasses[leastoffsetidx]
            satline['pass_datetime'] = nearestpass[0]
            satline['pass_azimuth']  = nearestpass[1]
            satline['pass_elevation']  = nearestpass[2]
            
            (lon1, lat1, alt1) = orb.get_lonlatalt(max_elevation_time - timedelta(seconds = 30))
            (lon2, lat2, alt2) = orb.get_lonlatalt(max_elevation_time + timedelta(seconds = 30))
            point1 = (lon1, lat1)
            point2 = (lon2, lat2)
            bearing = sphere.bearing(point1, point2)
            satline['pass_bearing'] = bearing
            
            if leastoffsetidx > 0:
                prevpass = nearpasses[leastoffsetidx - 1]
                satline['prev_datetime'] = prevpass[0]
                satline['prev_azimuth']  = prevpass[1]
                satline['prev_elevation']  = prevpass[2]
                
            if leastoffsetidx < len(nearpasses)-1:
                nextpass = nearpasses[leastoffsetidx + 1]
                satline['next_datetime'] = nextpass[0]
                satline['next_azimuth']  = nextpass[1]
                satline['next_elevation']  = nextpass[2]
            
        satout.writerow(satline)
            
        inrowcount += 1
        if args.limit and inrowcount == args.limit:
            break
    
if __name__ == '__main__':
    trackHotspotSatellite(None)
