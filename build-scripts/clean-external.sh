#!/bin/bash

source "$PWD/build-scripts/clean-sdl.sh"
source "$PWD/build-scripts/clean-shadercross.sh"
source "$PWD/build-scripts/clean-sdl_image.sh"
source "$PWD/build-scripts/clean-cimgui.sh"
source "$PWD/build-scripts/clean-cimplot.sh"

printf "Cleaning external\n"
rm -rf "$PWD/external/build"
