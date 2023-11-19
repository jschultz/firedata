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
# from qgis.gui import QgsMapCanvas, QgsLayerTreeMapCanvasBridge
# from qgis.PyQt import QtGui
# from PyQt5.QtGui import QColor, QFont
# from PyQt5.QtCore import QDate, QTime, QDateTime
# from dateutil import parser as dateparser
# import subprocess
# import sys
# import csv
import os

def exportQgisLayout(arglist=None):

    parser = ArgumentRecorder(description='Exports a layout as PDF, SVG or image file from a QGIS project.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-l', '--layout', type=str, default="Layout 1", help="Print layout to export")
    parser.add_argument('-o', '--outpath', type=str, help="Name of output file or directory to export to, default is 'layout'.pdf")

    parser.add_argument('-S', '--single',  action='store_true', help='Output atlas as a single file')
    parser.add_argument('-t', '--theme',   type=str, help='Map theme to apply')
    parser.add_argument('-r', '--raster',  action='store_true', help='Export all layers as raster')

    parser.add_argument('-v', '--variable', nargs='+', type=str, help='List of variable:value pairs to define as project variables')
    
    parser.add_argument('--logfile',      type=str, help="Logfile", private=True)
    parser.add_argument('--nologfile',    action='store_true', help='Do not output a logfile')
    parser.add_argument('--nobackup',     action='store_true', help='Do not back up existing output file')
    
    parser.add_argument('qgisfile', type=str, nargs=1, help="Name of QGIS file")

    args = parser.parse_args(arglist)

    # if not args.outpath:
    #     args.outpath = args.layout + '.pdf'
        
    if not args.nologfile:
        if args.logfile:
            logfilename = args.logfile
        elif args.outpath:
            logfilename = args.outpath.split('/')[-1].rsplit('.',1)[0] + '.log'
        else:
            logfilename = args.qgisfile[0].split('/')[-1].rsplit('.',1)[0] + '.log'
                
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

    for item in layout.items():
        if type(item).__name__ == 'QgsLayoutItemMap':
            if args.theme is not None:
                item.setFollowVisibilityPreset(True)
                item.setFollowVisibilityPresetName(args.theme)
            
            if args.raster:
                for layer in item.layersToRender():
                    if type(layer).__name__ == 'QgsVectorLayer':
                        layer.renderer().setForceRasterRender(True)

    outext = os.path.splitext(args.outpath)[1].casefold()[1:]
    if outext == 'pdf':
        pdfsettings = QgsLayoutExporter.PdfExportSettings()
    elif outext == 'svg':
        svgsettings = QgsLayoutExporter.SvgExportSettings()
    else:
        imagesettings = QgsLayoutExporter.ImageExportSettings()

    if args.single:
        if args.outpath and os.path.exists(args.outpath) and not args.nobackup:
            os.rename(args.outpath, args.outpath + '.bak')

        exporter = QgsLayoutExporter(layout)
        if outext == 'pdf':
            exporter.exportToPdf(layout.atlas(), args.outpath, pdfsettings)
        elif outext == 'svg':
            exporter.exportToSvg(layout.atlas(), args.outpath, svgsettings)
        else:
            exporter.exportToImage(layout.atlas(), args.outpath, outext, imagesettings)
    else:
        atlas =layout.atlas()
        atlas.beginRender()
        while atlas.next():
            exporter = QgsLayoutExporter(atlas.layout())
            outpath = os.path.join(args.outpath, atlas.currentFilename() + outext)
            if os.path.exists(outpath) and not args.nobackup:
                os.rename(outpath, outpath + '.bak')
            if outext == 'pdf':
                exporter.exportToPdf(outpath, pdfsettings)
            elif outext == 'svg':
                outpath = os.path.join(args.outpath, atlas.currentFilename() + '.svg')
            else:
                exporter.exportToSvg(outpath, imagesettings)
            
        atlas.endRender
        
    qgs.exitQgis()

if __name__ == '__main__':
    exportQgisLayout(None)
