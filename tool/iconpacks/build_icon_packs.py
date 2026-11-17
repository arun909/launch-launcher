#!/usr/bin/env python3
"""Converts the Lawnicons and Arcticons SVG icon packs into the compact format
the launcher bundles (android/app/src/main/assets/iconpacks/).

Only geometry is kept: every shape is reduced to absolute M/L/C/Z path data in
a 0..100 box, plus whether it is stroked or filled. Scripts, links, images,
colours and every other SVG feature are dropped, so nothing from the source
files can run inside the launcher.

Usage (see tool/iconpacks/README.md for the pinned source commits):
    python3 -I tool/iconpacks/build_icon_packs.py \
        --lawnicons <lawnicons checkout> --arcticons <Arcticons checkout> \
        [--arcticons-packages <file of package names to keep>]

Output per pack, in android/app/src/main/assets/iconpacks/<pack>/:
    appfilter.tsv     "<package>/<activity>\t<icon name>" per line
    index.txt         icon names, sorted; chunk = line number // CHUNK_SIZE
    chunk_NNN.txt     "<icon name>\t<op>;<op>;..." per line, same order
                      op = <S|F|E><stroke width ratio>:<path data>
                      (S = stroke, F = fill nonzero, E = fill even-odd)
Keep this format in sync with IconPackStore.kt.
"""

import argparse
import math
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET

CHUNK_SIZE = 200

# Each pack's content box (in its own SVG units, stroke included) is mapped to
# 0..100, so icons from both packs come out the same size.
PACKS = {
    'lawnicons': {
        'svg_dir': 'svgs',
        'appfilter': 'app/assets/appfilter.xml',
        'box': (16.0, 176.0),  # 192 canvas, 148 keyline + 12 stroke
        'stroke': 12.0,  # the pack's nominal stroke width
        'license': 'LICENSE',
    },
    'arcticons': {
        'svg_dir': 'icons/white',
        'appfilter': 'app/src/main/assets/appfilter.xml',
        'box': (2.0, 46.0),  # 48 canvas, r=21.5 circle + 1 stroke
        'stroke': 1.0,
        'license': None,  # icons are CC BY-SA 4.0; see NOTICE written below
    },
}

OUT_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'android', 'app', 'src', 'main', 'assets', 'iconpacks')

