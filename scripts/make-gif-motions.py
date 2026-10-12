#!/usr/bin/env python3
"""받은 GIF·그림에서 우사기만 떼어 내 동작(스프라이트 시트 + 시각표)을 만든다.

    python3 scripts/make-gif-motions.py [원본 폴더]   # 기본은 ~/Downloads
                                                      # Resources/Pets/usagi/<이름>.png, <이름>.json 생성
                                                      # (Pillow, OpenCV, numpy 필요)

- 배경이 이미 투명한 GIF 는 그대로 쓴다.
- 풍경 배경(서 있다가 물구나무)은 몸의 크림색에서 시작해 붙어 있는 분홍·흰색과 외곽선을 더해 떼어 낸다.
- 단색 배경(엎드린 그림)은 가장자리에서부터 배경색을 지우고 그림자와 글자를 뺀다.
- 선글라스와 빛 뿜기는 배경이 장면의 일부라 지우지 않는다. 프레임 전체를 모서리가 둥근 카드로 쓴다.
- 모든 동작은 끝나면 처음부터 다시 돈다 (기본 모습으로 돌아가지 않는다).
- 칸은 평소 시트와 같은 192×208 이고, 서 있는 우사기의 키·발 위치를 평소 시트에 맞춘다.
  한 동작 안에서는 모든 프레임을 같은 배율·같은 자리로 옮겨 뛰어오르는 움직임이 남는다.
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageSequence

ROOT = Path(__file__).resolve().parent.parent
PET = ROOT / "Resources/Pets/usagi"
CELL = (192, 208)
COLUMNS = 8


def disk(r):
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))


def largest(mask):
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    if n <= 1:
        return np.zeros_like(mask)
    return np.where(labels == 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA]), 255, 0).astype(np.uint8)


def fill_holes(mask):
    padded = cv2.copyMakeBorder(mask, 1, 1, 1, 1, cv2.BORDER_CONSTANT, value=0)
    flood = padded.copy()
    cv2.floodFill(flood, None, (0, 0), 255)
    return cv2.bitwise_or(padded, cv2.bitwise_not(flood))[1:-1, 1:-1]


def bbox(mask):
    ys, xs = np.where(mask > 24)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def read_frames(path):
    """(RGBA 그림, 보여 주는 시간 초) 목록."""
    image = Image.open(path)
    return [(np.array(frame.convert("RGBA")), frame.info.get("duration", 100) / 1000) for frame in ImageSequence.Iterator(image)]


def cut_cream(rgb):
    """풍경 배경에서 크림색 우사기를 떼어 낸다: 몸 색 → 붙어 있는 분홍(귀·볼)·흰색(모자 방울) → 외곽선."""
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    cream = ((h >= 17) & (h <= 28) & (s >= 42) & (s <= 75) & (v >= 247)).astype(np.uint8) * 255
    pink = (((h >= 160) | (h <= 8)) & (s >= 35) & (s <= 140) & (v >= 215)).astype(np.uint8) * 255
    white = ((s <= 14) & (v >= 240)).astype(np.uint8) * 255
    dark = (v < 125).astype(np.uint8) * 255
    body = largest(cv2.morphologyEx(cream, cv2.MORPH_OPEN, disk(2)))
    parts = cv2.morphologyEx(cv2.bitwise_or(cv2.bitwise_or(cream, pink), white), cv2.MORPH_OPEN, disk(1))
    n, labels, stats, _ = cv2.connectedComponentsWithStats(parts, 8)
    for _ in range(5):
        near = cv2.dilate(body, disk(9))
        for k in range(1, n):
            if stats[k, cv2.CC_STAT_AREA] >= 12 and (near[labels == k] > 0).any():
                body[labels == k] = 255
    joined = cv2.bitwise_or(body, cv2.bitwise_and(dark, cv2.dilate(body, disk(6))))
    filled = fill_holes(cv2.morphologyEx(joined, cv2.MORPH_CLOSE, disk(4)))
    mask = cv2.bitwise_or(filled, cv2.bitwise_and(dark, cv2.dilate(filled, disk(6))))
    return fill_holes(largest(cv2.morphologyEx(mask, cv2.MORPH_OPEN, disk(1))))


def cut_flat(rgb):
    """단색 배경에서 떼어 낸다: 가장자리와 이어진 배경색을 지우고, 발밑 그림자와 따로 떨어진 글자를 뺀다."""
    pixels = rgb.astype(np.int16)
    background = pixels[4, 4]
    same = (np.abs(pixels - background).max(2) < 28).astype(np.uint8) * 255
    padded = cv2.copyMakeBorder(same, 1, 1, 1, 1, cv2.BORDER_CONSTANT, value=255)
    cv2.floodFill(padded, None, (0, 0), 128)
    mask = np.where(padded[1:-1, 1:-1] == 128, 0, 255).astype(np.uint8)
    # 외곽선은 거의 검정(12 미만)이고 그림자는 30 안팎의 짙은 올리브색이다.
    brightest = pixels.max(2)
    shadow = cv2.morphologyEx(((brightest > 18) & (brightest < 70)).astype(np.uint8) * 255, cv2.MORPH_OPEN, disk(4))
    mask = cv2.bitwise_and(mask, cv2.bitwise_not(cv2.dilate(shadow, disk(3))))
    return fill_holes(largest(cv2.morphologyEx(mask, cv2.MORPH_OPEN, disk(3))))


def card_frames(frames, radius=0.09):
    """배경을 살리는 그림: 프레임 전체를 모서리가 둥근 카드로 쓴다."""
    height, width = frames[0][0].shape[:2]
    alpha = np.zeros((height, width), np.uint8)
    r = int(min(width, height) * radius)
    cv2.rectangle(alpha, (r, 0), (width - r - 1, height - 1), 255, -1)
    cv2.rectangle(alpha, (0, r), (width - 1, height - r - 1), 255, -1)
    for cx, cy in ((r, r), (width - r - 1, r), (r, height - r - 1), (width - r - 1, height - r - 1)):
        cv2.circle(alpha, (cx, cy), r, 255, -1, cv2.LINE_AA)
    result = []
    for frame, duration in frames:
        frame = frame.copy()
        frame[..., 3] = alpha
        result.append((frame, duration))
    return result


INK = np.array([24, 16, 12], np.float32)


def clean_lines(frame):
    """선과 면을 정리한다: 면은 압축 얼룩을 지워 고르게, 선은 한 가지 잉크색으로 다시 긋는다."""
    rgb = frame[..., :3]
    smooth = cv2.medianBlur(rgb, 5)
    # 선의 진하기: 어두울수록 1.
    line = np.clip((255 - smooth.max(2).astype(np.float32) - 60) / 110, 0, 1)
    line = cv2.GaussianBlur(line, (0, 0), 0.8)
    # 선 밑의 면 색을 둘레에서 끌어와 채우고 얼룩을 없앤다.
    under = cv2.dilate((line > 0.15).astype(np.uint8) * 255, disk(2))
    fill = cv2.medianBlur(cv2.inpaint(smooth, under, 5, cv2.INPAINT_TELEA), 7).astype(np.float32)
    out = frame.copy()
    out[..., :3] = (fill * (1 - line[..., None]) + INK * line[..., None]).astype(np.uint8)
    solid = (frame[..., 3] > 128).astype(np.uint8) * 255
    out[..., 3] = cv2.GaussianBlur(solid, (0, 0), 1.5)
    return out


def find_eyes(frame):
    """몸 안쪽의 크고 둥근 검은 덩어리 둘 (눈)의 (가운데 x, 가운데 y, 반지름)."""
    solid = (frame[..., 3] > 128).astype(np.uint8) * 255
    inner = cv2.erode(solid, disk(45))
    dark = ((frame[..., :3].max(2) < 90) & (inner > 0)).astype(np.uint8) * 255
    n, _, stats, centers = cv2.connectedComponentsWithStats(dark, 8)
    eyes = []
    for k in range(1, n):
        _, _, w, h, area = stats[k]
        # 눈은 거의 정사각형 칸에 꽉 찬 원이다 (눈썹·입·볼 줄은 길쭉하거나 듬성하다).
        if 0.8 < w / h < 1.25 and area > 0.55 * w * h and area > 800:
            eyes.append((float(centers[k][0]), float(centers[k][1]), max(w, h) / 2))
    assert len(eyes) == 2, f"눈을 {len(eyes)}개 찾았다"
    return eyes


def close_eyes(frame, eyes):
    """눈을 감긴다: 눈을 둘레의 살색으로 덮고 아래로 휜 짧은 선을 긋는다."""
    out = frame.copy()
    rgb = np.ascontiguousarray(out[..., :3])
    for cx, cy, r in eyes:
        skin = tuple(int(c) for c in rgb[int(cy - r - 14), int(cx)])
        cv2.circle(rgb, (int(cx), int(cy)), int(r + 5), skin, -1, cv2.LINE_AA)
        cv2.ellipse(rgb, (int(cx), int(cy - 2)), (int(r * 0.82), int(r * 0.42)), 0, 15, 165, tuple(int(c) for c in INK), 11, cv2.LINE_AA)
    out[..., :3] = rgb
    return out


def lying_idle(frame):
    """엎드려 뒤돌아보는 한 장으로 기본 모습의 움직임을 만든다: 숨쉬기, 눈 깜빡임, 귀 쫑긋.

    새 그림을 그리는 것이 아니라 한 장을 조금씩 늘이고 돌린 것이라 큰 동작(꼬리 흔들기, 고개 돌리기)은 없다.
    """
    frame = clean_lines(frame)
    eyes = find_eyes(frame)
    closed = close_eyes(frame, eyes)
    alpha = frame[..., 3]
    left, top, right, bottom = bbox(alpha)
    # 귀: 머리 위로 솟은 좁은 부분. 줄의 폭이 갑자기 넓어지기 직전까지.
    widths = (alpha > 128).sum(1)
    ear_width = np.median(widths[top + 20:top + 120])
    split = next(y for y in range(top + 20, bottom) if widths[y] > ear_width * 1.12)
    xs = np.where(alpha[split] > 128)[0]
    pivot = (float(xs.min() + xs.max()) / 2, float(split))
    foot = ((left + right) / 2, float(bottom))

    steps = 42                      # 0.1초씩 4.2초
    blink = {14, 15, 31}            # 눈 감는 칸
    twitch = {22: 4, 23: 7, 24: 3, 25: -2}  # 귀가 기우는 각도
    frames = []
    for step in range(steps):
        image = closed if step in blink else frame
        if step in twitch:
            ears = image.copy()
            ears[split:] = 0
            rest = image.copy()
            rest[:split] = 0
            turn = cv2.getRotationMatrix2D(pivot, twitch[step], 1.0)
            ears = cv2.warpAffine(ears, turn, (image.shape[1], image.shape[0]), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0, 0))
            # 돌린 귀를 몸 위에 얹는다.
            weight = ears[..., 3:4].astype(np.float32) / 255
            image = rest.copy()
            image[..., :3] = (ears[..., :3] * weight + rest[..., :3] * (1 - weight)).astype(np.uint8)
            image[..., 3] = np.maximum(ears[..., 3], rest[..., 3])
        # 숨쉬기: 발은 그대로 두고 위로 살짝 부풀었다 가라앉는다 (2.1초에 한 번).
        breath = 0.5 - 0.5 * np.cos(2 * np.pi * step / 21)
        sx, sy = 1 - 0.012 * breath, 1 + 0.024 * breath
        swell = np.float32([[sx, 0, foot[0] * (1 - sx)], [0, sy, foot[1] * (1 - sy)]])
        image = cv2.warpAffine(image, swell, (image.shape[1], image.shape[0]), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0, 0))
        frames.append((image, 0.1))
    return frames


def standing_reference():
    """평소 시트에서 서 있는 우사기의 폭·키와 발 아래 여백."""
    sheet = cv2.imread(str(PET / "spritesheet.png"), cv2.IMREAD_UNCHANGED)
    cell = sheet[9 * CELL[1]:10 * CELL[1], 0:CELL[0], 3]
    left, top, right, bottom = bbox(cell)
    return int(right - left), int(bottom - top), int(CELL[1] - bottom)


def build(name, frames, *, fit, size, hold=0.0):
    """동작 하나를 시트와 시각표로 쓴다.

    fit: "height" 면 첫 프레임의 키를, "width" 면 폭을 `size` 픽셀에 맞춘다.
    hold: 한 바퀴 돌 때마다 마지막 프레임에서 더 머무는 시간(초).
    """
    _, _, margin = standing_reference()
    boxes = [bbox(frame[..., 3]) for frame, _ in frames]
    box = boxes[0]
    scale = size / (box[3] - box[1] if fit == "height" else box[2] - box[0])
    left, top = min(b[0] for b in boxes), min(b[1] for b in boxes)
    right, bottom = max(b[2] for b in boxes), max(b[3] for b in boxes)
    # 칸에 다 들어가지 않으면 줄인다.
    scale = min(scale, (CELL[0] - 4) / (right - left), (CELL[1] - margin - 2) / (bottom - top))
    # 전체 움직임의 가로 가운데를 칸 가운데에, 가장 낮은 곳을 발 높이에 둔다.
    shift_x = CELL[0] / 2 - (left + right) / 2 * scale
    shift_y = (CELL[1] - margin) - bottom * scale
    matrix = np.float32([[scale, 0, shift_x], [0, scale, shift_y]])
    interpolation = cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC

    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    sheet = np.zeros((rows * CELL[1], COLUMNS * CELL[0], 4), np.uint8)
    times, clock = [], 0.0
    for index, (frame, duration) in enumerate(frames):
        cell = cv2.warpAffine(frame, matrix, CELL, flags=interpolation, borderValue=(0, 0, 0, 0))
        cell[cell[..., 3] == 0] = 0
        y, x = (index // COLUMNS) * CELL[1], (index % COLUMNS) * CELL[0]
        sheet[y:y + CELL[1], x:x + CELL[0]] = cell
        times.append(round(clock, 3))
        clock += duration
    Image.fromarray(sheet).save(PET / f"{name}.png")
    manifest = {
        "spritesheetPath": f"{name}.png",
        "cellWidth": CELL[0],
        "cellHeight": CELL[1],
        "columns": COLUMNS,
        "times": times,
        "end": round(clock + hold, 3),
        "loop": True,
    }
    (PET / f"{name}.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"✔ {name}: {len(frames)}칸, 배율 {scale:.3f}, 한 바퀴 {clock + hold:.2f}초")


def replace_sheet_row(row, name, picks):
    """평소 시트의 한 줄을 만든 동작의 칸들로 바꾼다 (시트만 쓰는 곳에서도 같은 그림이 나오도록).

    앱은 `pet.json` 의 `motions` 를 따라 이 줄에서 동작 전체(칸이 더 많다)를 재생한다.
    """
    sheet = Image.open(PET / "spritesheet.png").convert("RGBA")
    motion = Image.open(PET / f"{name}.png").convert("RGBA")
    y = row * CELL[1]
    sheet.paste(Image.new("RGBA", (sheet.width, CELL[1]), (0, 0, 0, 0)), (0, y))
    for column, index in enumerate(picks[:COLUMNS]):
        x0, y0 = (index % COLUMNS) * CELL[0], (index // COLUMNS) * CELL[1]
        sheet.paste(motion.crop((x0, y0, x0 + CELL[0], y0 + CELL[1])), (column * CELL[0], y))
    sheet.save(PET / "spritesheet.png")
    print(f"✔ spritesheet.png 의 {row + 1}번째 줄을 {name} 으로 바꿈")


def with_mask(frames, cut):
    """배경이 있는 프레임에 떼어 낸 모양을 투명도로 넣는다."""
    result = []
    for frame, duration in frames:
        frame = frame.copy()
        # 원본에 이미 투명한 곳이 있으면 그대로 둔다.
        frame[..., 3] = np.minimum(frame[..., 3], cv2.GaussianBlur(cut(frame[..., :3]), (0, 0), 0.8))
        result.append((frame, duration))
    return result


def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "Downloads"
    width, height, _ = standing_reference()

    # 엎드려 뒤돌아보기: 시트의 8번째 줄(말풍선을 열어 둔 동안의 모습)을 대신한다. 한 장을 정리하고 숨쉬기·깜빡임·귀 쫑긋을 넣는다.
    lying = with_mask(read_frames(source / "usagi-is-not-even-fat-v0-5211hb4qecxe1.webp"), cut_flat)
    build("lying", lying_idle(lying[0][0]), fit="height", size=height * 0.9)
    replace_sheet_row(7, "lying", [0, 5, 10, 14, 18, 23, 27, 31])
    # 서 있다가 털모자를 쓰고 물구나무: 끝 자세로 잠깐 머물렀다가 다시 돈다.
    flip = with_mask(read_frames(source / "bc9dc013aa09e3c8856f18063d244273.gif"), cut_cream)
    build("flip", flip, fit="height", size=height, hold=1.0)
    # 팔짱 끼고 귀 쫑긋거리며 말하기 (가슴 위만 나온 그림).
    build("arms", read_frames(source / "2467b95ff2d74e2fa96ad8db9904ad6c.gif"), fit="width", size=width * 1.15)
    # 옆으로 서서 꼬리 흔들며 돌아보기.
    build("tail", read_frames(source / "df7097c0ea064161a432815422d0fe37.gif"), fit="height", size=height)
    # 신나서 폴짝 뛰기.
    build("jump", read_frames(source / "8c7e20ea2b244367a413df9c26fb92e7 (1).gif"), fit="height", size=height * 0.95)
    # 선글라스 끼고 으스대기, 눈에서 빛 뿜기: 배경째 카드로.
    build("shades", card_frames(read_frames(source / "2223db05c61ee10b8fb6e3783e8864a3.gif")), fit="width", size=CELL[0] - 8)
    build("glow", card_frames(read_frames(source / "aeca435fa18848edbc511ec8f91c8f8f.gif")), fit="width", size=CELL[0] - 8)


if __name__ == "__main__":
    main()
