package com.arun.minimal_launcher.platform.icons

import android.content.ComponentName
import android.content.res.AssetManager
import android.graphics.Path
import android.util.LruCache

/**
 * Reads the icon packs bundled in `assets/iconpacks/<pack>/`, written by
 * tool/iconpacks/build_icon_packs.py (keep the two in sync):
 *
 *   appfilter.tsv   "<package>/<activity>\t<icon name>" per line
 *   index.txt       icon names, sorted; icon i lives in chunk i / [CHUNK_SIZE]
 *   chunk_NNN.txt   "<icon name>\t<op>;<op>;..." per line, op = <S|F|E><ratio>:<path>
 *
 * Paths are absolute M/L/C/Z in a 0..100 box. Everything is loaded lazily and
 * only what installed apps need is kept in memory. Thread-safe.
 */
class IconPackStore(
    private val assets: AssetManager,
    private val installedPackages: () -> Set<String>,
) {

    /** One drawing operation of a glyph. [strokeRatio] is relative to the pack's nominal stroke. */
    class Op(val kind: Char, val strokeRatio: Float, val path: Path)

    class Glyph(val ops: List<Op>)

    private class Pack(val name: String) {
        /** Component -> icon, and package -> icon for activities the pack doesn't list. */
        var byComponent: Map<String, String> = emptyMap()
        var byPackage: Map<String, String> = emptyMap()
        var loadedFor: Set<String>? = null
        val reloadedFor = HashSet<String>()
        var index: List<String>? = null
        val chunks = LruCache<Int, Map<String, String>>(12)
        val glyphs = LruCache<String, Glyph>(256)
    }

    private val packs = PACKS.associateWith { Pack(it) }

    /** The pack's icon name for [component], or null if the pack has none. */
    @Synchronized
    fun iconFor(pack: String, component: ComponentName): String? {
        val p = packs[pack] ?: return null
        // Reload once a package installed since the last load is asked for
        // (only once per package, in case it's missing from the installed list).
        val pkg = component.packageName
        if (p.loadedFor?.contains(pkg) != true && p.reloadedFor.add(pkg)) loadFilter(p)
        return p.byComponent["${component.packageName}/${component.className}"]
            ?: p.byPackage[component.packageName]
    }

    /** Every icon name in [pack], sorted. */
    @Synchronized
    fun names(pack: String): List<String> {
        val p = packs[pack] ?: return emptyList()
        return p.index ?: readLines("$ROOT/$pack/index.txt").also { p.index = it }
    }

    @Synchronized
    fun glyph(pack: String, name: String): Glyph? {
        val p = packs[pack] ?: return null
        p.glyphs.get(name)?.let { return it }
        val position = names(pack).binarySearch(name)
        if (position < 0) return null
        val chunkNo = position / CHUNK_SIZE
        val chunk = p.chunks.get(chunkNo) ?: readChunk(pack, chunkNo).also { p.chunks.put(chunkNo, it) }
        val glyph = chunk[name]?.let(::parseGlyph) ?: return null
        p.glyphs.put(name, glyph)
        return glyph
    }

    private fun loadFilter(p: Pack) {
        val installed = installedPackages()
        val byComponent = HashMap<String, String>()
        val byPackage = HashMap<String, String>()
        assets.open("$ROOT/${p.name}/appfilter.tsv").bufferedReader().useLines { lines ->
            for (line in lines) {
                val tab = line.indexOf('\t')
                val slash = line.indexOf('/')
                if (tab < 0 || slash !in 1 until tab) continue
                val pkg = line.substring(0, slash)
                if (pkg !in installed) continue
                val icon = line.substring(tab + 1)
                byComponent[line.substring(0, tab)] = icon
                byPackage.putIfAbsent(pkg, icon)
            }
        }
        p.byComponent = byComponent
        p.byPackage = byPackage
        p.loadedFor = installed
    }

    private fun readChunk(pack: String, chunkNo: Int): Map<String, String> {
        val map = HashMap<String, String>(CHUNK_SIZE * 2)
        for (line in readLines("$ROOT/$pack/chunk_%03d.txt".format(chunkNo))) {
            val tab = line.indexOf('\t')
            if (tab > 0) map[line.substring(0, tab)] = line.substring(tab + 1)
        }
        return map
    }

    private fun readLines(path: String): List<String> = try {
        assets.open(path).bufferedReader().useLines { lines -> lines.filter { it.isNotEmpty() }.toList() }
    } catch (_: java.io.IOException) {
        emptyList()
    }

    companion object {
        const val LAWNICONS = "lawnicons"
        const val ARCTICONS = "arcticons"
        val PACKS = listOf(LAWNICONS, ARCTICONS)

        private const val ROOT = "iconpacks"
        private const val CHUNK_SIZE = 200

        /** Nominal stroke width of each pack, in the 0..100 glyph box. */
        fun nominalStroke(pack: String): Float = when (pack) {
            ARCTICONS -> 100f / 44f
            else -> 100f * 12f / 160f
        }

        fun parseGlyph(data: String): Glyph? {
            val ops = data.split(';').mapNotNull { op ->
                val colon = op.indexOf(':')
                if (colon < 1) return@mapNotNull null
                val kind = op[0]
                if (kind != 'S' && kind != 'F' && kind != 'E') return@mapNotNull null
                val ratio = op.substring(1, colon).toFloatOrNull() ?: return@mapNotNull null
                val path = parsePath(op, colon + 1) ?: return@mapNotNull null
                if (kind == 'E') path.fillType = Path.FillType.EVEN_ODD
                Op(kind, ratio, path)
            }
            return if (ops.isEmpty()) null else Glyph(ops)
        }

        /** Absolute M/L/C/Z path data, numbers separated by spaces. */
        private fun parsePath(s: String, start: Int): Path? {
            val path = Path()
            val nums = FloatArray(6)
            var i = start
            var cmd = ' '
            while (i < s.length) {
                val c = s[i]
                when {
                    c == 'Z' -> { path.close(); i++ }
                    c == 'M' || c == 'L' || c == 'C' -> { cmd = c; i++ }
                    c == ' ' -> i++
                    else -> {
                        val count = if (cmd == 'C') 6 else 2
                        for (k in 0 until count) {
                            while (i < s.length && s[i] == ' ') i++
                            var end = i
                            while (end < s.length && (s[end].isDigit() || s[end] == '.' || s[end] == '-' || s[end] == 'e')) end++
                            nums[k] = s.substring(i, end).toFloatOrNull() ?: return null
                            i = end
                        }
                        when (cmd) {
                            'M' -> { path.moveTo(nums[0], nums[1]); cmd = 'L' }
                            'L' -> path.lineTo(nums[0], nums[1])
                            'C' -> path.cubicTo(nums[0], nums[1], nums[2], nums[3], nums[4], nums[5])
                            else -> return null
                        }
                    }
                }
            }
            return path
        }
    }
}
