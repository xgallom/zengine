#!/bin/bash

printf "Building SDL3 Shadercross\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SDIR="$PWD"
PDIR="$PWD/external/SDL_shadercross"
BDIR="$PDIR/build"
IDIR="$PWD/external/build"

mkdir -p "$BDIR"
mkdir -p "$IDIR"

cd "$PDIR"
git submodule update --init --recursive

cd "$BDIR"

CMAKE_INSTALL_PREFIX="$IDIR" cmake .. $2 \
	-DCMAKE_BUILD_TYPE=${1:-Debug} \
	-DCMAKE_FIND_PACKAGE_REDIRECTS_DIR="$IDIR/lib/cmake" \
	-DSDLSHADERCROSS_VENDORED=ON \
	-DBUILD_SHARED_LIBS=ON \
	-DSDLSHADERCROSS_INSTALL=ON \

make $3
make install $4

cd "$SDIR"
printf "\n\n"
