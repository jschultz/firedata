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

help='Use whisper.cpp to transcribe an audio file to a lrc file'
args=(
# "-short:--long:variable:default:description:flags"
  ":--debug:::Debug execution:flag"
  
  "-l:--logfile:::Log file to record processing, defaults to filename with extension '.log':private"
  ":--nologfile:::Don't write a log file:private,flag"
  ":--nobackup:::Don't back up existing output file:private,flag"
  
  "-x:--executable::whisper-cli:Whisper executable:"
  "-m:--model::ggml-large-v3-turbo.bin:Whisper model to use:"
  "-t:--threads::4:Number of threads to use"
  "-d:--directory:::Directory to place output file; otherwise same directory as audio file"
  "-O:--overwrite::false:Overwrite output file with matching timestampe:flag"

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

if [[ "${overwrite}" == "false" ]] \
&& [[ -f "${outfile}.lrc" ]] \
&& [[ "$(date -r "${outfile}.lrc")" == "$(date -r "${filename}")" ]];
then
    echo "Output file ${outfile}.lrc already exists" >&2
else
    # Look for model file
    if [[ ! -f ""${model}"" ]];
    then
        modeldir=""$(dirname "$(readlink -f "$(which "${executable}")")")""
        while [[ "${modeldir}" != "/" ]];
        do
            if [[ -f "${modeldir}"/models/"${model}" ]];
            then
                model="${modeldir}"/models/"${model}"
                break
            else
                modeldir="$(dirname "${modeldir}")"
            fi
        done
    fi
    if [[ ! -f ""${model}"" ]];
    then
        echo "Model \"${model}\" could not be found" >&2
        exit 1
    fi

    echo "Transcribing file ${filename} to ${outfile}.lrc" >&2
    if [[ "${debug}" == "true" ]]; then
        ${executable} --threads ${threads} --output-lrc --model "${model}" --output-file "${outfile}" "${filename}"
    else
        ${executable} --threads ${threads} --output-lrc --model "${model}" --output-file "${outfile}" "${filename}" 2> /dev/null
    fi
    touch "${outfile}.lrc" --reference="${filename}"
fi
