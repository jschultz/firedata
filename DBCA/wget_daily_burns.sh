#!/bin/sh
wget -O daily_burns_$(date --iso-8601).csv https://kmi.dpaw.wa.gov.au/geoserver/wfs?service=wfs\&version=2.0.0\&request=GetFeature\&outputFormat=csv\&typeNames=public:daily_burns
