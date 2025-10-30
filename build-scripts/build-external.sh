#!/bin/bash

git submodule update --init --recursive

printf "\nBuilding target ${1:-Debug}\n"
printf "cmake args:        \"$2\"\n"
printf "make args:         \"$3\"\n"
printf "make install args: \"$4\"\n"

source "$PWD/build-scripts/build-sdl.sh" "$@"
source "$PWD/build-scripts/build-sdl_image.sh" "$@"
source "$PWD/build-scripts/build-sdl_ttf.sh" "$@"
source "$PWD/build-scripts/build-shadercross.sh" "$@"
source "$PWD/build-scripts/build-cimgui.sh" "$@"
source "$PWD/build-scripts/build-cimplot.sh" "$@"
