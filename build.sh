#!/usr/bin/env bash

# Handle any error or die
set -e

THIS_BUILD_DIR=$(dirname "$0")
install_apk=false
run_apk=false
sign_apk=false
sign_bundle=false
build_release=true
[ -z "$ANDROID_SDK_ROOT" ] && ANDROID_SDK_ROOT="$ANDROID_HOME"

# Check environment before continuing
if ! $(which adb zipalign apksigner jarsigner ndk-build java cmake > /dev/null); then
	echo "One of the follow binaries is missing. Check your environment";
	echo "adb arch zipalign apksigner jarsigner ndk-build java cmake";
	exit 1;
fi

JAVA_MVERSION=$(java --version 2>&1 | awk 'NR == 1{print $2}' | awk -F . '{print $1}')
if [ $JAVA_MVERSION -lt 11 ]; then
	echo "Java version equal or above to 11 necessary.";
	exit 2;
	if [ $JAVA_MVERSION -gt 11 ]; then
		echo "Java 11 version is strongly recomended.";
	fi
fi

while getopts "sirqbh" OPT
do
	case $OPT in
		s) sign_apk=true;;
		i) install_apk=true;;
		r) install_apk=true ; run_apk=true;;
		q) echo "Quick rebuild does not work anymore with Gradle!";;
		b) sign_bundle=true;;
		h)
			echo "Usage: $0 [-s] [-i] [-r] [-q] [debug|release] [app-name]"
			echo "    -s:       sign .apk file after building"
			echo "    -b:       sign .aab app bundle file after building"
			echo "    -i:       install APK file to device after building"
			echo "    -r:       run APK file on device after building"
			echo "    debug:    build debug package"
			echo "    release:  build release package (default)"
			echo "    app-name: directory under project/jni/application to be compiled"
			exit 0
			;;
	esac
done
shift $(expr $OPTIND - 1)

if [ "$#" -gt 0 -a "$1" = "release" ]; then
	shift
	build_release=true
fi

if [ "$#" -gt 0 -a "$1" = "debug" ]; then
	shift
	build_release=false
	export NDK_DEBUG=1
fi

if [ "$#" -gt 0 ]; then
	echo "Switching build target to $1"
	if [ -e project/jni/application/$1 ]; then
		rm -f project/jni/application/src
		ln -s "$1" project/jni/application/src
	else
		echo "Error: no app $1 under project/jni/application"
		echo "Available applications:"
		pushd project/jni/application
		for f in *; do
			if [ -e "$f/AndroidAppSettings.cfg" ]; then
				echo "$f"
			fi
		done
		popd
		exit 1
	fi
	shift
fi

if ! [ -e project/local.properties ] && \
	grep "package $(grep -Po 'AppFullName\=\K[.[:alnum:]]+' AndroidAppSettings.cfg);" project/src/Globals.java > /dev/null 2>&1 && \
	[ "$(readlink AndroidAppSettings.cfg)" -ot "project/src/Globals.java" ] && \
	[ -z "$(find project/java/* \
				project/javaSDL2/* \
				project/jni/sdl2/android-project/app/src/main/java/org/libsdl/app/* \
				project/AndroidManifestTemplate.xml \
			-cnewer \
				project/src/Globals.java \
		)"
	];
then
	./changeAppSettings.sh -a
	sleep 1
	touch project/src/Globals.java
fi

MYARCH=linux-x86_64
if [ -z "$NCPU" ]; then
	NCPU=8
	if uname -s | grep -i "linux" > /dev/null ; then
		MYARCH=linux-x86_64
		NCPU=$(cat /proc/cpuinfo | grep -c -i processor)
	fi
	if uname -s | grep -i "darwin" > /dev/null ; then
		MYARCH=darwin-x86_64
	fi
	if uname -s | grep -i "windows" > /dev/null ; then
		MYARCH=windows-x86_64
	fi
fi
export BUILD_NUM_CPUS=$NCPU

# Fix Gradle compilation error
if [ -z "$ANDROID_NDK_HOME" ]; then
	export ANDROID_NDK_HOME="$(which ndk-build | sed 's@/ndk-build@@')"
fi

if [ -x project/jni/application/src/AndroidPreBuild.sh ]; then
	pushd project/jni/application/src
	./AndroidPreBuild.sh
	popd
fi

if grep -q 'CustomBuildScript=y' ./AndroidAppSettings.cfg; then
	ndk-build -C project -j$NCPU V=1 CUSTOM_BUILD_SCRIPT_FIRST_PASS=1 NDK_APP_STRIP_MODE=none
	make -C project/jni/application -f CustomBuildScript.mk
fi

ndk-build -C project -j$NCPU V=1 NDK_APP_STRIP_MODE=none
./copyAssets.sh
pushd project
if $build_release ; then
	./gradlew assembleRelease
	if [ ! -x jni/application/src/AndroidPostBuild.sh ]; then
		pushd jni/application/src
		./AndroidPostBuild.sh ${THIS_BUILD_DIR}/project/app/build/outputs/apk/release/app-release-unsigned.apk
		popd
	fi
	../copyAssets.sh pack-binaries app/build/outputs/apk/release/app-release-unsigned.apk
	rm -f app/build/outputs/apk/release/app-release.apk
	zipalign -p 4 app/build/outputs/apk/release/app-release-unsigned.apk app/build/outputs/apk/release/app-release.apk
	apksigner sign --ks ~/.android/debug.keystore --ks-key-alias androiddebugkey --ks-pass pass:android app/build/outputs/apk/release/app-release.apk
else
	./gradlew assembleDebug
	if [ ! -x jni/application/src/AndroidPostBuild.sh ]; then
		pushd jni/application/src
		./AndroidPostBuild.sh ${THIS_BUILD_DIR}/project/app/build/outputs/apk/debug/app-debug.apk
		popd
	fi
	mkdir -p app/build/outputs/apk/release
	../copyAssets.sh pack-binaries app/build/outputs/apk/debug/app-debug.apk
	rm -f app/build/outputs/apk/release/app-release.apk
	zipalign -p 4 app/build/outputs/apk/debug/app-debug.apk app/build/outputs/apk/release/app-release.apk
	apksigner sign --ks ~/.android/debug.keystore --ks-key-alias androiddebugkey --ks-pass pass:android app/build/outputs/apk/release/app-release.apk
fi

if $sign_apk; then
	pushd ..
	./sign.sh
	popd
fi

if $sign_bundle; then
	pushd ..
	./signBundle.sh
	popd
fi
if $install_apk && [ -n "$(adb devices | tail -n +2)" ]; then
	if $sign_apk; then
		APPNAME=$(grep AppName ../AndroidAppSettings.cfg | sed 's/.*=//' | tr -d '"' | tr " '/" '---')
		APPVER=$(grep AppVersionName ../AndroidAppSettings.cfg | sed 's/.*=//' | tr -d '"' | tr " '/" '---')
		adb install -r ../$APPNAME-$APPVER.apk ;
	else
		adb install -r app/build/outputs/apk/release/app-release.apk
	fi
fi

if $run_apk; then
	ActivityName="$(grep AppFullName ../AndroidAppSettings.cfg | sed 's/.*=//')/.MainActivity"
	RUN_APK="adb shell am start -n $ActivityName"
	echo "Running $ActivityName on the USB-connected device:"
	echo "$RUN_APK"
	eval $RUN_APK
fi
