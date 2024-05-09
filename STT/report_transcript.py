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

from argrecord import ArgumentHelper, ArgumentRecorder
import datetime
from sqlalchemy import *

def reportTranscript(arglist=None):
    parser = ArgumentRecorder(description='Report on transcript database',
                              fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)
    
    parser.add_argument('-d', '--database',   type=str,
                                              help='SQLAlchemy database specification')
    
    parser.add_argument('--no-comments',      action='store_true', help='Do not output descriptive comments')
    parser.add_argument('--no-header',        action='store_true', help='Do not output CSV header with column names')


    args = parser.parse_args(arglist)

    if args.database:
        database = create_engine(args.database)
        connection  = database.connect()
        metadata = MetaData()
        metadata.reflect(bind=database)
        transcript = metadata.tables['Transcript']
        query = select(
            transcript.c.Name,
            transcript.c.DateTime,
            transcript.c.Text).order_by(
            transcript.c.DateTime)

        results = connection.execute(query).fetchall()
        lastName = None
        for name, datetime, text in results:
            if name != lastName:
                lastName = name
                print()
                print(name, datetime.strftime("%d/%m/%Y")  )
                print()
                
            print(datetime.strftime("%H:%M:%S"), text)

    if args.database:
        connection.close()
        database.dispose()
        
if __name__ == '__main__':
    reportTranscript(None)
