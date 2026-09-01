#!/usr/bin/env python3
"""生成下载页 (site/) 要用的两张图, 以 base64 常量写进 site/src/icon.ts。

  /icon.png  512px 圆角图标 —— 页头品牌图、favicon、og:image 共用一张。
             从 art/icon_src.png 切 (复用 make_icon.py 的裁切/圆角逻辑,
             保证和 App 桌面图标是同一张源图)。
  /qr.png    指向 https://logat.xamal.top 的二维码 —— 给电脑访客扫。
             模块用近黑的墨色而不是品牌蓝: 二维码首先要好扫,
             深蓝在弱光下偶发识别失败, 不值得。

整页没有别的外部图片, 图标全内嵌在 Worker 里 —— 下载页的可用性不该
依赖第三方图床。

用法:
    python tools/make_site_icon.py
改下载页域名时改下面的 PAGE_URL 再跑一次。
"""

from __future__ import annotations

import base64
import io
import sys
from pathlib import Path

import qrcode
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_icon import crop_to_square, legacy_icon  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SITE_SRC = ROOT / 'site' / 'src'
PAGE_URL = 'https://logat.xamal.top'
INK = '#1A1D22'  # 墨色, 和页面正文同色


def png_b64(im: Image.Image) -> str:
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return base64.b64encode(buf.getvalue()).decode()


def main() -> int:
    src = Image.open(ROOT / 'art' / 'icon_src.png')
    sq, radius = crop_to_square(src)
    icon = legacy_icon(sq, radius / sq.size[0], 512)
    # LANCZOS 抗锯齿 + 渐变底会产生几万个相近色, 真彩 PNG 要 264KB;
    # 这张图本来就近乎纯色, 量化到 256 色只有 22KB, 肉眼看不出差别。
    icon = icon.quantize(colors=256, method=Image.Quantize.FASTOCTREE)

    qr = qrcode.QRCode(
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=16, border=2,
    )
    qr.add_data(PAGE_URL)
    qr.make(fit=True)
    qr_im = qr.make_image(fill_color=INK, back_color='white').convert('RGB')

    icon_b64 = png_b64(icon)
    qr_b64 = png_b64(qr_im)
    SITE_SRC.mkdir(parents=True, exist_ok=True)
    (SITE_SRC / 'icon.ts').write_text(
        '// 由 tools/make_site_icon.py 生成, 不要手改。\n'
        f'// 图标 {icon.size[0]}px / {len(icon_b64) * 3 // 4 // 1024}KB,'
        f' 二维码 {qr_im.size[0]}px / {len(qr_b64) * 3 // 4 // 1024}KB。\n'
        f'export const ICON_PNG_B64 = "{icon_b64}";\n'
        f'export const QR_PNG_B64 = "{qr_b64}";\n',
        encoding='utf-8')

    print(f'图标   {icon.size[0]}px  {len(icon_b64) * 3 // 4 // 1024}KB  (base64 {len(icon_b64) // 1024}KB)')
    print(f'二维码 {qr_im.size[0]}px  {len(qr_b64) * 3 // 4 // 1024}KB  (base64 {len(qr_b64) // 1024}KB)')
    print(f'写入   site/src/icon.ts')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
