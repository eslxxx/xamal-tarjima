#!/usr/bin/env python3
"""把一张成品图标 PNG 切成安卓要的整套 launcher 图标。

源图是一张 1:1 的成品图标 (自带圆角和蓝底, 圆角外面是白的)。这个脚本:

  1. 找到蓝色圆角方块的范围, 把外面那圈白边裁掉;
  2. 量出圆角半径, 给传统图标 (mipmap-*/ic_launcher.png) 加透明圆角 ——
     不裁的话白角会在深色启动器里露出来;
  3. 生成自适应图标 (Android 8+, 本项目 minSdk=26 所以**所有**设备都走这条路):
       背景层 = 源图放大到满幅再高斯模糊, 得到一块和原图配色一致的蓝色渐变;
       前景层 = 源图缩到安全区里居中放。
     背景层刻意用"模糊过的自己"而不是纯色: 前景那块圆角方块的边缘颜色和背后
     几乎一样, 圆角接缝看不出来; 纯色底会在渐变的上下两端露出色差。
  4. 顺手渲染 out/icon_preview.png —— 圆形/方形/squircle 三种遮罩各切一份,
     方便肉眼确认气泡没有被裁掉。

用法:
    python tools/make_icon.py art/icon_src.png
    python tools/make_icon.py art/icon_src.png --probe   # 只打印测量结果, 不写文件

源图存在 art/icon_src.png (不进 APK, 只为以后能重新生成)。
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'app' / 'android' / 'app' / 'src' / 'main' / 'res'
OUT = ROOT / 'out'

# 传统图标边长 (dp = px @ 各密度)
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
# 自适应图标一律 108dp 画布
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

# 前景里源图占画布的比例。108dp 画布中间 72dp 是各种遮罩都保证可见的区域。
# 0.68 是照着 out/icon_preview.png 挑的: 再大一点 (0.76 以上) 圆形遮罩就会切到
# 左边白气泡的边; 再小一点 (0.60) 图标在桌面上比邻居明显小一圈。
FG_SCALE = 0.68

# "这是内容不是蓝底" 的亮度阈值。蓝底亮度约 110~130, 半透明白箭头约 186, 纯白 255。
CONTENT_LUM = 150


def lum(p) -> float:
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


def crop_to_square(im: Image.Image) -> tuple[Image.Image, int]:
    """裁掉圆角外面的白边, 返回 (裁好的图, 圆角半径)。"""
    rgb = im.convert('RGB')
    w, h = rgb.size
    px = rgb.load()

    def is_white(p):
        return p[0] > 240 and p[1] > 240 and p[2] > 240

    # 沿中轴找蓝块的四个边界 —— 中轴一定穿过蓝底, 不会被圆角干扰
    cx, cy = w // 2, h // 2
    top = next(y for y in range(h) if not is_white(px[cx, y]))
    bot = next(y for y in range(h - 1, -1, -1) if not is_white(px[cx, y]))
    left = next(x for x in range(w) if not is_white(px[x, cy]))
    right = next(x for x in range(w - 1, -1, -1) if not is_white(px[x, cy]))
    box = (left, top, right + 1, bot + 1)

    # 圆角半径: 从蓝块顶边往下走, 第一次出现"这一行最左的蓝像素就贴着左边界"
    # 的那个高度, 就是圆角半径
    radius = 0
    for y in range(top, min(top + (bot - top) // 2, h)):
        row_left = next((x for x in range(left, right + 1) if not is_white(px[x, y])), right)
        if row_left <= left + 1:
            radius = y - top
            break

    return rgb.crop(box), max(radius, 1)


def content_box(sq: Image.Image, radius_frac: float) -> tuple[int, int, int, int]:
    """气泡 + 箭头 (比蓝底亮的那些像素) 的外接框。

    两个坑:
      - 圆角外面那四块是纯白, 不排除掉外接框会直接等于整张图;
      - 缩图必须用 BOX 而不是 LANCZOS。LANCZOS 在蓝/白这种硬边上会过冲, 在边界
        内侧留一圈比白还亮的振铃, 于是"内容"被误判到贴边。
      所以判定区域再往里收 3%, 把边界那一圈整个让开。
    """
    n = 256
    px = sq.resize((n, n), Image.BOX).load()
    pad = round(n * 0.03)
    inner = Image.new('L', (n, n), 0)
    m = rounded_mask(n - 2 * pad, max(1, round((n - 2 * pad) * radius_frac)))
    inner.paste(m, (pad, pad))
    inside = inner.load()

    xs, ys = [], []
    for y in range(n):
        for x in range(n):
            if inside[x, y] > 250 and lum(px[x, y]) > CONTENT_LUM:
                xs.append(x)
                ys.append(y)
    if not xs:
        return (0, 0, sq.size[0], sq.size[1])
    k = sq.size[0] / n
    return (int(min(xs) * k), int(min(ys) * k), int(max(xs) * k), int(max(ys) * k))


def rounded_mask(size: int, radius: int) -> Image.Image:
    """4 倍超采样画一个圆角矩形遮罩, 边缘才不会有锯齿。"""
    ss = 4
    m = Image.new('L', (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, size * ss - 1, size * ss - 1), radius=radius * ss, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def legacy_icon(sq: Image.Image, radius_frac: float, size: int) -> Image.Image:
    im = sq.resize((size, size), Image.LANCZOS).convert('RGBA')
    im.putalpha(rounded_mask(size, max(1, round(size * radius_frac))))
    return im


def adaptive_background(sq: Image.Image, size: int) -> Image.Image:
    """满幅的蓝色渐变底。

    做法是沿着蓝块左右两条边取色 (那两列是干净的蓝底, 没有气泡), 逐行插值铺满。
    **不能**用"把源图糊掉"那招: 高斯模糊会把圆角外面那四块白角糊进来, 整块底色
    被提亮, 于是前景那块圆角方块四周会出现一道明显的亮边, 看起来像给图标描了个框。
    """
    n = sq.size[0]
    rgb = sq.convert('RGB')
    px = rgb.load()
    inx = max(2, round(n * 0.06))          # 往里 6%, 避开圆角和边缘的抗锯齿
    row = Image.new('RGB', (2, size))
    rp = row.load()
    for y in range(size):
        sy = min(n - 1, round((y + 0.5) / size * n))
        rp[0, y] = px[inx, sy]
        rp[1, y] = px[n - 1 - inx, sy]
    return row.resize((size, size), Image.BICUBIC).convert('RGBA')


def adaptive_foreground(sq: Image.Image, radius_frac: float, size: int,
                        scale: float = FG_SCALE) -> Image.Image:
    inner = max(1, round(size * scale))
    art = legacy_icon(sq, radius_frac, inner)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    canvas.paste(art, (off, off), art)
    return canvas


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- 自适应图标。minSdk=26, 所以这是所有设备实际用的那一份;
     mipmap-*/ic_launcher.png 只留给应用商店列表和个别老启动器。
     由 tools/make_icon.py 生成, 不要手改。 -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""


def preview(sq: Image.Image, radius_frac: float, path: Path,
            scales=(0.60, 0.68, 0.76, 0.84)) -> None:
    """每个缩放比 × 三种遮罩渲染一格, 用来肉眼挑 FG_SCALE。

    遮罩都画在中间 72/108 的范围里 —— 那是各家启动器最多裁到的那一圈。
    圆形是最狠的一种 (气泡的圆角最容易被切), 圆角方形接近 vivo / 小米的实际形状。
    """
    s, pad = 216, 14
    inset = round(s * (108 - 72) / 108 / 2)

    def masks():
        circle = Image.new('L', (s, s), 0)
        ImageDraw.Draw(circle).ellipse((inset, inset, s - inset - 1, s - inset - 1), fill=255)
        squircle = Image.new('L', (s, s), 0)
        ImageDraw.Draw(squircle).rounded_rectangle(
            (inset, inset, s - inset - 1, s - inset - 1), radius=round(s * 0.16), fill=255)
        square = Image.new('L', (s, s), 0)
        ImageDraw.Draw(square).rounded_rectangle(
            (inset, inset, s - inset - 1, s - inset - 1), radius=round(s * 0.05), fill=255)
        return [circle, squircle, square]

    cols = len(scales)
    sheet = Image.new('RGB', (pad + cols * (s + pad), pad + 3 * (s + pad)), (0x1B, 0x1F, 0x25))
    bg = adaptive_background(sq, s)
    for c, sc in enumerate(scales):
        full = Image.alpha_composite(bg, adaptive_foreground(sq, radius_frac, s, sc))
        for r, m in enumerate(masks()):
            one = full.copy()
            one.putalpha(m)
            sheet.paste(one, (pad + c * (s + pad), pad + r * (s + pad)), one)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)
    print('预览各档缩放  ' + '  '.join(f'{v:.2f}' for v in scales) + '  (从左到右)')


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        print(__doc__)
        return 2
    src = Path(args[0])
    im = Image.open(src)
    if im.size[0] != im.size[1]:
        print(f'源图不是正方形: {im.size}')
        return 1

    sq, radius = crop_to_square(im)
    radius_frac = radius / sq.size[0]
    cb = content_box(sq, radius_frac)
    n = sq.size[0]
    # 内容框换算成 108dp 画布上的坐标, 和安全区 (18..90) 比一比
    inner = FG_SCALE * 108
    off = (108 - inner) / 2
    lo = off + cb[0] / n * inner
    hi = off + cb[2] / n * inner
    ty = off + cb[1] / n * inner
    by = off + cb[3] / n * inner

    print(f'源图        {im.size[0]}px')
    print(f'蓝块        {n}px  圆角半径 {radius}px ({radius_frac:.1%})')
    print(f'内容框      x {cb[0]}..{cb[2]}  y {cb[1]}..{cb[3]} (蓝块内)')
    print(f'FG_SCALE {FG_SCALE:.2f} 后落在 108dp 画布  x {lo:.1f}..{hi:.1f}  y {ty:.1f}..{by:.1f}')
    print('安全区      方形遮罩 18..90')
    sq_ok = lo >= 18 and hi <= 90 and ty >= 18 and by <= 90
    # 圆形遮罩是最狠的一种: 直径 72 的内切圆, 半径 36。四个角要都在圆里面。
    need = max(abs(x - 54) ** 2 + abs(y - 54) ** 2
               for x in (lo, hi) for y in (ty, by)) ** 0.5
    print(f'            方形遮罩: {"通过" if sq_ok else "**内容出界, 把 FG_SCALE 调小**"}'
          f'   圆形遮罩: 需要半径 {need:.1f} / 可用 36 '
          f'{"通过" if need <= 36 else "→ 圆形启动器上气泡边缘会被切掉一点"}')

    preview(sq, radius_frac, OUT / 'icon_preview.png')
    print('预览        out/icon_preview.png')

    if '--probe' in sys.argv:
        return 0

    for d, size in LEGACY.items():
        p = RES / f'mipmap-{d}' / 'ic_launcher.png'
        legacy_icon(sq, radius_frac, size).save(p)
    for d, size in ADAPTIVE.items():
        adaptive_background(sq, size).save(RES / f'mipmap-{d}' / 'ic_launcher_background.png')
        adaptive_foreground(sq, radius_frac, size).save(
            RES / f'mipmap-{d}' / 'ic_launcher_foreground.png')
    anydpi = RES / 'mipmap-anydpi-v26'
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / 'ic_launcher.xml').write_text(ADAPTIVE_XML, encoding='utf-8')
    print(f'已写入      {len(LEGACY)} 个传统图标 + {len(ADAPTIVE) * 2} 张自适应图层 + anydpi-v26/ic_launcher.xml')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
