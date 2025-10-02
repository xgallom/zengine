#!/bin/bash

printf "Building SDL3 TTF\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SDIR="$PWD"
PDIR="$PWD/external/SDL_ttf"
BDIR="$PDIR/build"
IDIR="$PWD/external/build"

mkdir -p "$BDIR"
mkdir -p "$IDIR"

cd "$PDIR"
git submodule update --init --recursive

cd "$BDIR"

CMAKE_INSTALL_PREFIX="$IDIR" cmake .. \
	-DCMAKE_FIND_PACKAGE_REDIRECTS_DIR="$IDIR/lib/cmake" \
	-DSDLTTF_VENDORED=ON \
	-DBUILD_SHARED_LIBS=ON \
	-DSDLTTF_INSTALL=ON \

make -j 8
make install

cd "$SDIR"
printf "\n\n"
