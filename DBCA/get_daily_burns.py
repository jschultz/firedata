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
import urllib3
from owslib.wms import WebMapService
from owslib.util import Authentication
from fp.fp import FreeProxy, FreeProxyException
from bs4 import BeautifulSoup
from shapely.geometry import Polygon, MultiPolygon
import csv
from datetime import datetime
import dateutil.parser
import time
import sys
import os
import shutil

# Force IPv4 since IPv6 requests seem to fail
import requests.packages.urllib3.util.connection
requests.packages.urllib3.util.connection.HAS_IPV6 = False

def getDailyBurns(arglist=None):
    parser = ArgumentRecorder(description='Read Daily Burns from DBCA WMS server, stopping a change is detected.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)

    parser.add_argument('-s', '--server',     type=str,
                                              default='https://kmi.dpaw.wa.gov.au/geoserver/public/wms')
    parser.add_argument('-V', '--version',    type=str,
                                              default='1.1.1')
    parser.add_argument('-p', '--proxy',      type=str, help='Proxy URL or "free" to use free-proxy'),
    parser.add_argument('-l', '--layer',      type=str,
                                              default='public:todays_burns')
    parser.add_argument('-c', '--csvfile',    type=str,
                                              help='Output CSV file, otherwise use stdout.', output=True)
    parser.add_argument('-i', '--interval',   type=int, default=60,
                                              help='Polling interval.')
    parser.add_argument('-t', '--timeout',    type=int, default=30,
                                              help='Timeout for WMS request.')

    parser.add_argument('--no-comments',      action='store_true', help='Do not output descriptive comments')
    parser.add_argument('--no-header',        action='store_true', help='Do not output CSV header with column names')

    args = parser.parse_args(arglist)

    csv.field_size_limit(sys.maxsize)

    incomments = None
    infieldnames = []
    indata = []
    if args.csvfile is not None and os.path.exists(args.csvfile):
        infile = open(args.csvfile, 'r')
        incomments = ArgumentHelper.read_comments(infile) or ArgumentHelper.separator()
        try:
            infieldnames = next(csv.reader([next(infile)]))
            inreader=csv.DictReader(infile, fieldnames=infieldnames)
            indata = [row for row in inreader]
            infile.close()
        except StopIteration:
            pass


    def float2str(s):
        try:
            return str(float(s))
        except:
            return ''

    def decodeDailyBurns(wms):
        rc = []

        try:
            img=wms.getmap( layers=[args.layer], bbox=(108.0,-45.0,155.0,-10.0), size=(768,571), srs='EPSG:4283', format='rss', timeout=args.timeout )
        except:
            return None

        data = BeautifulSoup(img.read(), 'xml')
        # print(data.prettify())

        items = data.find_all('item')
        multipolygon = []

        for item in items:
            description = BeautifulSoup('<description>' + item.find("description").get_text() + '</description>', 'xml')
            spans = description.find_all("span")
            if len(spans) > 0:
                if multipolygon != []:
                    # attributes['geom'] = multipolygon[0].wkt if len(multipolygon) == 1 else MultiPolygon(multipolygon).wkt
                    multipolygon = []

                    rc += [attributes]

                attributes = {}
                for n in range(len(spans) // 2):
                    attributes[spans[2 * n].get_text()] = spans[2 * n + 1].get_text()

                attributes['burn_target_date'] = str(dateutil.parser.parse(attributes.get('burn_target_date_raw')).date())
                del attributes['burn_target_date_raw']
                attributes['indicative_area']  = float2str(attributes.get('indicative_area'))
                attributes['burn_target_long'] = float2str(attributes.get('burn_target_long'))
                attributes['burn_target_lat']  = float2str(attributes.get('burn_target_lat'))
                attributes['burn_planned_area_today'] = float2str(attributes.get('burn_planned_area_today'))
                try:
                    attributes['burn_est_start'] = str(dateutil.parser.parse(attributes.get('burn_est_start', '')).time())
                except:
                    pass

            valiter = iter([float(val) for val in item.find("georss:polygon").get_text().split(' ')])
            polygon = Polygon([(lat, lon) for lat, lon in zip(valiter, valiter)])
            multipolygon += [polygon]

        if multipolygon != []:
            # attributes['geom'] = multipolygon[0].wkt if len(multipolygon) == 1 else MultiPolygon(multipolygon).wkt
            multipolygon = []

            rc += [attributes]

        return rc

    if args.proxy:
        auth = Authentication(verify=False)
        urllib3.disable_warnings()
        if args.proxy != 'free':
            os.environ['http_proxy']  = args.proxy
            os.environ['https_proxy'] = args.proxy
        else:
            fp = FreeProxy(https=True, rand=True, timeout=2)
    else:
        auth = Authentication()

    lastpolltime = None

    while True:

        if args.proxy == 'free':
            while True:
                try:
                    if args.verbosity >= 2:
                        print("Looking for free proxy", file=sys.stderr)
                    proxy = fp.get()
                    os.environ['http_proxy']  = proxy
                    os.environ['https_proxy'] = proxy
                    if args.verbosity >= 2:
                        print("Found free proxy", proxy, file=sys.stderr)
                    break
                except FreeProxyException as e:
                    if args.verbosity >= 2:
                        # print("FreeProxyException occurred", file=sys.stderr)
                        print(e, file=sys.stderr)
                    continue

        if lastpolltime is not None:
            remaininginterval = args.interval - (datetime.now() - lastpolltime).total_seconds()
        else:
            remaininginterval = args.interval   # To avoid busy polling

        if args.verbosity >= 2:
            print("Remaining interval:", remaininginterval, file=sys.stderr)

        if remaininginterval > 0:
            time.sleep(remaininginterval)

        try:
            wms = WebMapService(args.server, version=args.version, auth=auth)
        except Exception as e:
            print(e, file=sys.stderr)
            wms = None

        lastpolltime = datetime.now()
        if wms:
            try:
                outdata = decodeDailyBurns(wms)
            except Exception as e:
                print(e, file=sys.stderr)
                outdata = None

            if outdata is not None:
                outfieldnames = list(set(sum([list(item.keys()) for item in outdata], start=[])))
                if set(outfieldnames) != set(infieldnames) or len(outdata) != len(indata):
                    break

                for data in outdata:
                    for fieldname in outfieldnames:
                        data[fieldname] = data.get(fieldname, '')

                if not all((indata[idx] == outdata[idx] for idx in range(len(indata)))):
                    if args.verbosity >= 2:
                        print([(indata[idx], outdata[idx]) for idx in range(len(indata)) if indata[idx] != outdata[idx]], file=sys.stderr)
                    break

    if args.csvfile is not None:
        if os.path.exists(args.csvfile):
            shutil.move(args.csvfile, args.csvfile + '.bak')

        csvfile = open(args.csvfile, 'w')
    else:
        csvfile = sys.stdout

    if not args.no_comments:
        parser.write_comments(args, csvfile, incomments=incomments)

    csvwriter=csv.DictWriter(csvfile, fieldnames=outfieldnames)
    csvwriter.writeheader()
    for item in outdata:
        csvwriter.writerow(item)

    if args.csvfile is not None:
        csvfile.close()

if __name__ == '__main__':
    getDailyBurns(None)

