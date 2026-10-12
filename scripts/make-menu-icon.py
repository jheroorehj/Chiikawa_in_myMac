#!/usr/bin/env python3
"""선으로만 그린 그림을 메뉴바 아이콘으로 만든다.

    python3 scripts/make-menu-icon.py <원본.png>   # Resources/MenuIcon.png, IconArt.png 생성 (Pillow 필요)

원본은 몸 안쪽이 투명한 검은 선 그림이라 어두운 메뉴바에서 보이지 않는다.
여백을 잘라 내고 몸 안쪽을 흰색으로 채워 밝은·어두운 메뉴바 모두에서 보이게 한다.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
# 선이 끊긴 틈을 메우는 폭(픽셀). 틈보다 커야 바깥에서 채운 색이 안으로 새지 않는다.
GAP = 31

source = Image.open(sys.argv[1]).convert("RGBA")
solid = source.getchannel("A").point(lambda v: 255 if v > 128 else 0)

# 가장자리에 흩어진 점은 빼고 캐릭터만 남긴다.
box = solid.filter(ImageFilter.MinFilter(3)).getbbox()
box = (box[0] - GAP, box[1] - GAP, box[2] + GAP, box[3] + GAP)
source, solid = source.crop(box), solid.crop(box)

# 틈을 메운 뒤 바깥에서부터 칠해, 칠해지지 않은 곳을 몸 안쪽으로 본다.
closed = solid.filter(ImageFilter.MaxFilter(GAP))
outside = closed.copy()
ImageDraw.floodfill(outside, (0, 0), 128)
inside = outside.point(lambda v: 0 if v == 128 else 255)
# 메우느라 부푼 만큼 되돌리되, 선 바깥으로 흰색이 비어져 나오지 않게 조금 더 줄인다.
inside = inside.filter(ImageFilter.MinFilter(GAP)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1))

fill = Image.new("RGBA", source.size, (255, 255, 255, 0))
fill.putalpha(inside)
icon = Image.alpha_composite(fill, source)
icon = icon.crop(ImageChops.lighter(inside, solid).getbbox())
# 앱 아이콘(scripts/make-app-icon.py)이 쓰는 큰 그림.
icon.save(ROOT / "Resources/IconArt.png")
# 메뉴바에서는 18pt 로 보이므로 큰 원본을 그대로 둘 필요가 없다.
icon.thumbnail((144, 144), Image.LANCZOS)
icon.save(ROOT / "Resources/MenuIcon.png")
print("✔ Resources/IconArt.png, Resources/MenuIcon.png", icon.size)