NUM_RE = re.compile(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
TOKEN_RE = re.compile(r'[MmZzLlHhVvCcSsQqTtAa]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
COMPONENT_RE = re.compile(r'ComponentInfo\{([^/}]+)/([^}]+)\}')


# --- affine transforms --------------------------------------------------------

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def mul(m, n):
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (a * a2 + c * b2, b * a2 + d * b2, a * c2 + c * d2, b * c2 + d * d2, a * e2 + c * f2 + e, b * e2 + d * f2 + f)


def apply(m, x, y):
    a, b, c, d, e, f = m
    return a * x + c * y + e, b * x + d * y + f


def parse_transform(value):
    m = IDENTITY
    for name, args in re.findall(r'(\w+)\s*\(([^)]*)\)', value or ''):
        v = [float(n) for n in NUM_RE.findall(args)]
        if name == 'matrix' and len(v) == 6:
            t = tuple(v)
        elif name == 'translate' and v:
            t = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == 'scale' and v:
            t = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == 'rotate' and v:
            r = math.radians(v[0])
            t = (math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0)
            if len(v) == 3:
                t = mul(mul((1, 0, 0, 1, v[1], v[2]), t), (1, 0, 0, 1, -v[1], -v[2]))
        elif name == 'skewX' and v:
            t = (1, 0, math.tan(math.radians(v[0])), 1, 0, 0)
        elif name == 'skewY' and v:
            t = (1, math.tan(math.radians(v[0])), 0, 1, 0, 0)
        else:
            continue
        m = mul(m, t)
    return m


# --- path data -> absolute M/L/C/Z ---------------------------------------------

def arc_to_cubics(x1, y1, rx, ry, phi, large, sweep, x2, y2):
    """SVG arc as cubic Bezier segments (SVG spec F.6 endpoint -> center)."""
    if (x1, y1) == (x2, y2):
        return []
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [('L', x2, y2)]
    p = math.radians(phi)
    cp, sp = math.cos(p), math.sin(p)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = (x1p / rx) ** 2 + (y1p / ry) ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large == sweep:
        coef = -coef
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    n = max(1, int(math.ceil(abs(dt) / (math.pi / 2) - 1e-9)))
    step = dt / n
    k = 4 / 3 * math.tan(step / 4)
    out = []
    for i in range(n):
        a1, a2 = t1 + i * step, t1 + (i + 1) * step
        c1, s1, c2, s2 = math.cos(a1), math.sin(a1), math.cos(a2), math.sin(a2)
        pts = [(c1 - k * s1, s1 + k * c1), (c2 + k * s2, s2 - k * c2), (c2, s2)]
        seg = []
        for ux, uy in pts:
            ux, uy = ux * rx, uy * ry
            seg += [cp * ux - sp * uy + cx, sp * ux + cp * uy + cy]
        out.append(('C', *seg))
    return out


def parse_path(d):
    """Path data as a list of absolute ('M'|'L'|'C'|'Z', coords...) segments."""
    tokens = TOKEN_RE.findall(d or '')
    out = []
    i, cmd = 0, None
    x = y = sx = sy = 0.0
    last_ctrl = None  # (cmd kind, x, y) for S/T reflection

    def nums(k):
        nonlocal i
        vals = [float(t) for t in tokens[i:i + k]]
        if len(vals) < k or any(t.isalpha() for t in tokens[i:i + k]):
            raise ValueError('bad path')
        i += k
        return vals

    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
            if cmd in 'Zz':
                out.append(('Z',))
                x, y = sx, sy
                last_ctrl = None
                continue
        elif cmd is None:
            raise ValueError('path without command')
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if c == 'M':
            px, py = nums(2)
            x, y = ox + px, oy + py
            sx, sy = x, y
            out.append(('M', x, y))
            cmd = 'l' if rel else 'L'  # extra pairs are implicit lineto
            last_ctrl = None
        elif c == 'L':
            px, py = nums(2)
            x, y = ox + px, oy + py
            out.append(('L', x, y))
            last_ctrl = None
        elif c == 'H':
            (px,) = nums(1)
            x = ox + px
            out.append(('L', x, y))
            last_ctrl = None
        elif c == 'V':
            (py,) = nums(1)
            y = oy + py
            out.append(('L', x, y))
            last_ctrl = None
        elif c in 'CS':
            if c == 'C':
                x1, y1, x2, y2, px, py = nums(6)
                x1, y1 = ox + x1, oy + y1
            else:
                x2, y2, px, py = nums(4)
                x1, y1 = (2 * x - last_ctrl[1], 2 * y - last_ctrl[2]) if last_ctrl and last_ctrl[0] == 'C' else (x, y)
            x2, y2, px, py = ox + x2, oy + y2, ox + px, oy + py
            out.append(('C', x1, y1, x2, y2, px, py))
            last_ctrl = ('C', x2, y2)
            x, y = px, py
        elif c in 'QT':
            if c == 'Q':
                qx, qy, px, py = nums(4)
                qx, qy = ox + qx, oy + qy
            else:
                px, py = nums(2)
                qx, qy = (2 * x - last_ctrl[1], 2 * y - last_ctrl[2]) if last_ctrl and last_ctrl[0] == 'Q' else (x, y)
            px, py = ox + px, oy + py
            # Quadratic as cubic, so the app only needs M/L/C/Z.
            out.append(('C', x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y),
                        px + 2 / 3 * (qx - px), py + 2 / 3 * (qy - py), px, py))
            last_ctrl = ('Q', qx, qy)
            x, y = px, py
        elif c == 'A':
            # Flags are single digits and may be packed together ("a1 1 0 011 1").
            for j in (i + 3, i + 4):
                t = tokens[j] if j < len(tokens) else ''
                if len(t) > 1 and t[0] in '01' and not t.startswith(('0.', '1.')):
                    tokens[j:j + 1] = [t[0], t[1:]]
            arx, ary, phi, large, sweep, px, py = nums(7)
            px, py = ox + px, oy + py
            out += arc_to_cubics(x, y, arx, ary, phi, bool(large), bool(sweep), px, py)
            x, y = px, py
            last_ctrl = None
        else:
            raise ValueError('unknown command ' + cmd)
    return out


K = 0.5522847498  # circle quadrant as a cubic


def ellipse(cx, cy, rx, ry):
    return [('M', cx + rx, cy),
            ('C', cx + rx, cy + K * ry, cx + K * rx, cy + ry, cx, cy + ry),
            ('C', cx - K * rx, cy + ry, cx - rx, cy + K * ry, cx - rx, cy),
            ('C', cx - rx, cy - K * ry, cx - K * rx, cy - ry, cx, cy - ry),
            ('C', cx + K * rx, cy - ry, cx + rx, cy - K * ry, cx + rx, cy),
            ('Z',)]


def rect(x, y, w, h, rx, ry):
    if w <= 0 or h <= 0:
        return []
    rx, ry = min(rx, w / 2), min(ry, h / 2)
    if rx <= 0 or ry <= 0:
        return [('M', x, y), ('L', x + w, y), ('L', x + w, y + h), ('L', x, y + h), ('Z',)]
    kx, ky = K * rx, K * ry
    return [('M', x + rx, y), ('L', x + w - rx, y),
            ('C', x + w - rx + kx, y, x + w, y + ry - ky, x + w, y + ry), ('L', x + w, y + h - ry),
            ('C', x + w, y + h - ry + ky, x + w - rx + kx, y + h, x + w - rx, y + h), ('L', x + rx, y + h),
            ('C', x + rx - kx, y + h, x, y + h - ry + ky, x, y + h - ry), ('L', x, y + ry),
            ('C', x, y + ry - ky, x + rx - kx, y, x + rx, y), ('Z',)]


def shape_segments(el, tag):
    def f(name, default=0.0):
        v = NUM_RE.match((el.get(name) or '').strip())
        return float(v.group()) if v else default

    if tag == 'path':
        return parse_path(el.get('d'))
    if tag == 'circle':
        r = f('r')
        return ellipse(f('cx'), f('cy'), r, r) if r > 0 else []
    if tag == 'ellipse':
        rx, ry = f('rx'), f('ry')
        return ellipse(f('cx'), f('cy'), rx, ry) if rx > 0 and ry > 0 else []
    if tag == 'rect':
        rx, ry = el.get('rx'), el.get('ry')
        rxv = f('rx') if rx is not None else (f('ry') if ry is not None else 0.0)
        ryv = f('ry') if ry is not None else rxv
        return rect(f('x'), f('y'), f('width'), f('height'), rxv, ryv)
    if tag == 'line':
        return [('M', f('x1'), f('y1')), ('L', f('x2'), f('y2'))]
    if tag in ('polyline', 'polygon'):
        v = [float(n) for n in NUM_RE.findall(el.get('points') or '')]
        pts = list(zip(v[0::2], v[1::2]))
        if len(pts) < 2:
            return []
        segs = [('M', *pts[0])] + [('L', *p) for p in pts[1:]]
        return segs + [('Z',)] if tag == 'polygon' else segs
    return []


# --- styles --------------------------------------------------------------------

STYLE_PROPS = ('fill', 'stroke', 'stroke-width', 'fill-rule', 'display', 'visibility', 'opacity')


def parse_decls(text):
    out = {}
    for decl in (text or '').split(';'):
        if ':' in decl:
            k, v = decl.split(':', 1)
            out[k.strip().lower()] = v.strip()
    return out


def parse_css(text):
    rules = {}
    for selectors, body in re.findall(r'([^{}]+)\{([^}]*)\}', text or ''):
        decls = parse_decls(body)
        for sel in selectors.split(','):
            sel = sel.strip()
            if sel.startswith('.'):
                rules.setdefault(sel[1:], {}).update(decls)
    return rules


def local(tag):
    return tag.rsplit('}', 1)[-1]


def is_paint(v):
    return v is not None and v.lower() not in ('none', 'transparent')


def fmt(v):
    # 0.1 of the 0..100 box is a twentieth of a pixel on a 192 px icon.
    s = f'{v:.1f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def convert_svg(path, pack):
    """The icon's ops string, or None if it has no drawable geometry."""
    root = ET.parse(path).getroot()
    lo, hi = pack['box']
    scale = 100.0 / (hi - lo)
    base = (scale, 0, 0, scale, -lo * scale, -lo * scale)

    vb = [float(n) for n in NUM_RE.findall(root.get('viewBox') or '')]
    if len(vb) == 4 and vb[2] > 0 and vb[3] > 0:
        # Fit the viewBox to the pack's nominal canvas (box hi + lo).
        canvas = hi + lo
        base = mul(base, (canvas / vb[2], 0, 0, canvas / vb[3], -vb[0] * canvas / vb[2], -vb[1] * canvas / vb[3]))

    css = {}
    for el in root.iter():
        if local(el.tag) == 'style':
            for cls, decls in parse_css(el.text).items():
                css.setdefault(cls, {}).update(decls)

    ops = []

    def walk(el, inherited, matrix):
        tag = local(el.tag)
        if tag in ('defs', 'style', 'metadata', 'title', 'desc', 'clipPath', 'mask', 'symbol', 'pattern'):
            return
        props = dict(inherited)
        props.pop('display', None)
        for k in STYLE_PROPS:  # attributes < class rules < inline style
            if el.get(k) is not None:
                props[k] = el.get(k)
        for cls in (el.get('class') or '').split():
            props.update({k: v for k, v in css.get(cls, {}).items() if k in STYLE_PROPS})
        props.update({k: v for k, v in parse_decls(el.get('style')).items() if k in STYLE_PROPS})
        if props.get('display') == 'none' or props.get('visibility') == 'hidden' or props.get('opacity') in ('0', '0.0'):
            return
        matrix = mul(matrix, parse_transform(el.get('transform')))

        if tag in ('svg', 'g'):
            for child in el:
                walk(child, props, matrix)
            return
        try:
            segs = shape_segments(el, tag)
        except (ValueError, IndexError):
            print(f'  skipped bad shape in {os.path.basename(path)}', file=sys.stderr)
            return
        if not segs:
            return

        data = []
        for seg in segs:
            pts = []
            for j in range(1, len(seg), 2):
                pts += apply(matrix, seg[j], seg[j + 1])
            data.append(seg[0] + ' '.join(fmt(v) for v in pts))
        d = ''.join(data)

        fill = props.get('fill', '#000')  # SVG default fill is black
        if is_paint(fill) and tag not in ('line', 'polyline'):
            ops.append(('E' if props.get('fill-rule') == 'evenodd' else 'F') + '0:' + d)
        if is_paint(props.get('stroke')):
            m = NUM_RE.match(props.get('stroke-width', '1').strip())
            width = float(m.group()) if m else 1.0
            width *= math.sqrt(abs(matrix[0] * matrix[3] - matrix[1] * matrix[2]))
            ratio = width / (pack['stroke'] * scale)  # relative to the pack's nominal stroke
            if ratio > 0:
                ops.append('S' + f'{ratio:.2f}'.rstrip('0').rstrip('.') + ':' + d)

    walk(root, {}, base)
    return ';'.join(ops) or None


def read_appfilter(path):
    """(package/activity, drawable) pairs from an ADW appfilter.xml."""
    text = open(path, encoding='utf-8').read()
    pairs = []
    for item in re.findall(r'<item\s[^>]*>', text):
        comp = re.search(r'component="([^"]*)"', item)
        draw = re.search(r'drawable="([^"]*)"', item)
        m = COMPONENT_RE.search(comp.group(1)) if comp else None
        if m and draw:
            pairs.append((f'{m.group(1)}/{m.group(2)}', draw.group(1)))
    return pairs


def build(name, src, keep_packages):
    pack = PACKS[name]
    svg_dir = os.path.join(src, pack['svg_dir'])
    available = {f[:-4] for f in os.listdir(svg_dir) if f.endswith('.svg')}

    mapping = {}
    for comp, icon in read_appfilter(os.path.join(src, pack['appfilter'])):
        if icon in available and comp not in mapping:
            if keep_packages is None or comp.split('/', 1)[0] in keep_packages:
                mapping[comp] = icon

    names = sorted(available if keep_packages is None else set(mapping.values()))
    icons = {}
    for n in names:
        try:
            ops = convert_svg(os.path.join(svg_dir, n + '.svg'), pack)
        except ET.ParseError:
            ops = None
        if ops:
            icons[n] = ops
    names = [n for n in names if n in icons]
    mapping = {c: i for c, i in mapping.items() if i in icons}

    out = os.path.join(OUT_DIR, name)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    with open(os.path.join(out, 'appfilter.tsv'), 'w', encoding='utf-8') as f:
        f.writelines(f'{c}\t{i}\n' for c, i in sorted(mapping.items()))
    with open(os.path.join(out, 'index.txt'), 'w', encoding='utf-8') as f:
        f.writelines(n + '\n' for n in names)
    for c in range(0, len(names), CHUNK_SIZE):
        with open(os.path.join(out, f'chunk_{c // CHUNK_SIZE:03d}.txt'), 'w', encoding='utf-8') as f:
            f.writelines(f'{n}\t{icons[n]}\n' for n in names[c:c + CHUNK_SIZE])
    if pack['license']:
        shutil.copy(os.path.join(src, pack['license']), os.path.join(out, 'LICENSE'))
    else:
        with open(os.path.join(out, 'NOTICE'), 'w', encoding='utf-8') as f:
            f.write('Arcticons by the Arcticons team (https://github.com/Arcticons-Team/Arcticons).\n'
                    'Icons licensed under CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/).\n'
                    'Converted to path data, rescaled and recoloured by Minimal Launcher; '
                    'the converted icons are shared under the same licence.\n')
    size = sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out))
    print(f'{name}: {len(names)} icons, {len(mapping)} app mappings, {size / 1e6:.1f} MB uncompressed')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--lawnicons', required=True)
    ap.add_argument('--arcticons', required=True)
    ap.add_argument('--arcticons-packages', help='only keep Arcticons icons for these packages (one per line)')
    args = ap.parse_args()
    keep = None
    if args.arcticons_packages:
        with open(args.arcticons_packages, encoding='utf-8') as f:
            keep = {line.strip().removeprefix('package:') for line in f if line.strip()}
    build('lawnicons', args.lawnicons, None)
    build('arcticons', args.arcticons, keep)


if __name__ == '__main__':
    main()
