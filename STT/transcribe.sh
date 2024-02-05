#!/bin/bash
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
#
set -e

help='Use whisper.cpp to transcribe an audio file to a lrc file'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  
  "-l:--logfile:::Log file to record processing, defaults to filename with extension '.log':private"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--nobackup:::Don't back up existing output file:private,flag"
  
  "-x:--executable::main-openvino:Whisper executable:"
  "-m:--model::ggml-large.bin:Whisper model to use:"
  "-t:--threads::4:Number of threads to use"
  "-d:--directory:::Directory to place output file; otherwise same directory as audio file"
  "-O:--overwrite:::OK to overwrite output file:flag"

  ":filename:::Name of audio file to transcribe:input,required"
  
)

source $(dirname "$0")/argparse.sh

filebasename=$(basename "${filename}")

if [[ "${nologfile}" != "true" ]]; then
    if [[ ! -n "${logfile}" ]]; then
        logfile="${filebasename%.*}.log"
    fi
    echo -n "${COMMENTS}" > "${logfile}"
fi

if [[ "${debug}" == "true" ]]; then
    set -x
fi

wavfile="${filename%.*}.wav"
if [[ -n ${directory} ]]; then
    outfile="${directory}/$(basename ${filename%.*})"
else
    outfile="${filename%.*}"
fi

if [[ (! -f "${outfile}.lrc") || "$(date -r ${outfile}.lrc)" != "$(date -r ${filename})" || "${overwrite}" == "true" ]]; then
     ffmpeg -y -hide_banner -i "${filename}" -ac 1 -ar 16000 "${filename%.*}.16k.wav"
    ${executable} --threads ${threads} --output-lrc --model $HOME/src/whisper.cpp/models/${model} --output-file "${outfile}" "${filename%.*}.16k.wav"
    rm "${filename%.*}.16k.wav"
    touch "${outfile}.lrc" --reference="${filename}"
else
    echo "WARNING: Output file ${filename%.*}.lrc already exists - transcription skipped" > /dev/stderr
fi
