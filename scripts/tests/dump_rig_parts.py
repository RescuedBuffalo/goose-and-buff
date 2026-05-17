"""
Dump each connected component of a rigging sheet as its own PNG, with the
component index baked into the filename. Pair with find_rig_parts.py output
so we can visually match each crop to its part label.

Usage:
    python scripts/tests/dump_rig_parts.py design/assets/characters/buffalo_rigging_sheet.png /tmp/rig_dump

Writes:
    /tmp/rig_dump/00_x72_y34_w246_h368.png ...
"""

from __future__ import annotations
import sys
from collections import deque
from pathlib import Path

from PIL import Image


MIN_AREA = 400


def find_components(img: Image.Image, alpha_thresh: int = 128):
    w, h = img.size
    px = img.load()
    visited = bytearray(w * h)
    components = []

    def is_opaque(x: int, y: int) -> bool:
        return px[x, y][3] >= alpha_thresh

    for sy in range(h):
        for sx in range(w):
            if visited[sy * w + sx]:
                continue
            if not is_opaque(sx, sy):
                visited[sy * w + sx] = 1
                continue
            queue = deque([(sx, sy)])
            visited[sy * w + sx] = 1
            min_x, max_x = sx, sx
            min_y, max_y = sy, sy
            area = 0
            while queue:
                x, y = queue.popleft()
                area += 1
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        idx = ny * w + nx
                        if not visited[idx] and is_opaque(nx, ny):
                            visited[idx] = 1
                            queue.append((nx, ny))
            if area >= MIN_AREA:
                components.append({
                    "bbox": (min_x, min_y, max_x - min_x + 1, max_y - min_y + 1),
                    "area": area,
                })
    return components


def main():
    if len(sys.argv) < 3:
        print("usage: dump_rig_parts.py <png> <out_dir>")
        sys.exit(1)
    src = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    img = Image.open(src).convert("RGBA")
    comps = find_components(img)
    comps.sort(key=lambda c: (c["bbox"][1] // 50, c["bbox"][0]))
    for i, c in enumerate(comps):
        x, y, w, h = c["bbox"]
        crop = img.crop((x, y, x + w, y + h))
        name = f"{i:02d}_x{x}_y{y}_w{w}_h{h}.png"
        crop.save(out_dir / name)
    print(f"wrote {len(comps)} crops to {out_dir}")


if __name__ == "__main__":
    main()
