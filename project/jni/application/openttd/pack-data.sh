#!/usr/bin/env bash

set -e

VER=12.2-0
GFX_VERSION=7.1
SFX_VERSION=1.0.3
MSX_VERSION=0.4.2
ARCH=$1
ANDROID_DATA_FULLPATH=$(realpath ./AndroidData/)

# Base game data
pushd ./data
rm -f ${ANDROID_DATA_FULLPATH}/openttd-data-*.zip.xz ${ANDROID_DATA_FULLPATH}/openttd-data-*.zip

pushd ./baseset
curl --fail https://cdn.openttd.org/opengfx-releases/${GFX_VERSION}/opengfx-${GFX_VERSION}-all.zip | jar xv
curl --fail https://cdn.openttd.org/opensfx-releases/${SFX_VERSION}/opensfx-${SFX_VERSION}-all.zip | jar xv
curl --fail https://cdn.openttd.org/openmsx-releases/${MSX_VERSION}/openmsx-${MSX_VERSION}-all.zip | jar xv
tar xvf ./openmsx-${MSX_VERSION}.tar && rm ./openmsx-${MSX_VERSION}.tar
popd

zip -0 -r ${ANDROID_DATA_FULLPATH}/openttd-data-$VER.zip ./ && xz -8 ${ANDROID_DATA_FULLPATH}/openttd-data-$VER.zip
popd

# Timidity
pushd ../../timidity/samples/
rm -f ${ANDROID_DATA_FULLPATH}/timidity.zip.xz ${ANDROID_DATA_FULLPATH}/timidity.zip
cp ./timidity.zip ${ANDROID_DATA_FULLPATH}/timidity.zip && xz -8 ${ANDROID_DATA_FULLPATH}/timidity.zip
popd

# ICU
# TODO handle versioning. Use Makefile var
pushd ../../iconv/src/$ARCH/
rm -f ${ANDROID_DATA_FULLPATH}/icudt62l.zip.xz ${ANDROID_DATA_FULLPATH}/icudt62l.zip
zip -0 ${ANDROID_DATA_FULLPATH}/icudt62l.zip share/icu/62.1/icudt62l.dat && xz -8 ${ANDROID_DATA_FULLPATH}/icudt62l.zip
popd

# Fonts
pushd ../../freetype/
rm -f ${ANDROID_DATA_FULLPATH}/openttd-fonts.zip.xz ${ANDROID_DATA_FULLPATH}/openttd-fonts.zip
zip -0 -r ${ANDROID_DATA_FULLPATH}/openttd-fonts.zip ./fonts/ && xz -8 ${ANDROID_DATA_FULLPATH}/openttd-fonts.zip
popd
