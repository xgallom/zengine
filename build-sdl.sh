#!/bin/bash

B_DIR="./SDL"
B_CC="`which zig` cc"
B_CXX="`which zig` c++"

mkdir -p "$B_DIR/build"
cd "$B_DIR/build"
rm -rf ./*

cmake .. \
	-DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
	-DSDL_VULKAN=ON -DSDL_RENDER_VULKAN=ON

make -j 8

cd ../..

