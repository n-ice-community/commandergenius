#!/bin/sh

mkdir -p build-tools
[ -e build-tools/Makefile ] || ${CMAKE_BIN_LOC}cmake -DOPTION_TOOLS_ONLY=ON -B build-tools src
make -C build-tools -j8 VERBOSE=1 || exit 1
