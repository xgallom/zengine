#!/bin/bash

printf "Building SDL3 Mixer\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

SDIR="$ROOT_DIR"
PDIR="$ROOT_DIR/external/SDL_mixer"
BDIR="$PDIR/build"
IDIR="$ROOT_DIR/external/build"

mkdir -p "$BDIR"
mkdir -p "$IDIR"

cd "$PDIR"
git submodule update --init --recursive

cd "$BDIR"

CMAKE_INSTALL_PREFIX="$IDIR" cmake .. $2 \
	-DCMAKE_BUILD_TYPE=${1:-Debug} \
	-DCMAKE_FIND_PACKAGE_REDIRECTS_DIR="$IDIR/lib/cmake" \
	-DSDLMIXER_VENDORED=ON \
	-DBUILD_SHARED_LIBS=ON \
	-DSDL_INSTALL_EXAMPLES=OFF \
	-DSDLMIXER_TESTS_INSTALL=OFF \
	-DSDLMIXER_INSTALL=ON \

cmake --build . -- $3
cmake --install . $4

cd "$SDIR"
printf "\n\n"
