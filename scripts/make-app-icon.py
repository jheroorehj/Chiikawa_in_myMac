#!/usr/bin/env python3
"""메뉴바 아이콘과 같은 그림으로 앱 아이콘을 만든다.

    python3 scripts/make-app-icon.py   # Resources/AppIcon.icns 생성 (Pillow, iconutil 필요)

그림은 scripts/make-menu-icon.py 가 만든 Resources/IconArt.png 를 쓴다.
"""
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
pet = Image.open(ROOT / "Resources/IconArt.png").convert("RGBA")
pet = pet.crop(pet.getbbox())

SIZE = 1024
icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
# macOS 아이콘 격자: 824px 둥근 사각형을 가운데에.
plate = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ImageDraw.Draw(plate).rounded_rectangle((100, 100, 924, 924), radius=185, fill=(255, 236, 240, 255))
icon.alpha_composite(plate)
scale = 640 / max(pet.size)
pet = pet.resize((round(pet.width * scale), round(pet.height * scale)), Image.LANCZOS)
icon.alpha_composite(pet, ((SIZE - pet.width) // 2, (SIZE - pet.height) // 2))

with tempfile.TemporaryDirectory() as tmp:
    iconset = Path(tmp) / "AppIcon.iconset"
    iconset.mkdir()
    for points in (16, 32, 128, 256, 512):
        for factor in (1, 2):
            pixels = points * factor
            suffix = "" if factor == 1 else "@2x"
            icon.resize((pixels, pixels), Image.LANCZOS).save(iconset / f"icon_{points}x{points}{suffix}.png")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ROOT / "Resources/AppIcon.icns")], check=True)
print("✔ Resources/AppIcon.icns")
