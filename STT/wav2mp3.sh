#!/bin/bash
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
#
set -e

help='Use lame to compress audio files to a mp3 file, checking for already existing file and optionally removing old file'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"

  "-l:--logfile:::Log file to record processing, defaults to filename with extension '.log':private"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--trash:::Trash original file on success:private,flag"

#   "-p:--preset::voice:lame preset to use"
  "-b:--bitrate::64k:Output bitrate"

  "-d:--directory:::Directory to place output file; otherwise same directory as audio file"
#   "-O:--overwrite:::OK to overwrite output file:flag"

  ":filename:::Name of audio file to transcribe:input,required"

)

source $(dirname "$0")/argparse.sh

filebasename=$(basename ${filename})

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        logfile="${filebasename%.*}.log"
    fi
    echo -n "${COMMENTS}" > "${logfile}"
fi

if [[ "${debug}" == "true" ]]; then
    set -x
fi

if [[ -n ${directory} ]]; then
    outfile="${directory}/$(basename ${filename%.*}).mp3"
else
    outfile="${filename%.*}.mp3"
fi

if [[ -f "${outfile}" ]] \
&& [[ "$(date -r "${outfile}")" == "$(date -r "${filename}")" ]] \
&& (( $(echo $(mediainfo --inform="Audio;%Duration%" "${outfile}") '>=' $(mediainfo --inform="Audio;%Duration%" "${filename}") | bc -l) ));
then
    echo "Output file ${outfile} already exists" > /dev/stderr
else
    echo "Encoding file ${filename} to ${outfile}" > /dev/stderr
# 2025-11-06 lame seems to have gone buggy. Complaints about ReplayGain
#     lame --quiet --preset ${preset} ${filename} ${outfile}
    ffmpeg -i ${filename} -b:a ${bitrate} -y ${outfile}
    touch "${outfile}" --reference="${filename}"
fi

if [[ -f "${outfile}" ]] \
&& [[ "$(date -r "${outfile}")" == "$(date -r "${filename}")" ]] \
&& (( $(echo $(mediainfo --inform="Audio;%Duration%" "${outfile}") '>=' $(mediainfo --inform="Audio;%Duration%" "${filename}") | bc -l) ));
then
    if [[ "${trash}" == "true" ]]; then
        echo "Moving file ${filename} to $HOME/Trash"
        mv "${filename}" $HOME/Trash
    fi
else
    echo "ERROR: output file ${outfile} mismatch"
    exit
fi
