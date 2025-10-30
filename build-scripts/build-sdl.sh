#!/bin/bash

printf "Building SDL3\n"
printf -- "----------------------------------------------------------------------------------------------------\n\n"

SDIR="$PWD"
PDIR="$PWD/external/SDL"
BDIR="$PDIR/build"
IDIR="$PWD/external/build"

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

make $3
make install $4

cd "$SDIR"
printf "\n\n"
