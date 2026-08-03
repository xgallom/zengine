#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."

printf "Cleaning cimplot\n"
rm -rf "$ROOT_DIR/external/cimplot-build/build"
