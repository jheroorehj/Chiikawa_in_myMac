#!/usr/bin/env python3
"""노래 장면 녹화본에서 우사기만 떼어 내 특수 모션(스프라이트 시트 + 시각표)을 만든다.

    python3 scripts/make-song-motion.py <녹화.mov>   # Resources/Pets/usagi/song.png, song.json 생성
                                                     # (ffmpeg, OpenCV, numpy 필요)

- 영상을 초당 24장으로 뽑아 그림이 실제로 바뀌는 프레임만 남긴다 (원작은 같은 그림을 여러 프레임 쓴다).
- 프레임마다 배경을 지우고 우사기만 남긴다: 노란 옷 + 그 안의 얼굴 + 외곽선 + 흰 꼬리.
- 춤(영상 0~6.18초): 모든 프레임을 같은 영역·같은 배율로 잘라, 좌우로 오가고 폴짝 뛰는 움직임이 그대로 남게 한다.
- 마무리(영상 7.68초~): 장면이 바뀌어 우사기가 멀리 작게 나온다. 춤과 같은 크기가 되도록 키워서 떼어 내고,
  춤의 처음 자리(칸의 가운데)에 세운다. 가만히 서 있다가 "부릿!"에 맞춰 다리를 꼰다.
- 그 사이의 얼굴 클로즈업(6.18~7.68초)은 몸이 화면 밖이라 쓸 수 없다. 같은 표정·자세인 서 있는 프레임으로 대신한다.
- 각 프레임의 시각은 음성 파일 기준(초)이다. 음성은 영상의 VOICE_OFFSET 초 지점에서 시작한다
  (영상 소리와 음성 파일의 포락선을 맞대어 구한 값).
- 음성 파일은 영상보다 "부릿!" 앞의 쉬는 시간이 1.5초쯤 짧다 (영상 8.82초 ↔ 음성 6.85초).
  그래서 마무리 프레임은 "부릿!"을 기준으로 시각을 옮기고, 서 있는 시간이 그만큼 줄어든다.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
PET = ROOT / "Resources/Pets/usagi"
FPS = 24
VOICE_OFFSET = 0.48
# 춤이 끝나고 얼굴이 크게 잡히는 때, 장면이 바뀌어 멀리 서 있는 모습이 나오는 때 (영상 시각).
DANCE_END = 6.18
WIDE_START = 7.68
# 멀리 잡힌 장면은 색이 옅다 (옷의 채도 90쯤, 얼굴 70, 땅 32). 얼굴까지 함께 잡히도록 한계를 낮춘다.
WIDE_SATURATION = 55
# "부릿!" 소리가 시작하는 때: 영상에서, 그리고 음성 파일에서.
VIDEO_FINALE = 8.82
VOICE_FINALE = 6.85
# 마지막 자세로 멈춰 있다가 특수 모션을 끝내는 때 (음성 기준). 음성은 7.39초에 끝난다.
MOTION_END = 8.3
# "부릿!"만 따로 쓸 때: 음성 파일에서 잘라 내기 시작하는 때와, 동작이 한 바퀴 도는 시간.
BURIT_START = 6.7
BURIT_LOOP = 1.6
CELL = (192, 208)
COLUMNS = 8


def disk(r):
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))


def largest(mask):
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    if n <= 1:
        return np.zeros_like(mask)
    k = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    return np.where(labels == k, 255, 0).astype(np.uint8)


def fill_holes(mask):
    padded = cv2.copyMakeBorder(mask, 1, 1, 1, 1, cv2.BORDER_CONSTANT, value=0)
    flood = padded.copy()
    cv2.floodFill(flood, None, (0, 0), 255)
    return cv2.bitwise_or(padded, cv2.bitwise_not(flood))[1:-1, 1:-1]


def yellowish(bgr, saturation):
    """노란 옷 색인 곳. `saturation` 은 채도의 아래 한계 (땅은 30쯤, 옷은 장면에 따라 90~130)."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    return ((h >= 16) & (h <= 32) & (s >= saturation) & (v >= 190)).astype(np.uint8) * 255


