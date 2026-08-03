#!/bin/bash

printf "Building SDL3 Shadercross\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

SDIR="$ROOT_DIR"
PDIR="$ROOT_DIR/external/SDL_shadercross"
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
	-DSDLSHADERCROSS_VENDORED=ON \
	-DBUILD_SHARED_LIBS=ON \
	-DSDLSHADERCROSS_CLI=OFF \
	-DSDLSHADERCROSS_INSTALL=ON \

cmake --build . -- $3
cmake --install . $4

cd "$SDIR"
printf "\n\n"
