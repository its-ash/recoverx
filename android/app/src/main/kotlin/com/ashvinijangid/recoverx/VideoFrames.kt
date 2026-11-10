package com.ashvinijangid.recoverx

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.nio.ByteBuffer

/**
 * Grabs frames from a video for the sensitive-content check.
 *
 * Read-only: MediaMetadataRetriever only opens the file for reading, and
 * every frame stays in memory (raw RGBA, size × size). Nothing is written.
 */
object VideoFrames {
    fun sample(path: String, count: Int, size: Int): List<ByteArray> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val out = ArrayList<ByteArray>(count)
            for (i in 1..count) {
                // Evenly spread over the video, skipping the very start and end.
                val timeUs = if (durationMs > 0) durationMs * 1000L * i / (count + 1)
                             else (i - 1) * 2_000_000L
                val frame = grab(retriever, timeUs, size) ?: continue
                out.add(toRgba(frame, size))
            }
            return out
        } finally {
            retriever.release()
        }
    }

    private fun grab(r: MediaMetadataRetriever, timeUs: Long, size: Int): Bitmap? {
        val option = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            // Decode near the target size instead of full resolution.
            r.getScaledFrameAtTime(timeUs, option, size * 2, size * 2)
        } else {
            r.getFrameAtTime(timeUs, option)
        }
    }

    private fun toRgba(frame: Bitmap, size: Int): ByteArray {
        val argb = if (frame.config == Bitmap.Config.ARGB_8888) frame
                   else frame.copy(Bitmap.Config.ARGB_8888, false)
        val scaled = Bitmap.createScaledBitmap(argb, size, size, true)
        val buffer = ByteBuffer.allocate(size * size * 4)
        scaled.copyPixelsToBuffer(buffer) // ARGB_8888 is stored as R, G, B, A bytes
        if (scaled !== argb) scaled.recycle()
        if (argb !== frame) argb.recycle()
        frame.recycle()
        return buffer.array()
    }
}
