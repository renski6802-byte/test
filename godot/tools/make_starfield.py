#!/usr/bin/env python3
"""히파르코스 성표를 게임이 읽을 작은 파일로 굽는다.

왜 이런 짓을 하냐면 — 원본은 117,955개 32MB 다. 그중 바다에서 육안으로 보이는
것은 6.5등급까지, 약 8천 개다. 그 8천 개만 남기고 자리·밝기·색을 각각
정수로 눌러 담으면 48KB 가 된다. 웹으로 통째로 실어 보내도 부담이 없다.

원본 구하기:
    pip download --no-deps -d . hipparcos-catalog
    unzip -o hipparcos_catalog-*.whl

쓰는 법:
    python3 godot/tools/make_starfield.py hip2.dat godot/data/stars.bin

담기는 것 (별 하나에 6바이트):
    적경  uint16   0~360도를 65536 단계로   (20각초, 눈이 가르는 것보다 촘촘)
    적위  int16    -90~90도
    밝기  uint8    -2~14등급
    색    uint8    B-V -0.5~3.5
좌표계는 J2000 이다. 시대에 맞춘 세차 보정은 게임 쪽에서 회전으로 건다.
"""

import math
import struct
import sys
from pathlib import Path

MAG_LIMIT = 6.5         ## 육안 한계. 불빛 없는 바다 기준이다.
MAG_MIN = -2.0
MAG_SPAN = 16.0
BV_MIN = -0.5
BV_SPAN = 4.0

MAGIC = b"STR1"


def read(src: Path):
    out = []
    for line in src.open():
        f = line.split()
        if len(f) < 24:
            continue
        try:
            ra = math.degrees(float(f[4])) % 360.0
            dec = math.degrees(float(f[5]))
            mag = float(f[19])
            bv = float(f[23])
        except ValueError:
            continue
        if mag > MAG_LIMIT or not -90.0 <= dec <= 90.0:
            continue
        out.append((ra, dec, mag, bv))
    out.sort(key=lambda s: s[2])        # 밝은 것부터. 잘라 쓰기 좋게.
    return out


def pack(stars) -> bytes:
    buf = bytearray(MAGIC)
    buf += struct.pack("<I", len(stars))
    for ra, dec, mag, bv in stars:
        buf += struct.pack(
            "<HhBB",
            min(65535, int(ra / 360.0 * 65536.0)),
            max(-32767, min(32767, int(dec / 90.0 * 32767.0))),
            max(0, min(255, int((mag - MAG_MIN) / MAG_SPAN * 255.0))),
            max(0, min(255, int((bv - BV_MIN) / BV_SPAN * 255.0))),
        )
    return bytes(buf)


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__)
        raise SystemExit(1)
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    stars = read(src)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(pack(stars))
    print(f"{len(stars)}개 별 → {dst}  ({dst.stat().st_size / 1024:.1f} KB)")
    print(f"가장 밝은 별: 적경 {stars[0][0]:.3f}도  적위 {stars[0][1]:.3f}도  "
          f"{stars[0][2]:.2f}등급")


if __name__ == "__main__":
    main()
