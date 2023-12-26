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

import smtplib, ssl

port = 587  # For starttls
smtp_server = "smtp.zoho.com.au"
sender_email = "info@fabwa.org.au"
recipients = ["jonathan@schultz.la"]
password = "3kLtgQ8qLhvH"

message = "Subject: Daily burns\n\n"

while True:
    try:
        line=input("")
    except EOFError:
        break

    message += line + "\n"

context = ssl.create_default_context()
with smtplib.SMTP(smtp_server, port) as server:
    server.ehlo()  # Can be omitted
    server.starttls(context=context)
    server.ehlo()  # Can be omitted
    server.login(sender_email, password)
    server.sendmail(sender_email, recipients, message)
