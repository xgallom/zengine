#!/bin/bash

printf "Building SDL3 TTF\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

SDIR="$ROOT_DIR"
PDIR="$ROOT_DIR/external/SDL_ttf"
BDIR="$PDIR/build"
IDIR="$ROOT_DIR/external/build"

mkdir -p "$BDIR"
mkdir -p "$IDIR"

cd "$PDIR"
git submodule update --init --recursive

cd "$BDIR"

cmake .. $2 \
    -DCMAKE_INSTALL_PREFIX="$IDIR" \
	-DCMAKE_BUILD_TYPE=${1:-Debug} \
	-DCMAKE_FIND_PACKAGE_REDIRECTS_DIR="$IDIR/lib/cmake" \
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DSDLTTF_VENDORED=ON \
	-DSDLTTF_HARFBUZZ=ON \
	-DSDLTTF_FREETYPE=ON \
	-DBUILD_SHARED_LIBS=ON \
	-DSDLTTF_BUILD_SHARED_LIBS=ON \
	-DSDLTTF_INSTALL=ON \

cmake --build . -- $3
cmake --install . $4

cd "$SDIR"
printf "\n\n"
