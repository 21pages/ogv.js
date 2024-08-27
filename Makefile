VERSION:=$(shell node tools/getversion.js ..)
BUILDDATE:=$(shell date -u "+%Y%m%d%H%M%S")
HASH:=$(shell git rev-parse --short HEAD)
FULLVER:=$(VERSION)-$(BUILDDATE)-$(HASH)

DEMO_DIR:=demo
TESTS_DIR:=tests
BUILDSCRIPTS_DIR:=buildscripts

AUDIO_DIR:=node_modules/audio-feeder

JS_SRC_DIR:=src/js
JS_FILES:=$(shell find $(JS_SRC_DIR) -type f -name "*.js")
JS_FILES+= $(shell find $(JS_SRC_DIR)/workers -type f -name "*.js")

EMSCRIPTEN_MODULE_TARGETS+= build/ogv-decoder-video-vp9-wasm.js
EMSCRIPTEN_MODULE_TARGETS+= build/ogv-decoder-video-vp9-mt-wasm.js

ifdef SIMD
EMSCRIPTEN_MODULE_TARGETS+= build/ogv-decoder-video-vp9-simd-wasm.js
EMSCRIPTEN_MODULE_TARGETS+= build/ogv-decoder-video-vp9-simd-mt-wasm.js
endif

EMSCRIPTEN_MODULE_SRC_DIR:=$(JS_SRC_DIR)/modules
EMSCRIPTEN_MODULE_FILES:=$(shell find $(EMSCRIPTEN_MODULE_SRC_DIR) -type f -name "*.js")
EMSCRIPTEN_MODULE_FILES+= $(shell find $(EMSCRIPTEN_MODULE_SRC_DIR) -type f -name "*.json")

C_SRC_DIR:=src/c
C_FILES:=$(shell find $(C_SRC_DIR) -type f -name "*.c")
C_FILES+= $(shell find $(C_SRC_DIR) -type f -name "*.h")

WASM_ROOT_BUILD_DIR:=build/wasm/root
WASMMT_ROOT_BUILD_DIR:=build/wasm-mt/root
WASMSIMD_ROOT_BUILD_DIR:=build/wasm-simd/root
WASMSIMDMT_ROOT_BUILD_DIR:=build/wasm-simd-mt/root

.PHONY : DEFAULT all clean js demo democlean tests dist zip lint run-demo run-dev-server

DEFAULT : all

# Runners

run-demo : package.json demo
	npm run demo

# This uses webpack dev server so we don't need to re-compile anything upon change - just reload the page
#
# 1. Run ``make run-dev-server
# 2. Go to http://localhost:8080/examples/simple/ in your browser to look at a simple example player
# 3. Reload the page to get the latest re-build
run-dev-server : package.json
	npm run server

# Build all

all : dist \
      zip \
      demo \
      tests

js : build/ogv.js $(EMSCRIPTEN_MODULE_TARGETS)

demo : build/demo/index.html

tests : build/tests/index.html

lint :
	npm run lint

package.json :
	npm install

build/ogv.js : webpack.config.js package.json $(JS_FILES)
	OGV_FULL_VERSION=$(FULLVER) npm run build

democlean:
	rm -rf build/demo

clean:
	rm -rf build
	rm -rf dist

# Build everything and copy the result into dist folder

