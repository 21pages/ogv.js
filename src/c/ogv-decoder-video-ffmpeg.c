#include <assert.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <libavcodec/avcodec.h>
#include <libavutil/log.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>

#include "ogv-decoder-video.h"
#include "ogv-thread-support.h"

struct FFmpegRamDecoder
{
	AVCodecContext *c_;
	AVFrame *frame_;
	AVPacket *pkt_;
	char name_[128];
};

static struct FFmpegRamDecoder *ffmpegRamDecoder = NULL;

static void free_decoder(struct FFmpegRamDecoder *d)
{
	if (d->frame_)
		av_frame_free(&d->frame_);
	if (d->pkt_)
		av_packet_free(&d->pkt_);
	if (d->c_)
		avcodec_free_context(&d->c_);

	d->frame_ = NULL;
	d->pkt_ = NULL;
	d->c_ = NULL;
}

static int get_thread_count()
{
#ifdef __EMSCRIPTEN_PTHREADS__
	const int max_cores = 8; // max threads for UHD tiled decoding
	int cores = emscripten_num_logical_cores();
	if (cores == 0)
	{
		// Safari 15 does not report navigator.hardwareConcurrency...
		// Assume at least two fast cores are available.
		cores = 2;
	}
	else if (cores > max_cores)
	{
		cores = max_cores;
	}
	return cores;
#else
	return 1;
#endif
}

static int reset(struct FFmpegRamDecoder *d)
{
	free_decoder(d);
	const AVCodec *codec = NULL;
	int ret;
	if (!(codec = avcodec_find_decoder_by_name(d->name_)))
	{
		printf("avcodec_find_decoder_by_name failed\n");
		return -1;
	}
	if (!(d->c_ = avcodec_alloc_context3(codec)))
	{
		printf("Could not allocate video codec context\n");
		return -1;
	}

	d->c_->flags |= AV_CODEC_FLAG_LOW_DELAY;
	// d->c_->thread_count = get_thread_count();
	d->c_->thread_type = FF_THREAD_SLICE;

	if (!(d->pkt_ = av_packet_alloc()))
	{
		printf("av_packet_alloc failed\n");
		return -1;
	}

	if (!(d->frame_ = av_frame_alloc()))
	{
		printf("av_frame_alloc failed\n");
		return -1;
	}

	if ((ret = avcodec_open2(d->c_, codec, NULL)) != 0)
	{
		printf("avcodec_open2 failed\n");
		return -1;
	}
	printf("reset ok\n");

	return 0;
}

static void do_init(void)
{
	printf("do init 1\n");
	if (ffmpegRamDecoder)
	{
		free_decoder(ffmpegRamDecoder);
		free(ffmpegRamDecoder);
		ffmpegRamDecoder = NULL;
	}
	printf("do init 2\n");
	ffmpegRamDecoder = malloc(sizeof(struct FFmpegRamDecoder));
	if (!ffmpegRamDecoder)
	{
		return;
	}
	printf("do init 3\n");
	snprintf(ffmpegRamDecoder->name_, sizeof(ffmpegRamDecoder->name_), "%s", "vp9");
	if (reset(ffmpegRamDecoder) != 0)
	{
		free_decoder(ffmpegRamDecoder);
		free(ffmpegRamDecoder);
		ffmpegRamDecoder = NULL;
		return;
	}
	printf("do init ok\n");
}

void do_destroy(void)
{
	// should tear instance down, but meh
}

static int do_decode()
{
	int ret;
	bool decoded = false;

	printf("d->name:%s\n", ffmpegRamDecoder->name_);
	ret = avcodec_send_packet(ffmpegRamDecoder->c_, ffmpegRamDecoder->pkt_);
	if (ret < 0)
	{
		printf("avcodec_send_packet failed, ret=%d, msg=%s\n", ret, av_err2str(ret));
		return ret;
	}
	printf("avcodec_send_packet ok\n");

	while (ret >= 0)
	{
		if ((ret = avcodec_receive_frame(ffmpegRamDecoder->c_, ffmpegRamDecoder->frame_)) != 0)
		{
			if (ret != AVERROR(EAGAIN))
			{
				printf("avcodec_receive_frame failed,  ret=%d, msg=%s\n", ret, av_err2str(ret));
			}
			goto _exit;
		}
		decoded = true;
		printf("d:%p, d->frame_-:%p, width: %d, height: %d, linesize[0]: %d\n", ffmpegRamDecoder, ffmpegRamDecoder->frame_, ffmpegRamDecoder->frame_->width, ffmpegRamDecoder->frame_->height, ffmpegRamDecoder->frame_->linesize[0]);
	}
_exit:
	av_packet_unref(ffmpegRamDecoder->pkt_);
	return decoded ? 0 : -1;
}

