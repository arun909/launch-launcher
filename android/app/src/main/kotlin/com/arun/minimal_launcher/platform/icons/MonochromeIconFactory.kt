/*
 * Copyright (C) 2024 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Ported to Kotlin from AOSP Launcher3's iconloaderlib
 * (com.android.launcher3.icons.MonochromeIconFactory), which Pixel uses to
 * theme icons that don't ship a monochrome layer. Changed: returns a plain
 * drawable of the 108dp layer instead of Launcher3's ClippedMonoDrawable, and
 * wraps legacy (non-adaptive) icons first, as Launcher3 does elsewhere.
 */
package com.arun.minimal_launcher.platform.icons

import android.graphics.Bitmap
import android.graphics.BlendMode
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.InsetDrawable
import android.content.res.Resources
import android.os.Build
import java.nio.ByteBuffer
import kotlin.math.roundToInt

/** Generates a monochrome layer (white, alpha = shape) for an icon without one. */
@android.annotation.TargetApi(Build.VERSION_CODES.Q)
class MonochromeIconFactory(iconBitmapSize: Int) {

    private val bitmapSize: Int
    private val edgePixelLength: Int
    private val pixels: ByteArray
    private val flatBitmap: Bitmap
    private val flatCanvas: Canvas
    private val alphaBitmap: Bitmap
    private val alphaCanvas: Canvas
    private val copyPaint = Paint(Paint.FILTER_BITMAP_FLAG)

    init {
        val extraFactor = AdaptiveIconDrawable.getExtraInsetFraction()
        val viewPortScale = 1 / (1 + 2 * extraFactor)
        bitmapSize = (iconBitmapSize * 2 * viewPortScale).roundToInt()
        pixels = ByteArray(bitmapSize * bitmapSize)
        edgePixelLength = bitmapSize * (bitmapSize - iconBitmapSize) / 2

        flatBitmap = Bitmap.createBitmap(bitmapSize, bitmapSize, Bitmap.Config.ARGB_8888)
        flatCanvas = Canvas(flatBitmap)
        alphaBitmap = Bitmap.createBitmap(bitmapSize, bitmapSize, Bitmap.Config.ALPHA_8)
        alphaCanvas = Canvas(alphaBitmap)

        copyPaint.blendMode = BlendMode.SRC
        // A colour matrix which converts the icon to grayscale and then uses the
        // average of the RGB components as the alpha component.
        val satMatrix = ColorMatrix().apply { setSaturation(0f) }
        val vals = satMatrix.array
        vals[15] = .3333f
        vals[16] = .3333f
        vals[17] = .3333f
        vals[18] = 0f
        vals[19] = 0f
        copyPaint.colorFilter = ColorMatrixColorFilter(vals)
    }

    /**
     * A monochrome version of [icon], as a drawable of the whole 108dp adaptive
     * layer (like [AdaptiveIconDrawable.getMonochrome]).
     */
    fun wrap(icon: Drawable, resources: Resources): Drawable {
        val adaptive = icon as? AdaptiveIconDrawable ?: wrapLegacy(icon)
        flatCanvas.drawColor(Color.BLACK)
        drawDrawable(adaptive.background)
        drawDrawable(adaptive.foreground)
        generateMono()
        val out = alphaBitmap.copy(Bitmap.Config.ALPHA_8, false)
        return BitmapDrawable(resources, out).apply { paint.color = Color.WHITE }
    }

    private fun drawDrawable(drawable: Drawable?) {
        drawable ?: return
        drawable.setBounds(0, 0, bitmapSize, bitmapSize)
        drawable.draw(flatCanvas)
    }

    private fun generateMono() {
        alphaCanvas.drawBitmap(flatBitmap, 0f, 0f, copyPaint)

        // Scale the end points:
        val buffer = ByteBuffer.wrap(pixels)
        buffer.rewind()
        alphaBitmap.copyPixelsToBuffer(buffer)

        var min = 0xFF
        var max = 0
        for (b in pixels) {
            min = minOf(min, b.toInt() and 0xFF)
            max = maxOf(max, b.toInt() and 0xFF)
        }

        if (min < max) {
            // Rescale pixels to increase contrast.
            val range = (max - min).toFloat()

            // To check if the colours should be flipped, take the average colour of
            // the top and bottom edges, which should be the background. If the edges
            // are more opaque, flip the colours.
            var sum = 0
            for (i in 0 until edgePixelLength) {
                sum += pixels[i].toInt() and 0xFF
                sum += pixels[pixels.size - 1 - i].toInt() and 0xFF
            }
            val edgeAverage = sum / (edgePixelLength * 2f)
            val edgeMapped = (edgeAverage - min) / range
            val flipColor = edgeMapped > .5f

            for (i in pixels.indices) {
                val p = pixels[i].toInt() and 0xFF
                val p2 = ((p - min) * 0xFF / range).roundToInt()
                pixels[i] = (if (flipColor) 255 - p2 else p2).toByte()
            }
            buffer.rewind()
            alphaBitmap.copyPixelsFromBuffer(buffer)
        }
    }

    /**
     * A legacy icon as an adaptive one: white background, the icon inside the
     * visible 72dp of the 108dp foreground (as Launcher3 wraps legacy icons).
     */
    private fun wrapLegacy(icon: Drawable): AdaptiveIconDrawable {
        val inset = AdaptiveIconDrawable.getExtraInsetFraction() / (1 + 2 * AdaptiveIconDrawable.getExtraInsetFraction())
        return AdaptiveIconDrawable(ColorDrawable(Color.WHITE), InsetDrawable(icon, inset + LEGACY_PADDING))
    }

    private companion object {
        /** Extra margin so legacy art sits inside the shape, like Launcher3's normalised legacy icons. */
        const val LEGACY_PADDING = 0.06f
    }
}
