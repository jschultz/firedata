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
from qgis.core import QgsLayoutExporter, QgsExpressionContextUtils
from qgis.gui import QgsMapCanvas, QgsLayerTreeMapCanvasBridge
from qgis.PyQt import QtGui
from PyQt5.QtGui import QColor, QFont
from PyQt5.QtCore import QDate, QTime, QDateTime
from dateutil import parser as dateparser
import subprocess
import sys
import csv
import os

from headlessMask import *

# We defined the function fireseason here even though it is defined as a project function
# because PyQGIS seems not to load project functions.
from qgis.core import qgsfunction
@qgsfunction(group='Custom', referenced_columns=[])
def fireseason(fih_date1):
    """
    Calculates the fire season of the fih_date1 argument
    """
    fih_date1 = fih_date1.toPyDate()
    return fih_date1.year if fih_date1.month <= 6 else fih_date1.year + 1

def exportburnAtlas(arglist=None):

    parser = ArgumentRecorder(description='Exports an atlas from a QGIS file.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-B', '--burnid',   type=str, required=True, help="ID of burn to export")
    parser.add_argument('-f', '--filter', type=str, help="Additional criteria for producing a page")
    parser.add_argument('-l', '--layout', type=str, required=True, help="Print layout(s) to export")
    parser.add_argument('-p', '--pdffile', type=str, help="Name(s) of PDF file(s) to export")
    parser.add_argument('-i', '--imagefile', type=str, help="Name(s) of image file(s) to export")
    
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

    qgs = QgsApplication([b"exportBurnAtlas"], True)
    qgs.initQgis()

    project = QgsProject.instance()
    project.read(args.qgisfile[0])

    burnPreviousFiresLayer = project.mapLayersByName("burn_previous_fires")[0]
    burnPreviousFiresLayer.setSubsetString ("burnid='" + args.burnid + "'")

    manager = project.layoutManager()
    layoutitem = manager.layoutByName(args.layout)

    atlas = layoutitem.atlas()
    if args.filter:
        atlas.setFilterExpression(args.filter)
        atlas.setFilterFeatures(True)
    else:
        atlas.setFilterFeatures(False)

    exporter = QgsLayoutExporter(atlas.layout())
    if args.pdffile:
        pdfsettings = QgsLayoutExporter.PdfExportSettings()
        pdfsettings.simplifyGeometries = False
        #pdfsettings.forceVectorOutput = True
        exporter.exportToPdf(atlas, args.pdffile, pdfsettings)
    if args.imagefile:
        imagesettings = QgsLayoutExporter.ImageExportSettings()
        imagesettings.simplifyGeometries = False
        imagesettings.forceVectorOutput = True
        imagepath, imagename = args.imagefile.rsplit('/',1)
        imagebase, imageext = imagename.rsplit('.',1)
        rc = exporter.exportToImage(atlas, imagepath + '/' + imagebase, imageext, imagesettings)

        # exportToImage seems not to respect output filename so we rename output files:
        image_num = 1
        while True:
            try:
                os.rename(imagepath + '/' + 'output_' + str(image_num) + '.' + imageext, imagepath + '/' + imagebase + '_' + str(image_num) + '.' + imageext)
                image_num += 1
            except:
                break

    qgs.exitQgis()

if __name__ == '__main__':
    exportburnAtlas(None)
