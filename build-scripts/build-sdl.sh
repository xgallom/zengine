#!/bin/bash

printf "Building SDL3\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

SDIR="$ROOT_DIR"
PDIR="$ROOT_DIR/external/SDL"
BDIR="$PDIR/build"
IDIR="$ROOT_DIR/external/build"

mkdir -p "$BDIR"
mkdir -p "$IDIR"

cd "$PDIR"
git submodule update --init --recursive

cd "$BDIR"

CMAKE_INSTALL_PREFIX="$IDIR" cmake .. $2 \
	-DCMAKE_BUILD_TYPE=${1:-Debug} \
	-DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
	-DSDL_VULKAN=ON -DSDL_RENDER_VULKAN=ON \
	-DSDL_TEST_LIBRARY=OFF \

cmake --build . -- $3
cmake --install . $4

cd "$SDIR"
printf "\n\n"
