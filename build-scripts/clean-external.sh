#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

source "$ROOT_DIR/build-scripts/clean-cache.sh"

printf "\nCleaning external\n"
rm -rf "$ROOT_DIR/external/build"
