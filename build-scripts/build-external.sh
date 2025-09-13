#!/bin/bash

git submodule update --init --recursive

source "$PWD/build-scripts/build-sdl.sh"
source "$PWD/build-scripts/build-shadercross.sh"
source "$PWD/build-scripts/build-cimgui.sh"
