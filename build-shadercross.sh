#!/bin/bash

B_DIR="./SDL"
B_CC="`which zig` cc"
B_CXX="`which zig` c++"

mkdir -p "$B_DIR/build"
cd "$B_DIR/build"
rm -rf ./*

cmake .. \
	-DSDLSHADERCROSS_VENDORED=ON \
	-DBUILD_SHARED_LIBS=ON

make -j 8

cd ../..

