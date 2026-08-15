#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

cd "$ROOT_DIR"
git submodule update --init --recursive --depth 1

printf "\nBuilding target ${1:-Debug}\n"
printf "cmake args:        \"$2\"\n"
printf "make args:         \"$3\"\n"
printf "make install args: \"$4\"\n\n"

source "$ROOT_DIR/build-scripts/build-sdl.sh" "$@"
source "$ROOT_DIR/build-scripts/build-sdl_image.sh" "$@"
source "$ROOT_DIR/build-scripts/build-sdl_mixer.sh" "$@"
source "$ROOT_DIR/build-scripts/build-sdl_ttf.sh" "$@"
source "$ROOT_DIR/build-scripts/build-shadercross.sh" "$@"
source "$ROOT_DIR/build-scripts/build-cimgui.sh" "$@"
source "$ROOT_DIR/build-scripts/build-cimplot.sh" "$@"
