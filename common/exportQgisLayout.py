#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Copyright 2022 Jonathan Schultz
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

def exportQgisLayout(arglist=None):

    parser = ArgumentRecorder(description='Exports a layout from a QGIS file.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-l', '--layout', type=str, default="Layout 1", help="Print layout to export")
    parser.add_argument('-s', '--simplify', action='store_true', help="Simplify geometries")
    parser.add_argument('-o', '--outfile', type=str, help="Name of PDF file to export, default to 'layout'.pdf")

    parser.add_argument('-v', '--variable', nargs='+', type=str, help='List of variable:value pairs to define as project variables')
    
    parser.add_argument('--logfile',      type=str, help="Logfile", private=True)
    parser.add_argument('--nologfile',    action='store_true', help='Do not output a logfile')
    
    parser.add_argument('qgisfile', type=str, nargs=1, help="Name of QGIS file")

    args = parser.parse_args(arglist)

    if not args.outfile:
        args.outfile = args.layout + '.pdf'
        
    if not args.nologfile:
        if args.logfile:
            logfilename = args.logfile
        elif args.outfile:
            logfilename = args.outfile.split('/')[-1].rsplit('.',1)[0] + '.log'
                
        logfile = open(logfilename, 'w')
        parser.write_comments(args, logfile, incomments=ArgumentHelper.separator())
        logfile.close()

    # QgsApplication.setPrefixPath("/usr", True)
    qgs = QgsApplication([b"exportQgisLayout"], True)
    qgs.initQgis()

    project = QgsProject.instance()
    project.read(args.qgisfile[0])
    if args.variable:
        for var in args.variable:
            QgsExpressionContextUtils.setProjectVariable(project, var.split(':')[0], var.split(':')[1])
    
    manager = QgsProject.instance().layoutManager()
    layout = manager.layoutByName(args.layout)
    
    settings = QgsLayoutExporter.PdfExportSettings()
    settings.simplifyGeometries = args.simplify
    settings.forceVectorOutput = True
    exporter = QgsLayoutExporter(layout)
    # exporter.exportToPdf(args.outfile, settings)
    exporter.exportToPdf(layout.atlas(), args.outfile, settings)
    
    qgs.exitQgis()

if __name__ == '__main__':
    exportQgisLayout(None)
