.mode csv
.headers on
.once Esperance.csv
SELECT stations."Station Number", "Station Name", "DateTime", 
    "Precipitation in mm",
    "Air temperature in Degrees C",
    "Dew point temperature in Degrees C",
    "Relative humidity in percentage %",
    "Wind speed measured in km/h",
    "Wind direction measured in degrees"
FROM observations JOIN stations on observations."Station Number" = stations."Station Number" 
WHERE
    ("Station Name" = "ESPERANCE" AND DateTime >= "2015-11-15" AND DateTime <= "2015-11-26") 
ORDER BY DateTime ASC ;
    
.once Bremer.csv
SELECT stations."Station Number", "Station Name", "DateTime", 
    "Precipitation in mm",
    "Air temperature in Degrees C",
    "Dew point temperature in Degrees C",
    "Relative humidity in percentage %",
    "Wind speed measured in km/h",
    "Wind direction measured in degrees"
FROM observations JOIN stations on observations."Station Number" = stations."Station Number" 
WHERE
    (("Station Name" = "JACUP" OR "Station Name" = "ONGERUP")
    AND DateTime >= "2018-12-20" AND DateTime <= "2019-01-03")
ORDER BY DateTime ASC ;
    
.once Waroona.csv
SELECT stations."Station Number", "Station Name", "DateTime", 
    "Precipitation in mm",
    "Air temperature in Degrees C",
    "Dew point temperature in Degrees C",
    "Relative humidity in percentage %",
    "Wind speed measured in km/h",
    "Wind direction measured in degrees"
FROM observations JOIN stations on observations."Station Number" = stations."Station Number"
WHERE
    ("Station Name" = "DWELLINGUP" AND DateTime >= "2016-01-05" AND DateTime <= "2016-01-09")
ORDER BY DateTime ASC ;

.once Northcliffe.csv
SELECT stations."Station Number", "Station Name", "DateTime", 
    "Precipitation in mm",
    "Air temperature in Degrees C",
    "Dew point temperature in Degrees C",
    "Relative humidity in percentage %",
    "Wind speed measured in km/h",
    "Wind direction measured in degrees"
FROM observations JOIN stations on observations."Station Number" = stations."Station Number" 
WHERE
    (("Station Name" = "SHANNON" OR "Station Name" = "WINDY HARBOUR" OR "Station Name" = "NORTH WALPOLE")
    AND DateTime >= "2015-01-29" AND DateTime <= "2015-02-09")
ORDER BY DateTime ASC ;
    
.once Stirlings.csv
SELECT stations."Station Number", "Station Name", "DateTime", 
    "Precipitation in mm",
    "Air temperature in Degrees C",
    "Dew point temperature in Degrees C",
    "Relative humidity in percentage %",
    "Wind speed measured in km/h",
    "Wind direction measured in degrees"
FROM observations JOIN stations on observations."Station Number" = stations."Station Number" 
WHERE
    (("Station Name" = "ALBANY AIRPORT" OR "Station Name" = "ONGERUP")
    AND DateTime >= "2019-12-26" AND DateTime <= "2020-01-06")
ORDER BY DateTime ASC ;
