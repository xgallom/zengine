#!/bin/bash

source "$PWD/build-scripts/clean-cache.sh"

printf "\naCleaning external\n"
rm -rf "$PWD/external/build"
