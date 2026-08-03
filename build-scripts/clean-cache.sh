#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

printf "\nCleaning cache\n"
source "$ROOT_DIR/build-scripts/clean-sdl.sh"
source "$ROOT_DIR/build-scripts/clean-shadercross.sh"
source "$ROOT_DIR/build-scripts/clean-sdl_image.sh"
source "$ROOT_DIR/build-scripts/clean-sdl_mixer.sh"
source "$ROOT_DIR/build-scripts/clean-sdl_ttf.sh"
source "$ROOT_DIR/build-scripts/clean-cimgui.sh"
source "$ROOT_DIR/build-scripts/clean-cimplot.sh"
