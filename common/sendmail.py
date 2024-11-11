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
import smtplib, ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
from email.mime.base import MIMEBase
from email import encoders
from io import StringIO
import pandas
import os

def sendMail(arglist=None):
    parser = ArgumentRecorder(description='Send CSV data as an email', fromfile_prefix_chars='@')

    parser.add_argument('-v', '--verbosity',  type=int, default=1, private=True)
    
    parser.add_argument('-s', '--smtp',       type=str, required=True)
    parser.add_argument('-u', '--user',       type=str)
    parser.add_argument('-p', '--password',   type=str, private=True)
    parser.add_argument('-P', '--port',       type=int, default=587)

    parser.add_argument('-S', '--sender',     type=str, required=True)
    parser.add_argument('-R', '--recipient',  type=str, nargs='+')

    parser.add_argument(      '--subject',    type=str)
    parser.add_argument('-c', '--csvfile',    type=str, required=True)

    parser.add_argument('--logfile',          type=str, private=True,
                                              default='sendmail.log', help="Logfile name")
    parser.add_argument('--nologfile',        action='store_true', 
                                              help='Do not output a logfile')

    args = parser.parse_args(arglist)

    if not args.nologfile:
        logfile = open(args.logfile, 'w')
        parser.write_comments(args, logfile)
        logfile.close()

    msg = MIMEMultipart()
    msg['Subject'] = args.subject

    table_html = pandas.read_csv(args.csvfile).to_html()
    html = """\
    <html>
      <head></head>
      <body>
        """ + table_html + """
      </body>
    </html>
    """

    # Attach parts into message container.
    # According to RFC 2046, the last part of a multipart message, in this case
    # the HTML message, is best and preferred.
    msg.attach(MIMEText(html, 'html'))

    with open(args.csvfile, 'r') as file:
      text = file.read()

    part = MIMEBase('application', "octet-stream")
    part.set_payload(text)
    encoders.encode_base64(part)
    part.add_header('Content-Disposition',
                    'attachment; filename=' + os.path.basename(args.csvfile))
    msg.attach(part)

    context = ssl.create_default_context()
    with smtplib.SMTP(args.smtp, args.port) as server:
        server.ehlo()  # Can be omitted
        server.starttls(context=context)
        server.ehlo()  # Can be omitted
        server.login(args.user, args.password)
        server.sendmail(args.sender, args.recipient, msg.as_string())

if __name__ == '__main__':
    sendMail(None)
