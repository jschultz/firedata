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

def fireProgression(arglist=None):

    parser = ArgumentRecorder(description='Present BOM data.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)

    parser.add_argument('-q', '--qgisfile',   type=str, help='QGIS base file')
    parser.add_argument('-t', '--temporal',   type=str, required=True, help='Date/time for temporal data in any sensible format')

    parser.add_argument('-o', '--outfile',    type=str, required=True, help='Output SVG file, otherwise plot on screen.', output=True)
    parser.add_argument('--logfile',          type=str, help="Logfile", private=True)
    parser.add_argument('--no-logfile',       action='store_true', help='Do not output descriptive comments')

    args = parser.parse_args(arglist)

    temporal = dateparser.parse(args.temporal)

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
    project.read('/home/jschultz/data/Fire/Stirlings/Stirlings.qgz')

    manager = QgsProject.instance().layoutManager()
    layout = manager.layoutByName("Single map")
    layout.items()[0].setTemporalRange(QgsDateTimeRange(QDateTime(temporal),QDateTime(temporal)))

    exporter = QgsLayoutExporter(layout)
    exporter.exportToSvg(args.outfile,QgsLayoutExporter.SvgExportSettings())

    qgs.exitQgis()

if __name__ == '__main__':
    fireProgression(None)
