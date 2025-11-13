#!/bin/bash

printf "\nCleaning cache\n"
source "$PWD/build-scripts/clean-sdl.sh"
source "$PWD/build-scripts/clean-shadercross.sh"
source "$PWD/build-scripts/clean-sdl_image.sh"
source "$PWD/build-scripts/clean-sdl_ttf.sh"
source "$PWD/build-scripts/clean-cimgui.sh"
source "$PWD/build-scripts/clean-cimplot.sh"
