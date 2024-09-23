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

import smtplib, ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
from email.mime.base import MIMEBase
from email import encoders
from io import StringIO
import pandas

port = 587  # For starttls
smtp_server = "smtp.zoho.com.au"
sender_email = "info@fabwa.org.au"
# recipients = ["jonathan@schultz.la", "segoluke@tutanota.com"]
recipients = ["jonathan@schultz.la"]
password = "3kLtgQ8qLhvH"

msg = MIMEMultipart()
msg['Subject'] = "Daily burns"

text = ""
while True:
    try:
        line=input("")
    except EOFError:
        break

    text += line + "\n"

csvStringIO = StringIO(text)
table_html = pandas.read_csv(csvStringIO).to_html()
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
# msg.attach(MIMEText(text, 'plain'))
msg.attach(MIMEText(html, 'html'))

# part = MIMEApplication(
#     text,
#     Name='daily_burns.csv'
# )
# part['Content-Disposition'] = 'attachment; filename="%s"' % 'daily_burns.csv'
# msg.attach(part)

part = MIMEBase('application', "octet-stream")
part.set_payload(text)
encoders.encode_base64(part)
part.add_header('Content-Disposition',
                'attachment; filename=daily_burns.csv')
msg.attach(part)

context = ssl.create_default_context()
with smtplib.SMTP(smtp_server, port) as server:
    server.ehlo()  # Can be omitted
    server.starttls(context=context)
    server.ehlo()  # Can be omitted
    server.login(sender_email, password)
    server.sendmail(sender_email, recipients, msg.as_string())
