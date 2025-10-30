#!/bin/bash

printf "Building cimplot\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SDIR="$PWD"
PDIR="$PWD/external/cimplot"
BDIR="$PWD/external/cimplot-build/build"
IDIR="$PWD/external/build"

mkdir -p "$BDIR"
mkdir -p "$IDIR"

cd "$PDIR"
git submodule update --init --recursive

cd "$BDIR"

CMAKE_INSTALL_PREFIX="$IDIR" cmake .. $2 \
	-DCMAKE_BUILD_TYPE=${1:-Debug} \
	-DCMAKE_FIND_PACKAGE_REDIRECTS_DIR="$IDIR/lib/cmake" \
	-DIMGUI_USER_CONFIG="$PWD/external/cimgui/cimconfig.h" \

make $3
make install $3

cd "$SDIR"
printf "\n\n"
