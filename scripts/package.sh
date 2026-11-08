#!/bin/sh
set -eu
. '/Volumes/T7 Shield/rea/spotmouse/scripts/build-env.sh'
export YELPOINT_ROOT YELPOINT_BUILD
/usr/bin/python3 -B "$YELPOINT_ROOT/scripts/package.py"
