#!/bin/bash

dir=`pwd`

cd ffmpeg
git checkout n5.1.4
cd ..

# set up the build directory
mkdir -p build
cd build

mkdir -p wasm
cd wasm

mkdir -p root
mkdir -p ffmpeg
cd ffmpeg


CONF_FLAGS=(
  --target-os=none              # disable target specific configs
  --arch=x86_32                 # use x86_32 arch
  --enable-cross-compile        # use cross compile configs
  --disable-asm                 # disable asm
  --disable-stripping           # disable stripping as it won't work
  --disable-programs            # disable ffmpeg, ffprobe and ffplay build
  --disable-doc                 # disable doc build
  --disable-debug               # disable debug mode
  --disable-runtime-cpudetect   # disable cpu detection
  --disable-autodetect          # disable env auto detect

  # assign toolchains and extra flags
  --nm=emnm
  --ar=emar
  --ranlib=emranlib
  --cc=emcc
  --cxx=em++
  --objcc=emcc
  --dep-cc=emcc
  #--extra-cflags="$CFLAGS"
  --extra-cflags=-DWASM\ -I`dirname \`which emcc\``/system/lib/libcxxabi/include/ \
  --extra-cxxflags="$CXXFLAGS"

  --disable-everything
  --disable-htmlpages
  --disable-manpages
  --disable-podpages
  --disable-txtpages
  --disable-network
  --disable-appkit
  --disable-coreimage
  --disable-metal
  --disable-sdl2
  --disable-securetransport
  --disable-vulkan
  --disable-audiotoolbox
  --disable-v4l2-m2m
  --disable-valgrind-backtrace
  --disable-large-tests
  
  --disable-avdevice
  --disable-avformat
  --disable-avfilter
  --disable-swresample
  --disable-swscale
  --disable-postproc
  --enable-avcodec
  --enable-decoder=h264
  --enable-decoder=hevc
  --enable-decoder=vp8
  --enable-decoder=vp9
  --enable-decoder=av1

  # disable thread when FFMPEG_ST is NOT defined
  --disable-pthreads
  --disable-w32threads
  --disable-os2threads

  --prefix="$dir/build/wasm/root"
)

# finally, run configuration script
EMCONFIGURE_JS=1 \
STRIP=./buildscripts/fake-strip.sh \
  emconfigure ../../../ffmpeg/configure "${CONF_FLAGS[@]}" $@  \
|| exit 1

# compile libvpx
emmake make -j4 || exit 1
emmake make install || exit 1

cd ..
cd ..
cd ..
