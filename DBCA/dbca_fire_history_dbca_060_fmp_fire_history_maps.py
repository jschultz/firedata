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
import sys
import tempfile, os

def renderLayout(arglist=None):

    parser = ArgumentRecorder(description='Present BOM data.',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)

    parser.add_argument('-q', '--qgisfile',   type=str, required=True, help='QGIS base file')
    parser.add_argument('-l', '--layer',      type=str, required=True, help='Layout from QGIS file')
    parser.add_argument('-L', '--layout',     type=str, required=True, help='Layout from QGIS file')
    
    parser.add_argument('-c', '--cutoff',     type=int, required=True, help='Cutoff value for graduated renderer')

    parser.add_argument('-p', '--pdffile', type=str, help="Name of PDF file to export")
    parser.add_argument('-i', '--imagefile', type=str, help="Name of image file to export")

    parser.add_argument('--logfile',          type=str, help="Logfile", private=True)
    parser.add_argument('--no-logfile',       action='store_true', help='Do not output descriptive comments')

    args = parser.parse_args(arglist)

    # if not args.pdffile:
    #     args.pdffile = args.table
        
    if not args.no_logfile:
        if not args.logfile and not args.pdffile:
            logfile = sys.stdout
        else:
            if args.logfile:
                logfilename = args.logfile
            elif args.pdffile:
                logfilename = args.pdffile.split('/')[-1].rsplit('.',1)[0] + '.log'
                
            logfile = open(logfilename, 'w')

        parser.write_comments(args, logfile, incomments=ArgumentHelper.separator())
        
        if args.logfile or args.pdffile:
            logfile.close()

    # QgsApplication.setPrefixPath("/usr", True)
    qgs = QgsApplication([b"__file__"], True)
    qgs.initQgis()

    project = QgsProject.instance()
    project.read(args.qgisfile)
    
    layer = project.mapLayersByName(args.layer)[0]
    renderer = layer.renderer()
    
    renderer.updateRangeUpperValue(0, args.cutoff-0.1)
    renderer.updateRangeLabel(0,'0 - %d years' % (args.cutoff -1 ))
    renderer.updateRangeLowerValue(1, args.cutoff-0.1)
    renderer.updateRangeLabel(1,'%d+ years' % (args.cutoff))

    # Work-around for problem: https://gis.stackexchange.com/questions/451557/updating-legend-for-graduated-symbol-using-pyqgis
    tempfilename = tempfile.mktemp(suffix='.qgs')
    project.write(tempfilename)
    project.read(tempfilename)
    
    manager = QgsProject.instance().layoutManager()
    layout = manager.layoutByName(args.layout)
    
    if layout is None:
        raise RuntimeError("Layout does not exist")

    exporter = QgsLayoutExporter(layout)
    
    if args.pdffile:
        pdfsettings = QgsLayoutExporter.PdfExportSettings()
        pdfsettings.simplifyGeometries = True
        pdfsettings.forceVectorOutput = False
        exporter.exportToPdf(args.pdffile + '.pdf', QgsLayoutExporter.PdfExportSettings())
    if args.imagefile:
        imagesettings = QgsLayoutExporter.ImageExportSettings()
        imagesettings.simplifyGeometries = True
        imagesettings.forceVectorOutput = False
        exporter.exportToImage(args.imagefile + '.jpg', imagesettings)

    qgs.exitQgis()
    
    os.remove(tempfilename)

if __name__ == '__main__':
    renderLayout(None)
