const OGVVersion = __OGV_FULL_VERSION__;

import WebAssemblyCheck from './WebAssemblyCheck.js';

const scriptMap = {
	OGVDemuxerOggW: 'ogv-demuxer-ogg-wasm.js',
	OGVDemuxerWebMW: 'ogv-demuxer-webm-wasm.js',
	OGVDecoderAudioOpusW: 'ogv-decoder-audio-opus-wasm.js',
	OGVDecoderAudioVorbisW: 'ogv-decoder-audio-vorbis-wasm.js',
	OGVDecoderVideoTheoraW: 'ogv-decoder-video-theora-wasm.js',
	OGVDecoderVideoVP8W: 'ogv-decoder-video-vp8-wasm.js',
	OGVDecoderVideoVP8MTW: 'ogv-decoder-video-vp8-mt-wasm.js',
	OGVDecoderVideoVP9W: 'ogv-decoder-video-vp9-wasm.js',
	OGVDecoderVideoVP9SIMDW: 'ogv-decoder-video-vp9-simd-wasm.js',
	OGVDecoderVideoVP9MTW: 'ogv-decoder-video-vp9-mt-wasm.js',
	OGVDecoderVideoVP9SIMDMTW: 'ogv-decoder-video-vp9-simd-mt-wasm.js',
	OGVDecoderVideoAV1W: 'ogv-decoder-video-av1-wasm.js',
	OGVDecoderVideoAV1SIMDW: 'ogv-decoder-video-av1-simd-wasm.js',
	OGVDecoderVideoAV1MTW: 'ogv-decoder-video-av1-mt-wasm.js',
	OGVDecoderVideoAV1SIMDMTW: 'ogv-decoder-video-av1-simd-mt-wasm.js',
	OGVDecoderVideoFFmpegW: 'ogv-decoder-video-ffmpeg-wasm.js',
};

class OGVLoaderBase {
	constructor() {
		this.base = this.defaultBase();
	}

	defaultBase() {
		return undefined;
	}

	wasmSupported() {
		return WebAssemblyCheck.wasmSupported();
	}

	scriptForClass(className) {
		return scriptMap[className];
	}

	urlForClass(className) {
		let scriptName = this.scriptForClass(className);
		if (scriptName) {
			return this.urlForScript(scriptName);
		} else {
			throw new Error('asked for URL for unknown class ' + className);
		}
	}

	urlForScript(scriptName) {
		if (scriptName) {
			let base = this.base;
			if (base === undefined) {
				base = '';
			} else {
				base += '/';
			}
			return base + scriptName + '?version=' + encodeURIComponent(OGVVersion);
		} else {
			throw new Error('asked for URL for unknown script ' + scriptName);
		}
	}

	loadClass(className, callback, options) {
		options = options || {};
		let global = this.getGlobal();
		let url = this.urlForClass(className);
		let classWrapper = (options) => {
			options = options || {};
			options.locateFile = (filename) => {
				// Allow secondary resources like the .wasm payload
				// to be loaded by the emscripten code.
				if (filename.slice(0, 5) === 'data:') {
					// emscripten 1.37.25 loads memory initializers as data: URI
					return filename;
				} else {
					return this.urlForScript(filename);
				}
			};
			options.mainScriptUrlOrBlob = this.scriptForClass(className) + '?version=' + encodeURIComponent(OGVVersion);
			// Note: these pseudoclasses should not use 'new',
			// which breaks in emscripten 1.38.10
			return global[className](options);
		}
		if (typeof global[className] === 'function') {
			// already loaded!
			callback(classWrapper);
		} else {
			this.loadScript(url, () => {
				callback(classWrapper);
			});
		}
	}
}

export default OGVLoaderBase;
