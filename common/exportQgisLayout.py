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

    parser.add_argument('-l', '--layout', type=str, nargs='+', help="Print layout to export")
    parser.add_argument('-o', '--outpath', type=str, nargs='+', help="Name of output file(s) or directory(ies) to export to, default is 'layout'.pdf")

    parser.add_argument('-S', '--single',  action='store_true', help='Output atlas as a single file')
    parser.add_argument('-r', '--raster',  action='store_true', help='Export all layers as raster')

    parser.add_argument('-v', '--variable', nargs='+', type=str, help='List of variable:value pairs to define as project variables')

    parser.add_argument('--logfile',      type=str, help="Logfile", private=True)
    parser.add_argument('--nologfile',    action='store_true', help='Do not output a logfile')
    parser.add_argument('--nobackup',     action='store_true', help='Do not back up existing output file')

    parser.add_argument('qgisfile', type=str, help="Name of QGIS file")

    args = parser.parse_args(arglist)

    if not args.outpath:
        args.outpath = [''] * len(args.layout)
    if len(args.outpath) < len(args.layout):
        args.outpath.extend([''] * len(args.layout) - len(args.outpath))

    for idx in range(len(args.layout)):
        if idx >= len(args.outpath) or not args.outpath[idx]:
            args.outpath[idx] = args.layout[idx] + '.pdf'

    if not args.nologfile:
        if args.logfile:
            logfilename = args.logfile
        else:
            logfilename = args.outpath[0].split('/')[-1].rsplit('.',1)[0] + '.log'

        logfile = open(logfilename, 'w')
        parser.write_comments(args, logfile, incomments=ArgumentHelper.separator())
        logfile.close()

    # QgsApplication.setPrefixPath("/usr", True)
    qgs = QgsApplication([b"exportQgisLayout"], True)
    qgs.initQgis()

    project = QgsProject.instance()
    project.read(args.qgisfile)
    if args.variable:
        for var in args.variable:
            QgsExpressionContextUtils.setProjectVariable(project, var.split(':')[0], var.split(':')[1])

    manager = QgsProject.instance().layoutManager()
    index = 0
    for layoutname in args.layout:
        print("Exporting layout: ", layoutname)
        layout = manager.layoutByName(layoutname)

        if args.raster:
            for item in layout.items():
                if type(item).__name__ == 'QgsLayoutItemMap':
                    for layer in item.layersToRender():
                        if type(layer).__name__ == 'QgsVectorLayer':
                            layer.renderer().setForceRasterRender(True)

        outbasename     = os.path.basename(args.outpath[index])
        outroot, outext = os.path.splitext(outbasename)
        outext = outext[1:].casefold()
        if outext == 'pdf':
            pdfsettings = QgsLayoutExporter.PdfExportSettings()
        elif outext == 'svg':
            svgsettings = QgsLayoutExporter.SvgExportSettings()
        else:
            imagesettings = QgsLayoutExporter.ImageExportSettings()

        atlas = layout.atlas()
        if not atlas.enabled() or args.single:
            if args.outpath[index] and os.path.exists(args.outpath[index]) and not args.nobackup:
                os.rename(args.outpath[index], args.outpath[index] + '.bak')

            exporter = QgsLayoutExporter(layout)
            if not atlas.enabled():
                if outext == 'pdf':
                    exporter.exportToPdf(args.outpath[index], pdfsettings)
                elif outext == 'svg':
                    exporter.exportToSvg(args.outpath[index], svgsettings)
                else:
                    exporter.exportToImage(args.outpath[index], imagesettings)
            else:
                if outext == 'pdf':
                    exporter.exportToPdf(atlas, args.outpath[index], pdfsettings)
                elif outext == 'svg':
                    exporter.exportToSvg(atlas, args.outpath[index], svgsettings)
                else:
                    atlas.setFilenameExpression("'" + outroot + "'")   #Who knows?
                    exporter.exportToImage(atlas, args.outpath[index], outext, imagesettings)
        else:
            atlas.beginRender()
            while atlas.next():
                exporter = QgsLayoutExporter(atlas.layout())
                outpath = os.path.join(args.outpath[index], atlas.currentFilename() + outext)
                if os.path.exists(outpath) and not args.nobackup:
                    os.rename(outpath, outpath + '.bak')
                if outext == 'pdf':
                    exporter.exportToPdf(outpath, pdfsettings)
                elif outext == 'svg':
                    outpath = os.path.join(args.outpath[index], atlas.currentFilename() + '.svg')
                else:
                    exporter.exportToSvg(outpath, imagesettings)

            atlas.endRender

        index += 1

    qgs.exitQgis()

if __name__ == '__main__':
    exportQgisLayout(None)