static int decode(const uint8_t *data, int length)
{
	int ret = -1;
	if (!data || !length)
	{
		printf("illegal decode parameter\n");
		return -1;
	}
	ffmpegRamDecoder->pkt_->data = (uint8_t *)data;
	ffmpegRamDecoder->pkt_->size = length;
	printf("decode length: %d\n", length);
	ret = do_decode();
	return ret;
}

static AVFrame *copy_image(AVFrame *src)
{
	// AVFrame* dest = av_frame_alloc();
	// if (!dest) {
	// 	return NULL;
	// }
	// // copy src to dest
	// dest->format = src->format;
	// dest->width = src->width;
	// dest->height = src->height;
	// dest->channels = src->channels;
	// dest->channel_layout = src->channel_layout;
	// dest->nb_samples = src->nb_samples;
	// av_frame_get_buffer(dest, 32); // 32 ??
	// av_frame_copy(dest, src);
	// av_frame_copy_props(dest, src);
	// return dest;
	return src;
}


static void process_frame_decode(const char *data, size_t data_len)
{
	if (!data)
	{
		// NULL data signals syncing the decoder state
		call_main_return(NULL, 1);
		return;
	}

	int ret = decode((const uint8_t *)data, data_len);
	if (ret != 0)
	{
		call_main_return(NULL, 0);
		return;
	}
	printf("ffmpegRamDecoder:%p, ffmpegRamDecoder->frame_:%p, width: %d, height: %d, linesize[0]: %d\n", ffmpegRamDecoder, ffmpegRamDecoder->frame_, ffmpegRamDecoder->frame_->width, ffmpegRamDecoder->frame_->height, ffmpegRamDecoder->frame_->linesize[0]);
	AVFrame *frame = ffmpegRamDecoder->frame_;
	// send back to the main thread for extraction.
#ifdef __EMSCRIPTEN_PTHREADS__
	// Copy off main thread and send asynchronously...
	// This allows decoding to continue without waiting
	// for the main thread.
	call_main_return(copy_image(frame), 0);
#else
	call_main_return(frame, 1);
#endif

}


static int process_frame_return(void *image)
{
	AVFrame *frame = (AVFrame*)image;
	printf("process_frame_return: %p\n", frame);
	if (frame)
	{
		// image->h is inexplicably large for small sizes.
		// don't both copying the extra, but make sure it's chroma-safe.
		int height = frame->height;
		if ((height & 1) == 1)
		{
			// copy one extra row if need be
			// not sure this is even possible
			// but defend in depth
			height++;
		}

		int chromaWidth, chromaHeight;
		printf("process_frame_return: w: %d, h: %d\n", frame->width, frame->height);
		switch (frame->format)
		{
		case AV_PIX_FMT_YUV420P:
			chromaWidth = frame->width >> 1;
			chromaHeight = height >> 1;
			break;
		case AV_PIX_FMT_YUV444P:
			chromaWidth = frame->width;
			chromaHeight = height;
			break;
		default:
			return 0;
		}
		ogvjs_callback_frame(frame->data[0], frame->linesize[0],
							 frame->data[1], frame->linesize[1],
							 frame->data[2], frame->linesize[2],
							 frame->width, height,
							 chromaWidth, chromaHeight,
							 frame->width, frame->height,  // crop size
							 0, 0,						   // crop pos
							 frame->width, frame->height); // render size
#ifdef __EMSCRIPTEN_PTHREADS__
		// We were given a copy, so free it.
		// vpx_img_free(image); // todo
#else
		// Image will be freed implicitly by next decode call.
#endif
		return 1;
	}
	else
	{
		return 0;
	}
}