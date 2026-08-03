#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

printf "Cleaning SDL3 Mixer\n"
rm -rf "$ROOT_DIR/external/SDL_mixer/build"
