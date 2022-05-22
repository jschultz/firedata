#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Copyright 2021 Jonathan Schultz
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
import os

def exportburnAtlas(arglist=None):

    parser = ArgumentRecorder(description='Exports an atlas from a QGIS file.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-B', '--burn',   type=str, required=True, help="ID of burn to export")
    parser.add_argument('-l', '--layout', type=str, required=True, help="Print layout to export")
    parser.add_argument('-p', '--pdffile', type=str, help="Name of PDF file to export")
    parser.add_argument('-i', '--imagefile', type=str, help="Name of image file to export")
    
    parser.add_argument('--logfile',      type=str, help="Logfile", private=True)
    parser.add_argument('--nologfile',    action='store_true', help='Do not output a logfile')
    
    parser.add_argument('qgisfile', type=str, nargs=1, help="Name of QGIS file")

    args = parser.parse_args(arglist)

    if not args.nologfile:
        if args.logfile:
            logfilename = args.logfile
        elif args.pdffile:
            logfilename = args.pdffile.split('/')[-1].rsplit('.',1)[0] + '.log'
        elif args.imagefile:
            logfilename = args.imagefile.split('/')[-1].rsplit('.',1)[0] + '.log'
                
        logfile = open(logfilename, 'w')
        parser.write_comments(args, logfile, incomments=ArgumentHelper.separator())
        logfile.close()

    QgsApplication.setPrefixPath("/usr", True)
    qgs = QgsApplication([], True)
    qgs.initQgis()

    project = QgsProject.instance()
    project.read(args.qgisfile[0])
    
    manager = QgsProject.instance().layoutManager()
    layout = manager.layoutByName(args.layout)
    
    atlas = layout.atlas()
    atlas.setFilterFeatures(True)
    atlas.setFilterExpression('"burnid"=\'{}\''.format(args.burn))
    exporter = QgsLayoutExporter(atlas.layout())
    if args.pdffile:
        pdfsettings = QgsLayoutExporter.PdfExportSettings()
        #pdfsettings.simplifyGeometries = False
        #pdfsettings.forceVectorOutput = True
        exporter.exportToPdf(atlas, args.pdffile, pdfsettings)
    if args.imagefile:
        imagesettings = QgsLayoutExporter.ImageExportSettings()
        imagesettings.simplifyGeometries = False
        imagesettings.forceVectorOutput = True
        imagebase, imagename = args.imagefile.rsplit('/',1)
        imageext = imagename.rsplit('.',1)[1]
        exporter.exportToImage(atlas, imagebase + '/', imageext, imagesettings)
        os.rename(imagebase + '/' + 'output_1.' + imageext, args.imagefile)
    
    qgs.exitQgis()

if __name__ == '__main__':
    exportburnAtlas(None)
