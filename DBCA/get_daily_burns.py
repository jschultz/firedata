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
from owslib.wms import WebMapService
from bs4 import BeautifulSoup
from shapely.geometry import Polygon, MultiPolygon
import csv
from datetime import datetime
import time
import sys
import os
import shutil

def getDailyBurns(arglist=None):
    parser = ArgumentRecorder(description='Read Daily Burns from DBCA WMS server, stopping when today''s burns have been retrieved',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)
    
    parser.add_argument('-s', '--server',     type=str, 
                                              default='https://kmi.dpaw.wa.gov.au/geoserver/public/wms?service=WMS&version=1.1.1')
    parser.add_argument('-V', '--version',    type=str,
                                              default='1.1.1')
    parser.add_argument('-l', '--layer',      type=str,
                                              default='public:todays_burns')
    parser.add_argument('-c', '--csvfile',    type=str, 
                                              help='Output CSV file, otherwise use stdout.', output=True)
    
    parser.add_argument('--no-comments',      action='store_true', help='Do not output descriptive comments')
    parser.add_argument('--no-header',        action='store_true', help='Do not output CSV header with column names')

    args = parser.parse_args(arglist)

    if args.csvfile is None:
        csvfile = sys.stdout
    else:
        if os.path.exists(args.csvfile):
            shutil.move(args.csvfile, args.csvfile + '.bak')

        csvfile = open(args.csvfile, 'w')

    if not args.no_comments:
        parser.write_comments(args, csvfile, incomments=ArgumentHelper.separator())


    def decodeDailyBurns():
        rc = []
        
        img=wms.getmap( layers=[args.layer], bbox=(108.0,-45.0,155.0,-10.0), size=(768,571), srs='EPSG:4283', format='rss' )
        
        data = BeautifulSoup(img.read(), 'xml')
        # print(data.prettify())

        items = data.find_all('item')
        multipolygon = []
        csvfile = open('daily_burns.csv', 'w')
        csvwriter = None

        for item in items:
            description = BeautifulSoup('<description>' + item.find("description").get_text() + '</description>', 'xml')
            spans = description.find_all("span")
            if len(spans) > 0:
                if multipolygon != []:
                    attributes['geom'] = multipolygon[0].wkt if len(multipolygon) == 1 else MultiPolygon(multipolygon).wkt
                    multipolygon = []
                    
                attributes = {}
                for n in range(len(spans) // 2):
                    attributes[spans[2 * n].get_text()] = spans[2 * n + 1].get_text()
                    
                attributes['burn_target_date'] = datetime.strptime(attributes['burn_target_date_raw'],'%m/%d/%y %I:%M %p').date()
                del attributes['burn_target_date_raw']
                attributes['indicative_area']  = float(attributes['indicative_area'])
                attributes['burn_target_long'] = float(attributes['burn_target_long'])
                attributes['burn_target_lat']  = float(attributes['burn_target_lat'])
                attributes['burn_planned_area_today'] = float(attributes['burn_planned_area_today'])
                attributes['burn_est_start'] = datetime.strptime(attributes['burn_est_start'],'%H:%M:%S').time()
                
                if attributes['burn_target_date'] != datetime.today().date():
                    return None
                    
            valiter = iter([float(val) for val in item.find("georss:polygon").get_text().split(' ')])
            polygon = Polygon([(lat, lon) for lat, lon in zip(valiter, valiter)])
            multipolygon += [polygon]

        if multipolygon != []:
            attributes['geom'] = multipolygon[0].wkt if len(multipolygon) == 1 else MultiPolygon(multipolygon).wkt
            multipolygon = []
            
            rc += [attributes]
            
        return rc

    wms = WebMapService(args.server, version=args.version)

    items = None
    while items is None:
        items = decodeDailyBurns()  
        if items is None:
            time.sleep(60)
        
    csvwriter=csv.DictWriter(csvfile, fieldnames=list(items[0].keys()))
    csvwriter.writeheader()
    for item in items:
        csvwriter.writerow(item)
        
    csvfile.close()
        
if __name__ == '__main__':
    getDailyBurns(None)
