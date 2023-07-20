#!/bin/bash
set -e
DUMP=/share/wrf/workdir_dump
SCRATCH_WDIR=/scratch/wrf/workdir

function log() {
   echo -n `date -u '+%Y-%m-%d %H:%M:%S'`' '
   echo "$*"
}

log Removing old content from $DUMP

if [ -d $DUMP ]; then 
   rm -vr $DUMP
fi

log Copy working directory to $DUMP
cp -rvp $SCRATCH_WDIR $DUMP
