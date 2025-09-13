#!/bin/bash

printf "Building cimgui\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SDIR="$PWD"
PDIR="$PWD/external/cimgui"
BDIR="$PWD/external/cimgui-build/build"
IDIR="$PWD/external/build"

mkdir -p "$BDIR"
mkdir -p "$IDIR"

cd "$PDIR"
git submodule update --init --recursive

cd "$BDIR"

CMAKE_INSTALL_PREFIX="$IDIR" cmake .. \
	-DCMAKE_FIND_PACKAGE_REDIRECTS_DIR="$IDIR/lib/cmake" \
	-Dcimgui_SOURCE_DIR="$PDIR" \

make -j 8
make install

cd "$SDIR"
printf "\n\n"