def segment(bgr, saturation=95):
    """우사기가 있는 곳의 마스크(0/255)를 돌려준다."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    yellow = cv2.morphologyEx(yellowish(bgr, saturation), cv2.MORPH_OPEN, disk(2))
    body = largest(yellow)
    # 팔·다리·귀처럼 외곽선으로 떨어진 노란 조각을 가까운 것부터 붙인다.
    n, labels, stats, _ = cv2.connectedComponentsWithStats(yellow, 8)
    for _ in range(4):
        near = cv2.dilate(body, disk(16))
        for k in range(1, n):
            if stats[k, cv2.CC_STAT_AREA] >= 60 and (near[labels == k] > 0).any():
                body[labels == k] = 255
    dark = (v < 125).astype(np.uint8) * 255
    # 조각 사이의 외곽선을 메워 한 덩어리로 만들고 안쪽(얼굴)을 채운다.
    joined = cv2.bitwise_or(body, cv2.bitwise_and(dark, cv2.dilate(body, disk(9))))
    filled = fill_holes(cv2.morphologyEx(joined, cv2.MORPH_CLOSE, disk(6)))
    # 바깥 외곽선: 몸 가까이의 어두운 선.
    mask = cv2.bitwise_or(filled, cv2.bitwise_and(dark, cv2.dilate(filled, disk(10))))
    # 흰 꼬리: 몸에 붙은 새하얀 덩어리.
    white = cv2.morphologyEx(((s < 16) & (v > 240)).astype(np.uint8) * 255, cv2.MORPH_OPEN, disk(2))
    n, labels, stats, _ = cv2.connectedComponentsWithStats(white, 8)
    near = cv2.dilate(mask, disk(14))
    for k in range(1, n):
        if 150 <= stats[k, cv2.CC_STAT_AREA] <= 9000 and (near[labels == k] > 0).any():
            mask = cv2.bitwise_or(mask, cv2.dilate(np.where(labels == k, 255, 0).astype(np.uint8), disk(3)))
    return fill_holes(largest(cv2.morphologyEx(mask, cv2.MORPH_OPEN, disk(2))))


def bbox(mask):
    ys, xs = np.where(mask > 0)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def standing_reference():
    """평소 시트에서 서 있는 우사기의 키와 발 아래 여백 (특수 모션의 크기·위치를 여기에 맞춘다)."""
    sheet = cv2.imread(str(PET / "spritesheet.png"), cv2.IMREAD_UNCHANGED)
    cell = sheet[9 * CELL[1]:10 * CELL[1], 0:CELL[0], 3]
    _, top, _, bottom = bbox(np.where(cell > 24, 255, 0).astype(np.uint8))
    return bottom - top, CELL[1] - bottom


def unique_frames(video, start, duration, threshold):
    """구간을 초당 FPS 장으로 뽑아, 직전 그림과 눈에 띄게 다른 프레임만 (영상 시각, 그림)으로 돌려준다."""
    with tempfile.TemporaryDirectory() as tmp:
        command = ["ffmpeg", "-v", "error", "-ss", str(start), "-i", video]
        if duration is not None:
            command += ["-t", str(duration)]
        subprocess.run(command + ["-vf", f"fps={FPS}", f"{tmp}/%04d.png"], check=True)
        frames = []
        previous = None
        for index, path in enumerate(sorted(Path(tmp).glob("*.png"))):
            image = cv2.imread(str(path))
            small = cv2.resize(image, (352, 198)).astype(np.int16)
            if previous is None or np.mean(np.abs(small - previous).max(2) > 24) > threshold:
                frames.append((start + index / FPS, image))
                previous = small
    return frames


def main():
    video = sys.argv[1]
    dance = [(time, image, segment(image)) for time, image in unique_frames(video, 0, DANCE_END - 0.04, 0.006)]
    boxes = [bbox(mask) for _, _, mask in dance]
    # 귀를 세우고 선 프레임들의 키(중앙값)를 평소 시트의 키에 맞춘다.
    height, bottom_margin = standing_reference()
    dance_height = float(np.median([b[3] - b[1] for b in boxes]))
    scale = height / dance_height
    # 처음 선 자리를 가로 가운데로 삼고, 모든 프레임이 들어가도록 좌우를 같은 폭으로 잡는다.
    home = (boxes[1][0] + boxes[1][2]) / 2
    ground = max(b[3] for b in boxes)
    reach = max(max(home - b[0], b[2] - home) for b in boxes) + 6
    top = min(b[1] for b in boxes) - 6
    cell_w = int(np.ceil(reach * 2 * scale / 2) * 2)

    # 마무리: 멀리 작게 나온 우사기를 춤과 같은 크기로 키운 뒤 떼어 낸다 (작은 그림에는 떼어 내는 기준이 맞지 않는다).
    wide = unique_frames(video, WIDE_START, None, 0.003)
    first = wide[0][1]
    x0, y0, x1, y1 = bbox(largest(cv2.morphologyEx(yellowish(first, WIDE_SATURATION), cv2.MORPH_OPEN, disk(2))))
    pad = int((y1 - y0) * 0.6)
    crop = (max(0, x0 - pad), max(0, y0 - pad), min(first.shape[1], x1 + pad), min(first.shape[0], y1 + pad))

    def enlarged(image, zoom):
        part = image[crop[1]:crop[3], crop[0]:crop[2]]
        part = cv2.resize(part, None, fx=zoom, fy=zoom, interpolation=cv2.INTER_CUBIC)
        return part, segment(part, WIDE_SATURATION)

    # 춤에서 귀를 세우고 바로 선 프레임(세 번째)과 키가 같아지도록 확대 배율을 정한다.
    standing_height = boxes[2][3] - boxes[2][1]
    zoom = standing_height / (y1 - y0)
    _, mask = enlarged(first, zoom)
    zoom *= standing_height / (bbox(mask)[3] - bbox(mask)[1])
    finale = [(time, *enlarged(image, zoom)) for time, image in wide]

    # 서 있는 첫 프레임의 발이 춤의 처음 자리·땅 높이에 오도록 맞추고, 뒤 프레임도 같은 만큼 옮긴다.
    bx0, _, bx1, by1 = bbox(finale[0][2])
    finale_left = (bx0 + bx1) / 2 - reach
    finale_ground = by1
    # 다리를 꼬며 살짝 뛰어오르는 프레임의 귀가 잘리지 않게 칸을 위로 늘린다.
    highest = min(bbox(mask)[1] for _, _, mask in finale)
    top = min(top, ground - (finale_ground - highest) - 6)
    cell_h = int(np.ceil((ground - top) * scale)) + int(bottom_margin)

    # (음성 시각, 그림, 마스크, 그림의 어느 점이 칸의 왼쪽 위에 오는지)
    cells = [(max(0.0, time - VOICE_OFFSET), image, mask, (home - reach, top)) for time, image, mask in dance]
    origin = (finale_left, finale_ground - (ground - top))
    for index, (time, part, mask) in enumerate(finale):
        # 클로즈업 대신 춤이 끝나자마자 서 있는 모습을 보여 주고, 나머지는 "부릿!"을 기준으로 시각을 옮긴다.
        when = DANCE_END - VOICE_OFFSET if index == 0 else VOICE_FINALE + (time - VIDEO_FINALE)
        cells.append((when, part, mask, origin))

    rows = (len(cells) + COLUMNS - 1) // COLUMNS
    sheet = np.zeros((rows * cell_h, COLUMNS * cell_w, 4), np.uint8)
    times = []
    for index, (time, image, mask, (left, upper)) in enumerate(cells):
        alpha = cv2.GaussianBlur(mask, (0, 0), 1.2)
        rgba = np.dstack([image, alpha])
        # 그림의 (left, upper) 가 칸의 왼쪽 위에 오도록 옮기고 줄인다.
        matrix = np.float32([[scale, 0, -left * scale], [0, scale, -upper * scale]])
        cell = cv2.warpAffine(rgba, matrix, (cell_w, cell_h), flags=cv2.INTER_AREA, borderValue=(0, 0, 0, 0))
        # 투명한 곳에 배경색이 남지 않게 한다.
        cell[cell[..., 3] == 0] = 0
        y, x = (index // COLUMNS) * cell_h, (index % COLUMNS) * cell_w
        sheet[y:y + cell_h, x:x + cell_w] = cell
        times.append(round(time, 3))
    assert times == sorted(times), "프레임 시각이 순서대로가 아니다"

    cv2.imwrite(str(PET / "song.png"), sheet)
    manifest = {
        "spritesheetPath": "song.png",
        "cellWidth": cell_w,
        "cellHeight": cell_h,
        "columns": COLUMNS,
        # 각 프레임을 보여 주기 시작하는 시각(음성 시작 기준, 초)과 마지막 프레임을 내리는 시각.
        "times": times,
        "end": MOTION_END,
    }
    (PET / "song.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"✔ song.png (춤 {len(dance)}칸 + 마무리 {len(wide)}칸, 칸 {cell_w}×{cell_h}, 배율 {scale:.3f}, 마무리 확대 {zoom:.2f}배), song.json")

    # "부릿!" 부분만 따로: 서 있다가 다리를 꼬는 마무리 칸들과, 음성 파일의 그 구간.
    count = len(finale)
    strip = np.zeros((cell_h, count * cell_w, 4), np.uint8)
    for index in range(count):
        source = len(cells) - count + index
        y, x = (source // COLUMNS) * cell_h, (source % COLUMNS) * cell_w
        strip[:, index * cell_w:(index + 1) * cell_w] = sheet[y:y + cell_h, x:x + cell_w]
    cv2.imwrite(str(PET / "burit.png"), strip)
    # 서 있는 칸으로 시작하고, 다리 꼬는 칸들은 노래에서와 같은 간격으로 잇는다.
    burit_times = [0.0] + [round(t - BURIT_START, 3) for t in times[-(count - 1):]]
    (PET / "burit.json").write_text(json.dumps({
        "spritesheetPath": "burit.png",
        "cellWidth": cell_w,
        "cellHeight": cell_h,
        "columns": count,
        "times": burit_times,
        # 다리 꼰 자세로 잠깐 머물렀다가 처음부터 다시 돈다.
        "end": BURIT_LOOP,
        "loop": True,
    }, ensure_ascii=False, indent=2) + "\n")
    voices = ROOT / "Resources/Voices"
    subprocess.run([
        "ffmpeg", "-v", "error", "-y", "-ss", str(BURIT_START), "-i", str(voices / "usagi---u-una-na-ya-ha.mp3"),
        # 잘린 자리에서 딱 소리가 나지 않게 아주 짧게 키우며 시작한다.
        "-af", "afade=t=in:d=0.02", "-codec:a", "libmp3lame", "-q:a", "2", str(voices / "usagi---burit.mp3"),
    ], check=True)
    print(f"✔ burit.png ({count}칸), burit.json, usagi---burit.mp3 (노래의 {BURIT_START}초부터)")


if __name__ == "__main__":
    main()
