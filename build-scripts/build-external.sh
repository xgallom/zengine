#!/bin/bash

git submodule update --init --recursive
printf "\n"

source "$PWD/build-scripts/build-sdl.sh"
source "$PWD/build-scripts/build-sdl_image.sh"
source "$PWD/build-scripts/build-shadercross.sh"
source "$PWD/build-scripts/build-cimgui.sh"
source "$PWD/build-scripts/build-cimplot.sh"
