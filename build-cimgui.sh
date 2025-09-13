#!/bin/bash

B_DIR="./cimgui"
B_CC="`which zig` cc"
B_CXX="`which zig` c++"

mkdir -p "$B_DIR/build"
cd "$B_DIR/build"
rm -rf ./*

cmake ../backend_test/example_sdlgpu3

make -j 8

cp libcimgui_with_backend.dylib libcimgui.dylib

cd ../..

