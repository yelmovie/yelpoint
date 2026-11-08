#!/bin/sh
set -eu
# REA's launcher validates the physical external SSD and mounts its APFS image.
. '/Volumes/T7 Shield/rea/bin/rea-env.sh'
export YELPOINT_ROOT='/Volumes/T7 Shield/rea/spotmouse'
export YELPOINT_BUILD='/Volumes/REA/cache/yelpoint-build'
mkdir -p "$YELPOINT_BUILD/tmp" "$YELPOINT_BUILD/home" "$YELPOINT_BUILD/swift" "$YELPOINT_BUILD/clang"
export TMPDIR="$YELPOINT_BUILD/tmp/" TMP="$YELPOINT_BUILD/tmp" TEMP="$YELPOINT_BUILD/tmp"
export CFFIXED_USER_HOME="$YELPOINT_BUILD/home"
export CLANG_MODULE_CACHE_PATH="$YELPOINT_BUILD/clang"
export SWIFT_MODULECACHE_PATH="$YELPOINT_BUILD/swift"
export DOTNET_CLI_HOME="$YELPOINT_BUILD/home"
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="$YELPOINT_BUILD/dotnet-bundles"
export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export NUGET_PACKAGES="$YELPOINT_BUILD/nuget"
