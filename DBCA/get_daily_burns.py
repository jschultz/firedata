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

from owslib.wms import WebMapService
from shapely.geometry import Polygon, MultiPolygon
import csv

wms = WebMapService('https://kmi.dpaw.wa.gov.au/geoserver/public/wms?service=WMS&version=1.1.1',version='1.1.1')
img=wms.getmap( layers=['public:todays_burns'], bbox=(108.0,-45.0,155.0,-10.0), size=(768,571), srs='EPSG:4283', format='rss' )
from bs4 import BeautifulSoup
data = BeautifulSoup(img.read(), "xml")
print(data.prettify())

items = data.find_all("item")
multipolygon = []
csvfile = open('daily_burns.csv', 'w')
csvwriter = None

for item in items:
    description = BeautifulSoup('<description>' + item.find("description").get_text() + '</description>', 'xml')
    spans = description.find_all("span")
    if len(spans) > 0:
        if multipolygon != []:
            attributes_dict['geom'] = multipolygon[0].wkt if len(multipolygon) == 1 else MultiPolygon(multipolygon).wkt
            multipolygon = []
            
            if csvwriter is None:
                fieldnames = list(attributes_dict.keys())
                csvwriter=csv.DictWriter(csvfile, fieldnames=fieldnames)
                csvwriter.writeheader()

            csvwriter.writerow(attributes_dict)
            
        attributes_dict = {}
        for n in range(len(spans) // 2):
            attributes_dict[spans[2 * n].get_text()] = spans[2 * n + 1].get_text()
            
        attributes_dict['burn_target_date'] = datetime.datetime.strptime('burn_target_date_raw','%m/%d/%y %I:%M %p')
            
    valiter = iter([float(val) for val in item.find("georss:polygon").get_text().split(' ')])
    polygon = Polygon([(lat, lon) for lat, lon in zip(valiter, valiter)])
    multipolygon += [polygon]

if multipolygon != []:
    attributes_dict['geom'] = multipolygon[0].wkt if len(multipolygon) == 1 else MultiPolygon(multipolygon).wkt
    multipolygon = []
    
    if csvwriter is None:
        fieldnames = list(attributes_dict.keys())
        csvwriter=csv.DictWriter(csvfile, fieldnames=fieldnames)
        csvwriter.writeheader()

    csvwriter.writerow(attributes_dict)
    
csvfile.close()
