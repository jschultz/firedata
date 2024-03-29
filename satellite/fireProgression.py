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
from qgis.core import *
from qgis.gui import QgsMapCanvas, QgsLayerTreeMapCanvasBridge
from qgis.PyQt import QtGui
from PyQt5.QtGui import QColor, QFont
from PyQt5.QtCore import QDate, QTime, QDateTime
from dateutil import parser as dateparser
import subprocess
import sys
import csv

def fireProgression(arglist=None):

    parser = ArgumentRecorder(description='Present BOM data.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)

    parser.add_argument('-t', '--table',      type=str, required=True, help="PostgreSQL table with hotspot datas")

    parser.add_argument('-q', '--qgisfile',   type=str, required=True, help='QGIS base file')
    parser.add_argument('-l', '--layout',     type=str, required=True, help='Layout from QGIS file')

    parser.add_argument('-o', '--outfile',    type=str, help='Output SVG file base name, otherwise use table name.', output=True)

    parser.add_argument('--logfile',          type=str, help="Logfile", private=True)
    parser.add_argument('--no-logfile',       action='store_true', help='Do not output descriptive comments')

    args = parser.parse_args(arglist)

    if not args.outfile:
        args.outfile = args.table
        
    if not args.no_logfile:
        if not args.logfile and not args.outfile:
            logfile = sys.stdout
        else:
            if args.logfile:
                logfilename = args.logfile
            elif args.outfile:
                logfilename = args.outfile.split('/')[-1].rsplit('.',1)[0] + '.log'
                
            logfile = open(logfilename, 'w')

        parser.write_comments(args, logfile, incomments=ArgumentHelper.separator())
        
        if args.logfile or args.outfile:
            logfile.close()

    QgsApplication.setPrefixPath("/usr", True)
    qgs = QgsApplication([], True)
    qgs.initQgis()

    project = QgsProject.instance()
    project.read(args.qgisfile)

    manager = QgsProject.instance().layoutManager()
    layout = manager.layoutByName(args.layout)

    psqlin = subprocess.Popen(['psql',
                               '--quiet',
                               '--command', r'\timing off',
                               '--command', r'\copy (SELECT satellite, instrument, acq_date + acq_time AS datetime FROM ' + args.table +
                                             '       GROUP BY satellite, instrument, datetime ORDER BY datetime) TO STDOUT CSV HEADER'],
                               stdout=subprocess.PIPE, encoding='UTF-8')

    satcsv = csv.DictReader(psqlin.stdout)
    for satline in satcsv:
        temporal = QDateTime(dateparser.parse(satline['datetime']))
        print ("Outputting: ", temporal.toString())
        layout.items()[0].setTemporalRange(QgsDateTimeRange(temporal,temporal))

        exporter = QgsLayoutExporter(layout)
        exporter.exportToSvg(args.outfile + '_' + satline['datetime'] + '.svg', QgsLayoutExporter.SvgExportSettings())

    qgs.exitQgis()

if __name__ == '__main__':
    fireProgression(None)