dist: js README.md COPYING
	rm -rf dist
	mkdir -p dist
	chmod a-x build/*.wasm
	cp -p build/ogv.js \
	      build/ogv-es2017.js \
	      build/ogv-support.js \
	      build/ogv-version.js \
	      build/ogv-decoder-video-vp9-wasm.js \
	      build/ogv-decoder-video-vp9-wasm.wasm \
	      build/ogv-decoder-video-vp9-mt-wasm.js \
	      build/ogv-decoder-video-vp9-mt-wasm.wasm \
	      build/ogv-decoder-video-vp9-mt-wasm.worker.js \
	      build/ogv-worker-audio.js \
	      build/ogv-worker-video.js \
	      README.md \
	      COPYING \
	      dist/

	if [ "x$(SIMD)x" = "xx" ]; then \
		echo "Skipping SIMD, compile with 'make SIMD=1' if desired."; \
	else \
		cp -p build/ogv-decoder-video-av1-simd-wasm.js \
	          build/ogv-decoder-video-av1-simd-wasm.wasm \
		      build/ogv-decoder-video-av1-simd-mt-wasm.js \
	          build/ogv-decoder-video-av1-simd-mt-wasm.wasm \
		      build/ogv-decoder-video-av1-simd-mt-wasm.worker.js \
		      build/ogv-decoder-video-vp9-simd-wasm.js \
	          build/ogv-decoder-video-vp9-simd-wasm.wasm \
		      build/ogv-decoder-video-vp9-simd-mt-wasm.js \
	          build/ogv-decoder-video-vp9-simd-mt-wasm.wasm \
		      build/ogv-decoder-video-vp9-simd-mt-wasm.worker.js \
		      dist/ \
			  ; \
	fi

	cp -p libvpx/PATENTS dist/PATENTS-vpx.txt

# Zip up the dist folder for non-packaged release

zip: dist
	rm -rf zip
	mkdir -p zip/ogvjs-$(VERSION)
	cp -pr dist/* zip/ogvjs-$(VERSION)
	(cd zip && zip -r ogvjs-$(VERSION).zip ogvjs-$(VERSION))


# Build depending C libraries with Emscripten


$(WASM_ROOT_BUILD_DIR)/lib/libvpx.a : $(BUILDSCRIPTS_DIR)/compileVpxWasm.sh
	test -d build || mkdir -p build
	./$(BUILDSCRIPTS_DIR)/compileVpxWasm.sh

$(WASMMT_ROOT_BUILD_DIR)/lib/libvpx.a : $(BUILDSCRIPTS_DIR)/compileVpxWasmMT.sh
	test -d build || mkdir -p build
	./$(BUILDSCRIPTS_DIR)/compileVpxWasmMT.sh

$(WASMSIMD_ROOT_BUILD_DIR)/lib/libvpx.a : $(BUILDSCRIPTS_DIR)/compileVpxWasmSIMD.sh
	test -d build || mkdir -p build
	./$(BUILDSCRIPTS_DIR)/compileVpxWasmSIMD.sh

$(WASMSIMDMT_ROOT_BUILD_DIR)/lib/libvpx.a : $(BUILDSCRIPTS_DIR)/compileVpxWasmSIMDMT.sh
	test -d build || mkdir -p build
	./$(BUILDSCRIPTS_DIR)/compileVpxWasmSIMDMT.sh

# Compile our Emscripten modules

build/ogv-decoder-video-vp9-wasm.js : $(C_SRC_DIR)/ogv-decoder-video-vpx.c \
                                      $(C_SRC_DIR)/ogv-decoder-video.h \
     								 $(C_SRC_DIR)/ogv-thread-support.h \
                                      $(JS_SRC_DIR)/modules/ogv-decoder-video.js \
                                      $(JS_SRC_DIR)/modules/ogv-decoder-video-callbacks.js \
                                      $(JS_SRC_DIR)/modules/ogv-decoder-video-exports.json \
                                      $(JS_SRC_DIR)/modules/ogv-module-pre.js \
                                      $(WASM_ROOT_BUILD_DIR)/lib/libvpx.a \
                                      $(BUILDSCRIPTS_DIR)/compile-options.sh \
                                      $(BUILDSCRIPTS_DIR)/compileOgvDecoderVideoVP9.sh
	test -d build || mkdir -p build
	./$(BUILDSCRIPTS_DIR)/compileOgvDecoderVideoVP9.sh

build/ogv-decoder-video-vp9-mt-wasm.js : $(C_SRC_DIR)/ogv-decoder-video-vpx.c \
                                         $(C_SRC_DIR)/ogv-decoder-video.h \
                                         $(C_SRC_DIR)/ogv-thread-support.h \
                                         $(JS_SRC_DIR)/modules/ogv-decoder-video.js \
                                         $(JS_SRC_DIR)/modules/ogv-decoder-video-callbacks.js \
                                         $(JS_SRC_DIR)/modules/ogv-decoder-video-exports.json \
                                         $(JS_SRC_DIR)/modules/ogv-module-pre.js \
						                 $(WASMMT_ROOT_BUILD_DIR)/lib/libvpx.a \
                                         $(BUILDSCRIPTS_DIR)/compile-options.sh \
                                         $(BUILDSCRIPTS_DIR)/compileOgvDecoderVideoVP9MT.sh
	test -d build || mkdir -p build
	./$(BUILDSCRIPTS_DIR)/compileOgvDecoderVideoVP9MT.sh

build/ogv-decoder-video-vp9-simd-wasm.js : $(C_SRC_DIR)/ogv-decoder-video-vpx.c \
                                           $(C_SRC_DIR)/ogv-decoder-video.h \
                                           $(C_SRC_DIR)/ogv-thread-support.h \
                                           $(JS_SRC_DIR)/modules/ogv-decoder-video.js \
                                           $(JS_SRC_DIR)/modules/ogv-decoder-video-callbacks.js \
                                           $(JS_SRC_DIR)/modules/ogv-decoder-video-exports.json \
                                           $(JS_SRC_DIR)/modules/ogv-module-pre.js \
						                   $(WASMSIMD_ROOT_BUILD_DIR)/lib/libvpx.a \
                                           $(BUILDSCRIPTS_DIR)/compile-options.sh \
                                           $(BUILDSCRIPTS_DIR)/compileOgvDecoderVideoVP9SIMD.sh
	test -d build || mkdir -p build
	./$(BUILDSCRIPTS_DIR)/compileOgvDecoderVideoVP9SIMD.sh

build/ogv-decoder-video-vp9-simd-mt-wasm.js : $(C_SRC_DIR)/ogv-decoder-video-vpx.c \
                                              $(C_SRC_DIR)/ogv-decoder-video.h \
                                              $(C_SRC_DIR)/ogv-thread-support.h \
                                              $(JS_SRC_DIR)/modules/ogv-decoder-video.js \
                                              $(JS_SRC_DIR)/modules/ogv-decoder-video-callbacks.js \
                                              $(JS_SRC_DIR)/modules/ogv-decoder-video-exports.json \
                                              $(JS_SRC_DIR)/modules/ogv-module-pre.js \
						                      $(WASMSIMDMT_ROOT_BUILD_DIR)/lib/libvpx.a \
                                              $(BUILDSCRIPTS_DIR)/compile-options.sh \
                                              $(BUILDSCRIPTS_DIR)/compileOgvDecoderVideoVP9SIMDMT.sh
	test -d build || mkdir -p build
	./$(BUILDSCRIPTS_DIR)/compileOgvDecoderVideoVP9SIMDMT.sh

# Install dev dependencies

# The player demo, with the JS build
# NOTE: This is pretty much only about copying files around
# Note index.html.in is a template to force a cache-clear timestamp on the JS URL.

build/demo/index.html : $(DEMO_DIR)/index.html.in \
                        build/demo/threaded.php \
                        build/demo/demo.css \
                        build/demo/ajax-loader.gif \
                        build/demo/demo.js \
                        build/demo/iconfont.css \
                        build/demo/benchmark.html \
                        build/demo/codec-bench.html \
                        build/demo/minimal.html \
                        build/demo/media/ehren-paper_lights-96.opus \
                        build/demo/media/pixel_aspect_ratio.ogg \
                        build/demo/media/curiosity.ogv \
                        build/demo/media/llama-drama-av1.webm \
                        build/demo/lib/ogv.js
	test -d build/demo || mkdir -p build/demo
	sed 's/OGV_VERSION/$(FULLVER)/g' < $(DEMO_DIR)/index.html.in > build/demo/index.html

build/demo/threaded.php : $(DEMO_DIR)/threaded.php.in
	test -d build/demo || mkdir -p build/demo
	cat $(DEMO_DIR)/threaded.php.in > build/demo/threaded.php

build/demo/demo.css : $(DEMO_DIR)/demo.css $(DEMO_DIR)/controls.css
	test -d build/demo || mkdir -p build/demo
	cat $(DEMO_DIR)/demo.css $(DEMO_DIR)/controls.css > build/demo/demo.css

build/demo/ajax-loader.gif : $(DEMO_DIR)/ajax-loader.gif
	test -d build/demo || mkdir -p build/demo
	cp $(DEMO_DIR)/ajax-loader.gif build/demo/ajax-loader.gif

build/demo/demo.js : $(DEMO_DIR)/demo.js $(DEMO_DIR)/benchmark.js $(DEMO_DIR)/controls.js
	test -d build/demo || mkdir -p build/demo
	cat $(DEMO_DIR)/demo.js $(DEMO_DIR)/benchmark.js $(DEMO_DIR)/controls.js > build/demo/demo.js

build/demo/iconfont.css : $(DEMO_DIR)/iconfont.css
	test -d build/demo || mkdir -p build/demo
	cp $(DEMO_DIR)/iconfont.css build/demo/iconfont.css

build/demo/benchmark.html : $(DEMO_DIR)/benchmark.html
	test -d build/demo || mkdir -p build/demo
	cp $(DEMO_DIR)/benchmark.html build/demo/benchmark.html

build/demo/codec-bench.html : $(DEMO_DIR)/codec-bench.html
	test -d build/demo || mkdir -p build/demo
	cp $(DEMO_DIR)/codec-bench.html build/demo/codec-bench.html

build/demo/minimal.html : $(DEMO_DIR)/minimal.html.in
	test -d build/demo || mkdir -p build/demo
	sed 's/OGV_VERSION/$(FULLVER)/g' < $(DEMO_DIR)/minimal.html.in > build/demo/minimal.html

build/demo/media/ehren-paper_lights-96.opus : $(DEMO_DIR)/media/ehren-paper_lights-96.opus
	test -d build/demo/media || mkdir -p build/demo/media
	cp $(DEMO_DIR)/media/ehren-paper_lights-96.opus build/demo/media/ehren-paper_lights-96.opus

build/demo/media/pixel_aspect_ratio.ogg : $(DEMO_DIR)/media/pixel_aspect_ratio.ogg
	test -d build/demo/media || mkdir -p build/demo/media
	cp $(DEMO_DIR)/media/pixel_aspect_ratio.ogg build/demo/media/pixel_aspect_ratio.ogg

build/demo/media/curiosity.ogv : $(DEMO_DIR)/media/curiosity.ogv
	test -d build/demo/media || mkdir -p build/demo/media
	cp $(DEMO_DIR)/media/curiosity.ogv build/demo/media/curiosity.ogv

build/demo/media/llama-drama-av1.webm : $(DEMO_DIR)/media/llama-drama-av1.webm
	test -d build/demo/media || mkdir -p build/demo/media
	cp $(DEMO_DIR)/media/llama-drama-av1.webm build/demo/media/llama-drama-av1.webm

build/demo/lib/ogv.js : dist
	test -d build/demo/lib || mkdir -p build/demo/lib
	cp -pr dist/* build/demo/lib/


# TODO: Use Karma with this instead: https://github.com/karma-runner/karma-qunit
#       which will replace this stuff here by a one-liner
# QUnit test cases
build/tests/index.html : build/tests/tests.js \
                         build/tests/lib/ogv.js \
                         build/tests/media/1frame.ogv \
                         build/tests/media/3frames.ogv \
                         build/tests/media/1second.ogv \
                         build/tests/media/3seconds.ogv \
                         build/tests/media/3seconds-noskeleton.ogv \
                         build/tests/media/320x240.ogv \
												 build/tests/media/aspect.ogv \
                         $(TESTS_DIR)/index.html
	test -d build/tests || mkdir -p build/tests
	cp $(TESTS_DIR)/index.html build/tests/index.html

build/tests/tests.js : $(TESTS_DIR)/tests.js
	test -d build/tests || mkdir -p build/tests
	cp $(TESTS_DIR)/tests.js build/tests/tests.js

build/tests/lib/ogv.js : dist
	test -d build/tests/lib || mkdir -p build/tests/lib
	cp -pr dist/* build/tests/lib/

build/tests/media/1frame.ogv : $(TESTS_DIR)/media/1frame.ogv
	test -d build/tests/media || mkdir -p build/tests/media
	cp $(TESTS_DIR)/media/1frame.ogv build/tests/media/1frame.ogv

build/tests/media/3frames.ogv : $(TESTS_DIR)/media/3frames.ogv
	test -d build/tests/media || mkdir -p build/tests/media
	cp $(TESTS_DIR)/media/3frames.ogv build/tests/media/3frames.ogv

build/tests/media/1second.ogv : $(TESTS_DIR)/media/1second.ogv
	test -d build/tests/media || mkdir -p build/tests/media
	cp $(TESTS_DIR)/media/1second.ogv build/tests/media/1second.ogv

build/tests/media/3seconds.ogv : $(TESTS_DIR)/media/3seconds.ogv
	test -d build/tests/media || mkdir -p build/tests/media
	cp $(TESTS_DIR)/media/3seconds.ogv build/tests/media/3seconds.ogv

build/tests/media/3seconds-noskeleton.ogv : $(TESTS_DIR)/media/3seconds-noskeleton.ogv
	test -d build/tests/media || mkdir -p build/tests/media
	cp $(TESTS_DIR)/media/3seconds-noskeleton.ogv build/tests/media/3seconds-noskeleton.ogv

build/tests/media/320x240.ogv : $(TESTS_DIR)/media/320x240.ogv
	test -d build/tests/media || mkdir -p build/tests/media
	cp $(TESTS_DIR)/media/320x240.ogv build/tests/media/320x240.ogv

build/tests/media/aspect.ogv : $(TESTS_DIR)/media/aspect.ogv
	test -d build/tests/media || mkdir -p build/tests/media
	cp $(TESTS_DIR)/media/aspect.ogv build/tests/media/aspect.ogv
