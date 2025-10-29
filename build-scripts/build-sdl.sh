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

CMAKE_INSTALL_PREFIX="$IDIR" cmake .. "$@" \
	-DCMAKE_BUILD_TYPE=$1 \
	-DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
	-DSDL_VULKAN=ON -DSDL_RENDER_VULKAN=ON \
	-DSDL_TEST_LIBRARY=OFF \

make -j8
make install

cd "$SDIR"
printf "\n\n"
