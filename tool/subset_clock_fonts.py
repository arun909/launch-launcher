"""Cuts the clock widget's fonts (assets/fonts/clock) down to what a clock
needs: Latin letters, digits and punctuation, every OpenType feature
(tabular figures among them) and the weight axis. Other variation axes are
pinned at their defaults.

Needs fontTools (pip install fonttools). Run on fresh downloads from
github.com/google/fonts (ofl/<name>/<Name>[axes].ttf, saved as <Name>.ttf):

    python3 tool/subset_clock_fonts.py <download dir> assets/fonts/clock
"""

import io
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

# Space to "~", Latin-1, dashes, curly quotes, thin and narrow spaces.
UNICODES = [*range(0x20, 0x7F), *range(0xA0, 0x100), 0x2009, 0x2013, 0x2014, *range(0x2018, 0x201E), 0x202F]

# Axes kept (the rest are pinned at their defaults).
KEEP_AXES = {"wght"}


def cut(src: pathlib.Path, dst: pathlib.Path) -> None:
    font = TTFont(src, lazy=False)
    if "fvar" in font:
        pinned = {a.axisTag: a.defaultValue for a in font["fvar"].axes if a.axisTag not in KEEP_AXES}
        if pinned:
            # Saved and read back: the subsetter needs fully loaded tables.
            buf = io.BytesIO()
            instancer.instantiateVariableFont(font, pinned).save(buf)
            buf.seek(0)
            font = TTFont(buf, lazy=False)
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=UNICODES)
    subsetter.subset(font)
    font.save(dst)
    print(f"{dst.name}: {src.stat().st_size // 1024} KB -> {dst.stat().st_size // 1024} KB")


def main() -> None:
    src_dir, dst_dir = map(pathlib.Path, sys.argv[1:3])
    for src in sorted(src_dir.glob("*.ttf")):
        cut(src, dst_dir / src.name)


if __name__ == "__main__":
    main()
