#!/bin/bash

printf "Building cimplot\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

SDIR="$ROOT_DIR"
PDIR="$ROOT_DIR/external/cimplot"
BDIR="$ROOT_DIR/external/cimplot-build/build"
IDIR="$ROOT_DIR/external/build"

mkdir -p "$BDIR"
mkdir -p "$IDIR"

cd "$PDIR"
git submodule update --init --recursive --depth 1

cd "$BDIR"

cmake .. $2 \
    -DCMAKE_INSTALL_PREFIX="$IDIR" \
	-DCMAKE_BUILD_TYPE=${1:-Debug} \
	-DCMAKE_FIND_PACKAGE_REDIRECTS_DIR="$IDIR/lib/cmake" \
	-DIMGUI_USER_CONFIG="$ROOT_DIR/external/cimgui/cimconfig.h" \

cmake --build . -- $3
cmake --install . $4

cd "$SDIR"
printf "\n\n"
