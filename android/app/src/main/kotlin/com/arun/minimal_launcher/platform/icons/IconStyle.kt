package com.arun.minimal_launcher.platform.icons

/**
 * How app icons are drawn, as sent by Dart (lib/core/models/icon_style.dart;
 * keep the keys and values in sync).
 */
data class IconStyle(
    /** [ORIGINAL], [THEMED] (Android's monochrome icons), or a bundled pack name. */
    val pack: String = ORIGINAL,
    /** Try the other sources before [fallback] when [pack] has no icon. */
    val fillGaps: Boolean = true,
    val background: String = BG_DARK,
    /** Glyph colour (ARGB), unless [appColor]. */
    val color: Int = 0xFFFFFFFF.toInt(),
    /** Tint each glyph with a colour taken from the app's own icon. */
    val appColor: Boolean = false,
    /** Multiplier of the primary pack's stroke width. */
    val lineWeight: Float = 1f,
    /** Fraction of the icon the glyph spans. */
    val glyphScale: Float = 0.62f,
    /** For apps no source has an icon for: [THEMED], [LETTER], [GRAYSCALE] or [ORIGINAL]. */
    val fallback: String = THEMED,
    /**
     * Behind the app's own icons that don't fill the shape (older, non-adaptive
     * ones): [LEGACY_PLAIN], [LEGACY_TINTED], or [LEGACY_KEEP] (left as made).
     */
    val legacyBackground: String = LEGACY_PLAIN,
) {
    val isOriginal get() = pack == ORIGINAL

    /** Sources tried in order before [fallback]. */
    val sources: List<String>
        get() = when {
            !fillGaps -> listOf(pack)
            pack == THEMED -> listOf(THEMED) + IconPackStore.PACKS
            else -> listOf(pack) + IconPackStore.PACKS.filter { it != pack }
        }

    /** Stroke width in the 0..100 glyph box, before an op's own ratio. */
    val strokeWidth: Float
        get() = IconPackStore.nominalStroke(if (pack in IconPackStore.PACKS) pack else IconPackStore.LAWNICONS) *
            lineWeight

    companion object {
        const val ORIGINAL = "original"
        const val THEMED = "themed"
        const val LETTER = "letter"
        const val GRAYSCALE = "grayscale"

        const val LEGACY_PLAIN = "plain"
        const val LEGACY_TINTED = "tinted"
        const val LEGACY_KEEP = "keep"

        const val BG_DARK = "dark"
        const val BG_BLACK = "black"
        const val BG_GLASS = "glass"
        const val BG_TINTED = "tinted"
        const val BG_NONE = "none"

        fun fromMap(map: Map<*, *>?): IconStyle {
            if (map == null) return IconStyle()
            val d = IconStyle()
            return IconStyle(
                pack = map["pack"] as? String ?: d.pack,
                fillGaps = map["fillGaps"] as? Boolean ?: d.fillGaps,
                background = map["background"] as? String ?: d.background,
                color = (map["color"] as? Number)?.toLong()?.toInt() ?: d.color,
                appColor = map["appColor"] as? Boolean ?: d.appColor,
                lineWeight = (map["lineWeight"] as? Number)?.toFloat()?.coerceIn(0.25f, 4f) ?: d.lineWeight,
                glyphScale = (map["glyphScale"] as? Number)?.toFloat()?.coerceIn(0.3f, 1f) ?: d.glyphScale,
                fallback = map["fallback"] as? String ?: d.fallback,
                legacyBackground = map["legacyBackground"] as? String ?: d.legacyBackground,
            )
        }
    }
}
